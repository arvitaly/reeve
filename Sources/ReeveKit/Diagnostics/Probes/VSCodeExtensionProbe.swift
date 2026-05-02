import Foundation

public struct VSCodeExtensionProbe: DiagnosticProbe, Sendable {
    public let probeID = "vscode.extensions"
    public let displayName = "Extensions"

    public init() {}

    public func run(context: ProbeContext) async -> [Finding] {
        let extPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".vscode/extensions")

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: extPath.path) else {
            return []
        }

        let count = contents.filter { !$0.hasPrefix(".") }.count
        guard count > 30 else { return [] }

        return [Finding(
            cause: "\(count) VS Code extensions installed",
            evidence: "Each active extension runs JS in the extension host process — memory scales with count",
            severity: count > 60 ? .actionable : .advisory,
            suggestedRemediation: Remediation(
                kind: .reveal(path: extPath.path),
                title: "Show extensions",
                detail: "Disable unused extensions to reduce memory"
            )
        )]
    }
}
