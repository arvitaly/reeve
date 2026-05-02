import Foundation

public struct XcodeDerivedDataProbe: DiagnosticProbe, Sendable {
    public let probeID = "xcode.deriveddata"
    public let displayName = "DerivedData"

    public init() {}

    public func run(context: ProbeContext) async -> [Finding] {
        let ddPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")

        guard FileManager.default.fileExists(atPath: ddPath.path) else { return [] }

        let size = directorySize(at: ddPath)
        let gb = Double(size) / 1_073_741_824
        guard gb > 5 else { return [] }

        return [Finding(
            cause: String(format: "DerivedData: %.1f GB on disk", gb),
            evidence: "Build artifacts accumulate across projects — safe to clear, Xcode rebuilds as needed",
            severity: gb > 20 ? .actionable : .advisory,
            suggestedRemediation: Remediation(
                kind: .clear(path: ddPath.path, label: "DerivedData"),
                title: "Clear DerivedData",
                detail: String(format: "Frees %.1f GB — next build will be slower", gb)
            )
        )]
    }

    private func directorySize(at url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: keys),
               let size = values.totalFileAllocatedSize {
                total += UInt64(size)
            }
        }
        return total
    }
}
