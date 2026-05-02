import Darwin
import Foundation

public struct ReeveSelfProbe: DiagnosticProbe, Sendable {
    public let probeID = "reeve.self"
    public let displayName = "Reeve Self-Audit"

    public init() {}

    public func run(context: ProbeContext) async -> [Finding] {
        guard context.processes.contains(where: { $0.isReeve }) else { return [] }

        let pid = ProcessRecord.reevePID
        let categories = RegionInspector.inspect(pid: pid)
        guard !categories.isEmpty else { return [] }

        let totalResident = categories.reduce(0 as UInt64) { $0 + $1.residentBytes }
        let totalMB = totalResident / (1024 * 1024)

        let top3 = categories.prefix(3).map { cat in
            "\(cat.label): \(cat.residentBytes / (1024 * 1024)) MB"
        }.joined(separator: ", ")

        var findings: [Finding] = []

        findings.append(Finding(
            cause: "Reeve resident: \(totalMB) MB",
            evidence: top3,
            severity: .info
        ))

        if totalMB > 100 {
            findings.append(Finding(
                cause: "Reeve using \(totalMB) MB — higher than expected",
                evidence: "Snapshot history, icon cache, and sparkline buffers are the typical sources",
                severity: .advisory
            ))
        }

        return findings
    }
}
