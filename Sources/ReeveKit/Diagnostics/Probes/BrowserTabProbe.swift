import Foundation

public struct BrowserTabProbe: DiagnosticProbe, Sendable {
    public let probeID = "browser.tabs"
    public let displayName = "Browser Tabs"

    private static let rendererNames: Set<String> = [
        "Google Chrome Helper (Renderer)",
        "Google Chrome Helper (GPU)",
        "Brave Browser Helper (Renderer)",
        "Brave Browser Helper (GPU)",
        "Microsoft Edge Helper (Renderer)",
        "Opera Helper (Renderer)",
        "Vivaldi Helper (Renderer)",
    ]

    private static let electronRendererSuffix = "Helper (Renderer)"

    public init() {}

    public func run(context: ProbeContext) async -> [Finding] {
        let renderers = context.processes.filter { proc in
            Self.rendererNames.contains(proc.name) ||
            proc.name.hasSuffix(Self.electronRendererSuffix)
        }
        guard renderers.count > 10 else { return [] }

        let totalMB = renderers.reduce(0 as UInt64) { $0 + $1.effectiveMemory } / (1024 * 1024)
        let severity: Finding.Confidence = renderers.count > 30 ? .actionable : .advisory

        return [Finding(
            cause: "\(renderers.count) renderer processes (\(totalMB) MB)",
            evidence: "Each tab/extension runs in its own process — memory scales linearly with tab count",
            severity: severity,
            suggestedRemediation: Remediation(
                kind: .reduceProcesses(hint: "Close unused tabs to free ~\(totalMB / UInt64(renderers.count)) MB each"),
                title: "Close tabs",
                detail: "Each renderer averages \(totalMB / UInt64(renderers.count)) MB"
            )
        )]
    }
}
