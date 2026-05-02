import Foundation

public enum ProbeRegistry {
    private static let universalProbes: [any DiagnosticProbe] = [
        UniversalVMTagProbe(),
    ]

    private static let bundleProbes: [(prefix: String, probes: [any DiagnosticProbe])] = [
        ("com.apple.finder", [FinderDesktopProbe()]),
        ("com.apple.Safari", [SafariTabProbe()]),
        ("com.google.Chrome", [BrowserTabProbe()]),
        ("com.brave.Browser", [BrowserTabProbe()]),
        ("com.microsoft.edgemac", [BrowserTabProbe()]),
        ("com.operasoftware.Opera", [BrowserTabProbe()]),
        ("com.vivaldi.Vivaldi", [BrowserTabProbe()]),
        ("company.thebrowser.Browser", [BrowserTabProbe()]),
        ("com.apple.dt.Xcode", [XcodeDerivedDataProbe()]),
        ("com.docker.", [DockerMemoryProbe()]),
        ("com.microsoft.VSCode", [VSCodeExtensionProbe()]),
        ("com.todesktop.230313mzl4w4u92", [VSCodeExtensionProbe()]),
        ("dev.zed.Zed", []),
        ("com.tinyspeck.slackmacgap", [BrowserTabProbe()]),
        ("com.hnc.Discord", [BrowserTabProbe()]),
    ]

    private static let selfProbe = ReeveSelfProbe()

    public static func probes(for context: ProbeContext) -> [any DiagnosticProbe] {
        var result: [any DiagnosticProbe] = universalProbes

        if context.processes.contains(where: { $0.isReeve }) {
            result.append(selfProbe)
        }

        if let bid = context.bundleID {
            for (prefix, probes) in bundleProbes {
                if bid.localizedCaseInsensitiveContains(prefix) {
                    result.append(contentsOf: probes)
                }
            }
        }

        return result
    }

    public static func runAll(
        context: ProbeContext,
        cache: DiagnosticCache
    ) async -> [Finding] {
        let probes = probes(for: context)
        guard !probes.isEmpty else { return [] }
        let cacheKey = context.bundleID ?? context.displayName
        var all: [Finding] = []
        for probe in probes {
            if let cached = await cache.get(key: cacheKey, probeID: probe.probeID) {
                all.append(contentsOf: cached)
                continue
            }
            let findings = await probe.run(context: context)
            await cache.set(key: cacheKey, probeID: probe.probeID, findings: findings)
            all.append(contentsOf: findings)
        }
        return all.sorted { $0.severity > $1.severity }
    }
}
