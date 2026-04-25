import Darwin
import Foundation

public actor ProcessSampler {
    private var cpuBaselines: [pid_t: UInt64] = [:]
    private var lastSampleTime: ContinuousClock.Instant = .now

    public init() {}

    public func sample() -> SystemSnapshot {
        let now = ContinuousClock.now
        let elapsed = now - lastSampleTime
        let elapsedNanos = max(1, elapsed.components.seconds * 1_000_000_000
            + elapsed.components.attoseconds / 1_000_000_000)

        let pids = listAllPIDs()
        var newBaselines: [pid_t: UInt64] = [:]
        newBaselines.reserveCapacity(pids.count)

        let processes: [ProcessInfo] = pids.compactMap { pid in
            var taskInfo = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, size) == size else {
                return nil
            }

            let totalCPUNanos = taskInfo.pti_total_user &+ taskInfo.pti_total_system
            newBaselines[pid] = totalCPUNanos

            let cpuPercent: Double = {
                guard let prev = cpuBaselines[pid], totalCPUNanos >= prev else { return 0 }
                return min(100.0, Double(totalCPUNanos - prev) / Double(elapsedNanos) * 100.0)
            }()

            var nameBuffer = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = String(cString: nameBuffer)

            return ProcessInfo(
                pid: pid,
                name: name.isEmpty ? "<\(pid)>" : name,
                residentMemory: taskInfo.pti_resident_size,
                cpuPercent: cpuPercent
            )
        }

        cpuBaselines = newBaselines
        lastSampleTime = now
        return SystemSnapshot(processes: processes, sampledAt: .now)
    }

    private func listAllPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        // Allocate extra to handle processes spawned between the two calls
        var buffer = [pid_t](repeating: 0, count: Int(count) + 64)
        let actual = proc_listallpids(&buffer, Int32(buffer.count * MemoryLayout<pid_t>.stride))
        guard actual > 0 else { return [] }
        return Array(buffer.prefix(Int(actual)))
    }
}
