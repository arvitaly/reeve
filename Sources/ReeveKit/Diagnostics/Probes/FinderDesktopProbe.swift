import Foundation

public struct FinderDesktopProbe: DiagnosticProbe, Sendable {
    public let probeID = "finder.desktop"
    public let displayName = "Desktop Files"

    public init() {}

    public func run(context: ProbeContext) async -> [Finding] {
        var findings: [Finding] = []

        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
        if let count = fileCount(at: desktopURL), count > 50 {
            let estimatedMB = count / 10
            findings.append(Finding(
                cause: "\(count) files on Desktop",
                evidence: "Finder indexes every Desktop item for thumbnails and spatial layout — each costs resident memory",
                severity: count > 500 ? .actionable : .advisory,
                suggestedRemediation: Remediation(
                    kind: .reveal(path: desktopURL.path),
                    title: "Open Desktop in Finder",
                    detail: "Move files to a subfolder to reduce Finder memory by ~\(estimatedMB) MB"
                )
            ))
        }

        let qlCacheURL = quickLookCacheURL()
        if let qlCacheURL, let size = directorySize(at: qlCacheURL), size > 100_000_000 {
            let mb = size / (1024 * 1024)
            findings.append(Finding(
                cause: "QuickLook thumbnail cache: \(mb) MB",
                evidence: "Cached thumbnails for previewed files — safe to clear, rebuilds on demand",
                severity: mb > 500 ? .actionable : .advisory,
                suggestedRemediation: Remediation(
                    kind: .clear(path: qlCacheURL.path, label: "QuickLook cache"),
                    title: "Clear thumbnail cache",
                    detail: "Frees \(mb) MB — thumbnails rebuild as needed"
                )
            ))
        }

        return findings
    }

    private func fileCount(at url: URL) -> Int? {
        try? FileManager.default.contentsOfDirectory(atPath: url.path).count
    }

    private func quickLookCacheURL() -> URL? {
        guard let tmpDir = ProcessInfo.processInfo.environment["TMPDIR"] else { return nil }
        let tmp = URL(fileURLWithPath: tmpDir)
        let cache = tmp.deletingLastPathComponent()
            .appendingPathComponent("C")
            .appendingPathComponent("com.apple.QuickLook.thumbnailcache")
        guard FileManager.default.fileExists(atPath: cache.path) else { return nil }
        return cache
    }

    private func directorySize(at url: URL) -> UInt64? {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return nil }
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
