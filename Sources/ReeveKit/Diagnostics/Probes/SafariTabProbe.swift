import Foundation

public struct SafariTabProbe: DiagnosticProbe, Sendable {
    public let probeID = "safari.tabs"
    public let displayName = "Safari Tabs"

    public init() {}

    public func run(context: ProbeContext) async -> [Finding] {
        let script = """
        tell application "Safari"
            set tabCount to 0
            repeat with w in windows
                set tabCount to tabCount + (count of tabs of w)
            end repeat
            return tabCount
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else { return [] }

        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)

        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            // -1743 = Automation permission denied
            if code == -1743 || code == -1744 {
                return [Finding(
                    cause: "Safari tab count unavailable",
                    evidence: "Reeve needs Automation permission to count Safari tabs",
                    severity: .info,
                    suggestedRemediation: Remediation(
                        kind: .openSettings(
                            urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
                        ),
                        title: "Grant permission",
                        detail: "Privacy & Security → Automation → Reeve → Safari"
                    )
                )]
            }
            return []
        }

        let tabCount = Int(result.int32Value)
        guard tabCount > 10 else { return [] }

        let estimatedMB = tabCount * 80

        return [Finding(
            cause: "\(tabCount) Safari tabs open",
            evidence: "Each tab uses ~80 MB — Safari shares rendering across fewer processes than Chrome",
            severity: tabCount > 30 ? .actionable : .advisory,
            suggestedRemediation: Remediation(
                kind: .reduceProcesses(hint: "Close unused tabs to free ~\(estimatedMB) MB"),
                title: "Close tabs",
                detail: "~\(estimatedMB) MB estimated across \(tabCount) tabs"
            )
        )]
    }
}
