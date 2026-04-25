import Foundation
import Darwin

public struct ProcessInfo: Identifiable, Sendable, Hashable {
    public let pid: pid_t
    public let name: String
    public let residentMemory: UInt64
    public let cpuPercent: Double

    public var id: pid_t { pid }

    // Self-referential audit: Reeve's PID is captured once at launch.
    // No special handling — if Reeve ranks high, it ranks high.
    public static let reevePID: pid_t = getpid()
    public var isReeve: Bool { pid == ProcessInfo.reevePID }

    public var formattedMemory: String {
        ByteCountFormatter.string(fromByteCount: Int64(residentMemory), countStyle: .memory)
    }

    public var formattedCPU: String {
        String(format: "%.1f%%", cpuPercent)
    }
}

public struct SystemSnapshot: Sendable {
    public let processes: [ProcessInfo]
    public let sampledAt: Date

    public static let empty = SystemSnapshot(processes: [], sampledAt: .now)

    public var topByMemory: [ProcessInfo] {
        processes.sorted { $0.residentMemory > $1.residentMemory }
    }

    public var topByCPU: [ProcessInfo] {
        processes.sorted { $0.cpuPercent > $1.cpuPercent }
    }
}
