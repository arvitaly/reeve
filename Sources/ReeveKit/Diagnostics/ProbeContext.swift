import Foundation

public struct ProbeContext: Sendable {
    public let bundleID: String?
    public let displayName: String
    public let processes: [ProcessRecord]
    public let totalMemory: UInt64
    public let snapshot: SystemSnapshot

    public init(
        bundleID: String?, displayName: String,
        processes: [ProcessRecord], totalMemory: UInt64,
        snapshot: SystemSnapshot
    ) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.processes = processes
        self.totalMemory = totalMemory
        self.snapshot = snapshot
    }

    public var leadPID: pid_t? { processes.first?.pid }
}
