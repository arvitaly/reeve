@preconcurrency import Darwin
import Foundation
import IOKit

private let kPageSize = UInt64(vm_kernel_page_size)

/// Actor that reads live process data from the kernel using public libproc APIs.
///
/// CPU% and disk I/O rates are computed as deltas between consecutive calls to `sample()`.
/// The first call returns 0 for all delta-based metrics; meaningful values appear on the
/// second call.
///
/// All system calls (`proc_listallpids`, `proc_pidinfo`, `proc_name`, `proc_pid_rusage`)
/// are documented in `/usr/include/libproc.h` and the Darwin man pages. No private APIs
/// are used. `proc_pid_rusage` returns EPERM for processes owned by other users; those
/// processes are reported with zero disk rates.
public actor ProcessSampler {
    private var cpuBaselines: [pid_t: UInt64] = [:]
    private var diskBaselines: [pid_t: (read: UInt64, write: UInt64)] = [:]
    private var lastSampleTime: ContinuousClock.Instant = .now
    // ProcessInfo.processInfo.physicalMemory is a constant on a running machine
    private let physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory

    public init() {}

    /// Captures a `SystemSnapshot` with current CPU, memory, and disk I/O for every
    /// visible process.
    public func sample() -> SystemSnapshot {
        let now = ContinuousClock.now
        let elapsed = now - lastSampleTime
        let elapsedNanos = max(1, elapsed.components.seconds * 1_000_000_000
            + elapsed.components.attoseconds / 1_000_000_000)
        let elapsedSec = max(1, elapsed.components.seconds)

        let pids = listAllPIDs()
        var newCPUBaselines: [pid_t: UInt64] = [:]
        var newDiskBaselines: [pid_t: (read: UInt64, write: UInt64)] = [:]
        newCPUBaselines.reserveCapacity(pids.count)
        newDiskBaselines.reserveCapacity(pids.count)

        let processes: [ProcessRecord] = pids.compactMap { pid in
            var taskInfo = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, size) == size else {
                return nil
            }

            let totalCPUNanos = taskInfo.pti_total_user &+ taskInfo.pti_total_system
            newCPUBaselines[pid] = totalCPUNanos

            let cpuPercent: Double = {
                guard let prev = cpuBaselines[pid], totalCPUNanos >= prev else { return 0 }
                return min(100.0, Double(totalCPUNanos - prev) / Double(elapsedNanos) * 100.0)
            }()

            // Disk I/O — RUSAGE_INFO_V4 gives cumulative bytes since process start.
            // EPERM is expected for other users' processes; treat as zero rate.
            // proc_pid_rusage declares its 3rd parameter as rusage_info_t* (void**) but
            // actually treats the argument VALUE as void* (address of the struct). We use
            // unsafeBitCast to pass the struct address without Swift reinterpreting the
            // pointee — the same trick the C cast (rusage_info_t *)&ri performs.
            var rusage = rusage_info_v4()
            let diskReadRate: UInt64
            let diskWriteRate: UInt64
            let rusageOK = withUnsafeMutablePointer(to: &rusage) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            if rusageOK == 0, let prev = diskBaselines[pid] {
                let readDelta = rusage.ri_diskio_bytesread >= prev.read
                    ? rusage.ri_diskio_bytesread - prev.read : 0
                let writeDelta = rusage.ri_diskio_byteswritten >= prev.write
                    ? rusage.ri_diskio_byteswritten - prev.write : 0
                diskReadRate  = readDelta  / UInt64(elapsedSec)
                diskWriteRate = writeDelta / UInt64(elapsedSec)
            } else {
                diskReadRate  = 0
                diskWriteRate = 0
            }
            if rusageOK == 0 {
                newDiskBaselines[pid] = (rusage.ri_diskio_bytesread, rusage.ri_diskio_byteswritten)
            }

            var nameBuffer = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = String(cString: nameBuffer)

            // PROC_PIDT_SHORTBSDINFO (sys/proc_info.h §13) exposes pbsi_ppid and pbsi_status.
            // pbsi_status == 4 (SSTOP) means the process is suspended via SIGSTOP.
            var bsdInfo = proc_bsdshortinfo()
            let bsdSize = Int32(MemoryLayout<proc_bsdshortinfo>.size)
            let parentPID: pid_t
            let isSuspended: Bool
            if proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &bsdInfo, bsdSize) == bsdSize {
                parentPID = pid_t(bsdInfo.pbsi_ppid)
                isSuspended = bsdInfo.pbsi_status == 4   // SSTOP
            } else {
                parentPID = 0
                isSuspended = false
            }

            // UNIX nice value via getpriority(PRIO_PROCESS). Documented in getpriority(2).
            Darwin.errno = 0
            let rawNice = getpriority(PRIO_PROCESS, UInt32(pid))
            let niceValue: Int32 = Darwin.errno == 0 ? rawNice : 0

            return ProcessRecord(
                pid: pid,
                name: name.isEmpty ? "<\(pid)>" : name,
                residentMemory: taskInfo.pti_resident_size,
                cpuPercent: cpuPercent,
                parentPID: parentPID,
                physFootprint: rusageOK == 0 ? rusage.ri_phys_footprint : nil,
                diskReadRate: diskReadRate,
                diskWriteRate: diskWriteRate,
                isSuspended: isSuspended,
                niceValue: niceValue
            )
        }

        cpuBaselines = newCPUBaselines
        diskBaselines = newDiskBaselines
        lastSampleTime = now

        let totalCPU = processes.reduce(0.0) { $0 + $1.cpuPercent }
        let footprintSum = processes.reduce(UInt64(0)) { $0 + ($1.physFootprint ?? 0) }
        let epermRSS = processes.filter { $0.physFootprint == nil }
            .reduce(UInt64(0)) { $0 + $1.residentMemory }
        let visiblePIDs = Set(processes.map { $0.pid })
        let invisible = collectInvisibleProcesses(allPIDs: pids, visiblePIDs: visiblePIDs)
        let breakdown = sampleMemoryBreakdown()
        return SystemSnapshot(
            processes: processes,
            sampledAt: .now,
            physicalMemory: physicalMemory,
            usedMemory: breakdown.map { $0.used },
            memoryBreakdown: breakdown,
            totalCPU: totalCPU,
            processFootprintSum: footprintSum,
            epermProcessRSS: epermRSS,
            invisibleProcesses: invisible
        )
    }

    // host_statistics64 / HOST_VM_INFO64 — documented in <mach/host_info.h>.
    private func sampleMemoryBreakdown() -> MemoryBreakdown? {
        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kr: kern_return_t = withUnsafeMutablePointer(to: &vmStats) { statsPtr in
            statsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let ps = kPageSize
        let internal_ = UInt64(vmStats.internal_page_count) * ps
        let purgeable = UInt64(vmStats.purgeable_count) * ps
        return MemoryBreakdown(
            wired: UInt64(vmStats.wire_count) * ps,
            active: UInt64(vmStats.active_count) * ps,
            compressed: UInt64(vmStats.compressor_page_count) * ps,
            inactive: UInt64(vmStats.inactive_count) * ps,
            free: UInt64(vmStats.free_count) * ps,
            appMemory: internal_ > purgeable ? internal_ - purgeable : 0,
            gpuInUse: Self.sampleGPUMemory()
        )
    }

    /// IOKit IOAccelerator → PerformanceStatistics → "In use system memory".
    /// Documented in IOKit.framework; property keys visible via `ioreg -r -c IOAccelerator`.
    private static func sampleGPUMemory() -> UInt64 {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOAccelerator") else { return 0 }
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }
        var total: UInt64 = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let stats = dict["PerformanceStatistics"] as? [String: Any],
               let inUse = stats["In use system memory"] as? UInt64 {
                total += inUse
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return total
    }

    private func collectInvisibleProcesses(allPIDs: [pid_t], visiblePIDs: Set<pid_t>) -> [InvisibleProcess] {
        let rssMap = Self.psRSSMap()
        return allPIDs.compactMap { pid -> InvisibleProcess? in
            guard !visiblePIDs.contains(pid) else { return nil }
            var bsd = proc_bsdshortinfo()
            let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &bsd, size) == size else { return nil }
            let name = withUnsafePointer(to: bsd.pbsi_comm) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) }
            }
            guard !name.isEmpty else { return nil }
            return InvisibleProcess(pid: pid, name: name, uid: bsd.pbsi_uid, rssBytes: rssMap[pid] ?? 0)
        }
    }

    /// `ps -axo pid=,rss=` uses com.apple.system-task-ports.read entitlement to read
    /// RSS for all processes including root-owned. Documented in ps(1). ~15ms.
    private static func psRSSMap() -> [pid_t: UInt64] {
        let proc = Foundation.Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-axo", "pid=,rss="]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }
        var map: [pid_t: UInt64] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2,
                  let pid = Int32(parts[0].trimmingCharacters(in: .whitespaces)),
                  let rssKB = UInt64(parts[1].trimmingCharacters(in: .whitespaces))
            else { continue }
            map[pid] = rssKB * 1024
        }
        return map
    }

    private func listAllPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var buffer = [pid_t](repeating: 0, count: Int(count) + 64)
        let actual = proc_listallpids(&buffer, Int32(buffer.count * MemoryLayout<pid_t>.stride))
        guard actual > 0 else { return [] }
        return Array(buffer.prefix(Int(actual)))
    }
}
