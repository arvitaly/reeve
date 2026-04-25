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

    public var id: pid_t { pid }

    // Self-referential audit: Reeve's PID is captured once at launch.
    // No special handling — if Reeve ranks high, it ranks high.
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

    /// All processes sorted from highest to lowest CPU usage.
    public var topByCPU: [ProcessRecord] {
        processes.sorted { $0.cpuPercent > $1.cpuPercent }
    }
}
