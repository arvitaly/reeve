import Foundation

public struct DockerMemoryProbe: DiagnosticProbe, Sendable {
    public let probeID = "docker.memory"
    public let displayName = "Docker VM"

    public init() {}

    public func run(context: ProbeContext) async -> [Finding] {
        let settingsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.docker/settings.json")

        guard let data = try? Data(contentsOf: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let memoryMiB = json["memoryMiB"] as? Int else {
            return []
        }

        let gb = Double(memoryMiB) / 1024
        guard gb > 4 else { return [] }

        return [Finding(
            cause: String(format: "Docker VM allocated %.1f GB", gb),
            evidence: "Docker Desktop reserves a fixed memory block for its Linux VM — unused portion is wasted",
            severity: gb > 8 ? .actionable : .advisory,
            suggestedRemediation: Remediation(
                kind: .openSettings(urlString: "docker://dashboard/settings/resources"),
                title: "Docker settings",
                detail: String(format: "Current: %.0f GB — reduce if workloads allow", gb)
            )
        )]
    }
}
