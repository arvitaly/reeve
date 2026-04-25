import Darwin
import Foundation

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
                proc_pid_rusage(pid, RUSAGE_INFO_V4,
                    unsafeBitCast(ptr, to: UnsafeMutablePointer<rusage_info_t?>.self))
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

            return ProcessRecord(
                pid: pid,
                name: name.isEmpty ? "<\(pid)>" : name,
                residentMemory: taskInfo.pti_resident_size,
                cpuPercent: cpuPercent,
                diskReadRate: diskReadRate,
                diskWriteRate: diskWriteRate
            )
        }

        cpuBaselines = newCPUBaselines
        diskBaselines = newDiskBaselines
        lastSampleTime = now
        return SystemSnapshot(processes: processes, sampledAt: .now)
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
