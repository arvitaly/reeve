import Foundation
import Darwin

/// A point-in-time snapshot of a single process, captured from the kernel via libproc.
///
/// `isReeve` is a structural property, not a filter. If Reeve ranks high, it ranks high.
public struct ProcessRecord: Identifiable, Sendable, Hashable {
    public let pid: pid_t
    /// Parent PID from proc_bsdshortinfo (pbsi_ppid). Zero when unavailable.
    public let parentPID: pid_t
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
    /// True when pbsi_status == SSTOP (4) — process is suspended via SIGSTOP.
    public let isSuspended: Bool
    /// UNIX nice value from getpriority(PRIO_PROCESS). 0 = normal, positive = lower priority.
    public let niceValue: Int32

    public var id: pid_t { pid }

    // Self-referential audit: Reeve's PID is captured once at launch.
    // No special handling — if Reeve ranks high, it ranks high.
    public init(
        pid: pid_t, name: String, residentMemory: UInt64, cpuPercent: Double,
        parentPID: pid_t = 0, diskReadRate: UInt64 = 0, diskWriteRate: UInt64 = 0,
        isSuspended: Bool = false, niceValue: Int32 = 0
    ) {
        self.pid = pid; self.name = name; self.residentMemory = residentMemory
        self.cpuPercent = cpuPercent; self.parentPID = parentPID
        self.diskReadRate = diskReadRate; self.diskWriteRate = diskWriteRate
        self.isSuspended = isSuspended; self.niceValue = niceValue
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
    /// Physical RAM installed on this machine. Static — set once from ProcessInfo.
    public let physicalMemory: UInt64
    /// Kernel-reported used pages (wire + active + compressor) × page size.
    /// Nil when `host_statistics64` fails — honest absence per CLAUDE.md.
    public let usedMemory: UInt64?
    /// Sum of all process CPU percentages.
    public let totalCPU: Double

    public init(
        processes: [ProcessRecord],
        sampledAt: Date,
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory,
        usedMemory: UInt64? = nil,
        totalCPU: Double = 0
    ) {
        self.processes = processes
        self.sampledAt = sampledAt
        self.physicalMemory = physicalMemory
        self.usedMemory = usedMemory
        self.totalCPU = totalCPU
    }

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

    /// Builds the parent-child process tree, returning root nodes (those whose parent is absent
    /// from this snapshot). Roots and siblings are sorted by resident memory descending.
    ///
    /// launchd (PID 1) is root-owned and cannot be sampled via proc_pidinfo. To avoid
    /// promoting all ~300 of its children to top-level roots we insert a synthetic launchd
    /// node so the tree has one meaningful root rather than hundreds.
    public func buildTree() -> [ProcessTreeNode] {
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        var childPIDs: [pid_t: [pid_t]] = [:]
        var rootPIDs: [pid_t] = []
        var launchdChildPIDs: [pid_t] = []

        for process in processes {
            let ppid = process.parentPID
            if ppid != 0 && byPID[ppid] != nil {
                childPIDs[ppid, default: []].append(process.pid)
            } else if ppid == 1 && byPID[1] == nil {
                launchdChildPIDs.append(process.pid)
            } else {
                rootPIDs.append(process.pid)
            }
        }

        func buildNode(_ pid: pid_t, depth: Int) -> ProcessTreeNode {
            let record = byPID[pid]!
            let children = (childPIDs[pid] ?? [])
                .compactMap { byPID[$0] }
                .sorted { $0.residentMemory > $1.residentMemory }
                .map { buildNode($0.pid, depth: depth + 1) }
            return ProcessTreeNode(record: record, children: children, depth: depth)
        }

        var roots = rootPIDs
            .compactMap { byPID[$0] }
            .sorted { $0.residentMemory > $1.residentMemory }
            .map { buildNode($0.pid, depth: 0) }

        if !launchdChildPIDs.isEmpty {
            let synthetic = ProcessRecord(pid: 1, name: "launchd", residentMemory: 0, cpuPercent: 0, parentPID: 0)
            let kids = launchdChildPIDs
                .compactMap { byPID[$0] }
                .sorted { $0.residentMemory > $1.residentMemory }
                .map { buildNode($0.pid, depth: 1) }
            roots.insert(ProcessTreeNode(record: synthetic, children: kids, depth: 0), at: 0)
        }

        return roots
    }
}

/// A node in the process parent-child tree produced by `SystemSnapshot.buildTree()`.
public struct ProcessTreeNode: Sendable, Identifiable {
    public let record: ProcessRecord
    public let children: [ProcessTreeNode]
    public let depth: Int
    public var id: pid_t { record.pid }

    /// Total memory of this subtree (self + all descendants).
    public var subtreeMemory: UInt64 {
        children.reduce(record.residentMemory) { $0 + $1.subtreeMemory }
    }

    /// Depth-first flattening of this node and all descendants.
    public func flattened() -> [ProcessTreeNode] {
        [self] + children.flatMap { $0.flattened() }
    }
}
