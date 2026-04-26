import Foundation
import Darwin

/// A point-in-time snapshot of a single process, captured from the kernel via libproc.
///
/// `isReeve` is a structural property, not a filter. If Reeve ranks high, it ranks high.
public struct ProcessRecord: Identifiable, Sendable, Hashable {
    public let pid: pid_t
    public let name: String
    /// Resident set size in bytes.
    public let residentMemory: UInt64
    /// CPU usage since the previous sample, in percent (0–100). Zero on the first sample.
    public let cpuPercent: Double
    /// Disk bytes read per second since the previous sample. Zero on the first sample or when
    /// the process is owned by a different user (proc_pid_rusage returns EPERM).
    public let diskReadRate: UInt64
    /// Disk bytes written per second since the previous sample. Same caveats as diskReadRate.
    public let diskWriteRate: UInt64

    public var id: pid_t { pid }

    // Self-referential audit: Reeve's PID is captured once at launch.
    // No special handling — if Reeve ranks high, it ranks high.
    public init(
        pid: pid_t, name: String, residentMemory: UInt64, cpuPercent: Double,
        diskReadRate: UInt64 = 0, diskWriteRate: UInt64 = 0
    ) {
        self.pid = pid; self.name = name; self.residentMemory = residentMemory
        self.cpuPercent = cpuPercent; self.diskReadRate = diskReadRate; self.diskWriteRate = diskWriteRate
    }

    public static let reevePID: pid_t = getpid()
    /// `true` when this record describes the running Reeve process itself.
    public var isReeve: Bool { pid == ProcessRecord.reevePID }

    /// Human-readable memory size using binary units (e.g. "128 MB").
    public var formattedMemory: String {
        ByteCountFormatter.string(fromByteCount: Int64(residentMemory), countStyle: .memory)
    }

    /// CPU percentage formatted to one decimal place (e.g. "4.2%").
    public var formattedCPU: String {
        String(format: "%.1f%%", cpuPercent)
    }

    /// Disk read rate, nil when below 1 KB/s (noise floor).
    public var formattedDiskRead: String? {
        guard diskReadRate >= 1024 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(diskReadRate), countStyle: .memory) + "/s ↓"
    }

    /// Disk write rate, nil when below 1 KB/s.
    public var formattedDiskWrite: String? {
        guard diskWriteRate >= 1024 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(diskWriteRate), countStyle: .memory) + "/s ↑"
    }
}

/// An immutable snapshot of the entire process list at a single moment in time.
public struct SystemSnapshot: Sendable {
    public let processes: [ProcessRecord]
    public let sampledAt: Date

    /// An empty snapshot used as the initial published state before the first poll.
    public static let empty = SystemSnapshot(processes: [], sampledAt: .now)

    /// All processes sorted from highest to lowest resident memory.
    public var topByMemory: [ProcessRecord] {
        processes.sorted { $0.residentMemory > $1.residentMemory }
    }

    /// All processes sorted from highest to lowest CPU usage, memory as tiebreaker.
    public var topByCPU: [ProcessRecord] {
        processes.sorted {
            if $0.cpuPercent != $1.cpuPercent { return $0.cpuPercent > $1.cpuPercent }
            return $0.residentMemory > $1.residentMemory
        }
    }

    /// All processes sorted from highest to lowest disk write rate, memory as tiebreaker.
    public var topByDiskWrite: [ProcessRecord] {
        processes.sorted {
            if $0.diskWriteRate != $1.diskWriteRate { return $0.diskWriteRate > $1.diskWriteRate }
            return $0.residentMemory > $1.residentMemory
        }
    }
}
