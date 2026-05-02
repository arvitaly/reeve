import Foundation

public struct UniversalVMTagProbe: DiagnosticProbe, Sendable {
    public let probeID = "universal.vmtags"
    public let displayName = "Memory Regions"

    public init() {}

    public func run(context: ProbeContext) async -> [Finding] {
        guard let pid = context.leadPID else { return [] }
        let categories = RegionInspector.inspect(pid: pid)
        guard !categories.isEmpty else { return [] }

        let totalResident = categories.reduce(0 as UInt64) { $0 + $1.residentBytes }
        guard totalResident > 0 else { return [] }

        var findings: [Finding] = []

        let top = categories.prefix(5)
        let breakdown = top.map { cat in
            let mb = cat.residentBytes / (1024 * 1024)
            let pct = totalResident > 0 ? Int(cat.residentBytes * 100 / totalResident) : 0
            return "\(cat.label): \(mb) MB (\(pct)%)"
        }.joined(separator: ", ")

        findings.append(Finding(
            cause: "Resident by category",
            evidence: breakdown,
            severity: .info
        ))

        for cat in categories {
            let mb = cat.residentBytes / (1024 * 1024)
            switch cat.label {
            case "JavaScriptCore" where mb > 500:
                findings.append(Finding(
                    cause: "JavaScriptCore: \(mb) MB resident",
                    evidence: "JS heap grows with tab/page count and retained objects",
                    severity: .actionable,
                    suggestedRemediation: Remediation(
                        kind: .reduceProcesses(hint: "Close unused tabs or pages"),
                        title: "Close tabs",
                        detail: "Each tab maintains its own JS heap"
                    )
                ))
            case "CGImage" where mb > 200:
                findings.append(Finding(
                    cause: "CGImage buffers: \(mb) MB resident",
                    evidence: "Decoded image bitmaps cached in memory",
                    severity: .advisory
                ))
            case "CoreAnimation" where mb > 200:
                findings.append(Finding(
                    cause: "CoreAnimation layers: \(mb) MB resident",
                    evidence: "GPU-backed layer trees for rendering — scales with visible content",
                    severity: .advisory
                ))
            case "QuickLook Thumbnails" where mb > 100:
                findings.append(Finding(
                    cause: "QuickLook thumbnails: \(mb) MB resident",
                    evidence: "Preview thumbnails for files in open Finder windows",
                    severity: .actionable,
                    suggestedRemediation: Remediation(
                        kind: .reduceProcesses(hint: "Switch Finder to list view or close windows with many files"),
                        title: "Reduce previews",
                        detail: "Icon/Gallery view generates thumbnails per file"
                    )
                ))
            case "SQLite" where mb > 200:
                findings.append(Finding(
                    cause: "SQLite: \(mb) MB resident",
                    evidence: "Database pages mapped into memory — scales with database size",
                    severity: .advisory
                ))
            default:
                break
            }
        }

        return findings
    }
}
