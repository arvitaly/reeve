@preconcurrency import Darwin
import Darwin.Mach
import Foundation
import OSLog
import ReeveKit

/// Wraps `mach_zone_info` to enumerate kernel zones with size and element
/// counts. Returns up to 20 largest zones by allocated bytes plus totals.
///
/// Requires `host_priv` — i.e. the helper must be running as root. On
/// macOS releases that have tightened access (Apple has been progressively
/// restricting Mach kernel APIs), this returns `.error(.macError(...))` and
/// the UI gracefully omits the kernel-zones segment without breaking.
enum KernelZones {
    private static let log = Logger(subsystem: "com.reeve.helper", category: "zones")

    static func snapshot() -> HelperResponse {
        // mach_host_self() returns host_t (host name port). mach_zone_info
        // wants host_priv_t — only obtainable via host_get_host_priv_port for
        // uid 0. Without this redirection the call fails KERN_INVALID_HOST
        // even when running as root.
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        // host_get_host_priv_port is a macro in <mach/host_special_ports.h>:
        //   host_get_special_port(host, HOST_LOCAL_NODE, HOST_PRIV_PORT, port)
        var hostPriv: host_priv_t = HOST_NULL
        let privKR = host_get_special_port(host, HOST_LOCAL_NODE, HOST_PRIV_PORT, &hostPriv)
        guard privKR == KERN_SUCCESS, hostPriv != HOST_NULL else {
            log.info("host_get_special_port(HOST_PRIV_PORT) failed: \(privKR) (uid=\(getuid()))")
            return .error(.macError(message: "host_get_special_port kr=\(privKR)"))
        }
        defer { mach_port_deallocate(mach_task_self_, hostPriv) }

        var namesPtr: mach_zone_name_array_t? = nil
        var namesCnt: mach_msg_type_number_t = 0
        var infoPtr: mach_zone_info_array_t? = nil
        var infoCnt: mach_msg_type_number_t = 0

        let kr = mach_zone_info(hostPriv, &namesPtr, &namesCnt, &infoPtr, &infoCnt)
        guard kr == KERN_SUCCESS,
              let names = namesPtr, let info = infoPtr,
              namesCnt > 0, infoCnt == namesCnt else {
            log.info("mach_zone_info failed: \(kr)")
            return .error(.macError(message: "mach_zone_info kr=\(kr)"))
        }

        defer {
            let nbytes = vm_size_t(MemoryLayout<mach_zone_name_t>.size * Int(namesCnt))
            let ibytes = vm_size_t(MemoryLayout<mach_zone_info_t>.size * Int(infoCnt))
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: names), nbytes)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), ibytes)
        }

        var allocatedTotal: UInt64 = 0
        var freeTotal: UInt64 = 0
        var entries: [ZoneEntry] = []
        entries.reserveCapacity(Int(namesCnt))

        for i in 0..<Int(namesCnt) {
            let nameTuple = names[i].mzn_name
            let nameStr = withUnsafeBytes(of: nameTuple) { raw -> String in
                let bound = raw.bindMemory(to: CChar.self)
                return String(cString: bound.baseAddress!)
            }
            let zone = info[i]
            let allocated = UInt64(zone.mzi_cur_size)
            let elements = UInt64(zone.mzi_count)
            let used = UInt64(zone.mzi_count) * UInt64(zone.mzi_elem_size)
            let free = allocated > used ? allocated - used : 0
            allocatedTotal &+= allocated
            freeTotal &+= free
            entries.append(ZoneEntry(name: nameStr,
                                     allocatedBytes: allocated,
                                     elementCount: elements))
        }

        let top = entries
            .sorted { $0.allocatedBytes > $1.allocatedBytes }
            .prefix(20)
            .map { $0 }

        let snapshot = KernelZoneSnapshot(
            totalAllocatedBytes: allocatedTotal,
            totalFreeBytes: freeTotal,
            topZones: top,
            sampledAt: .now
        )
        return .kernelZones(snapshot)
    }
}
