import XCTest
@testable import ReeveKit

final class ProbeTests: XCTestCase {

    // MARK: - UniversalVMTagProbe

    func testUniversalVMTagProbeID() {
        let probe = UniversalVMTagProbe()
        XCTAssertEqual(probe.probeID, "universal.vmtags")
    }

    func testUniversalVMTagProbeRunsOnSelf() async {
        let ctx = makeContext(pid: getpid(), bundleID: nil, name: "TestProcess")
        let probe = UniversalVMTagProbe()
        let findings = await probe.run(context: ctx)
        XCTAssertFalse(findings.isEmpty, "Should find at least the breakdown finding for own process")
        let breakdown = findings.first { $0.cause == "Resident by category" }
        XCTAssertNotNil(breakdown)
        XCTAssertFalse(breakdown!.evidence.isEmpty)
    }

    // MARK: - BrowserTabProbe

    func testBrowserTabProbeIgnoresFewRenderers() async {
        let procs = (0..<5).map { i in
            ProcessRecord(pid: pid_t(100 + i), name: "Google Chrome Helper (Renderer)",
                          residentMemory: 50_000_000, cpuPercent: 0)
        }
        let ctx = ProbeContext(bundleID: "com.google.Chrome", displayName: "Chrome",
                               processes: procs, totalMemory: 250_000_000, snapshot: .empty)
        let findings = await BrowserTabProbe().run(context: ctx)
        XCTAssertTrue(findings.isEmpty, "Should not report with <= 10 renderers")
    }

    func testBrowserTabProbeReportsManyRenderers() async {
        let procs = (0..<25).map { i in
            ProcessRecord(pid: pid_t(100 + i), name: "Google Chrome Helper (Renderer)",
                          residentMemory: 100_000_000, cpuPercent: 0)
        }
        let ctx = ProbeContext(bundleID: "com.google.Chrome", displayName: "Chrome",
                               processes: procs, totalMemory: 2_500_000_000, snapshot: .empty)
        let findings = await BrowserTabProbe().run(context: ctx)
        XCTAssertEqual(findings.count, 1)
        XCTAssertTrue(findings[0].cause.contains("25"))
        XCTAssertEqual(findings[0].severity, .advisory)
    }

    func testBrowserTabProbeActionableAbove30() async {
        let procs = (0..<35).map { i in
            ProcessRecord(pid: pid_t(100 + i), name: "Google Chrome Helper (Renderer)",
                          residentMemory: 100_000_000, cpuPercent: 0)
        }
        let ctx = ProbeContext(bundleID: "com.google.Chrome", displayName: "Chrome",
                               processes: procs, totalMemory: 3_500_000_000, snapshot: .empty)
        let findings = await BrowserTabProbe().run(context: ctx)
        XCTAssertEqual(findings.first?.severity, .actionable)
    }

    func testBrowserTabProbeDetectsElectron() async {
        let procs = (0..<15).map { i in
            ProcessRecord(pid: pid_t(100 + i), name: "Slack Helper (Renderer)",
                          residentMemory: 80_000_000, cpuPercent: 0)
        }
        let ctx = ProbeContext(bundleID: "com.tinyspeck.slackmacgap", displayName: "Slack",
                               processes: procs, totalMemory: 1_200_000_000, snapshot: .empty)
        let findings = await BrowserTabProbe().run(context: ctx)
        XCTAssertEqual(findings.count, 1)
    }

    // MARK: - XcodeDerivedDataProbe

    func testXcodeDerivedDataProbeID() {
        XCTAssertEqual(XcodeDerivedDataProbe().probeID, "xcode.deriveddata")
    }

    // MARK: - DockerMemoryProbe

    func testDockerMemoryProbeID() {
        XCTAssertEqual(DockerMemoryProbe().probeID, "docker.memory")
    }

    // MARK: - VSCodeExtensionProbe

    func testVSCodeExtensionProbeID() {
        XCTAssertEqual(VSCodeExtensionProbe().probeID, "vscode.extensions")
    }

    // MARK: - ReeveSelfProbe

    func testReeveSelfProbeID() {
        XCTAssertEqual(ReeveSelfProbe().probeID, "reeve.self")
    }

    func testReeveSelfProbeRunsOnSelf() async {
        let proc = ProcessRecord(pid: getpid(), name: "Reeve",
                                 residentMemory: 50_000_000, cpuPercent: 1)
        let ctx = ProbeContext(bundleID: "com.reeve.app", displayName: "Reeve",
                               processes: [proc], totalMemory: 50_000_000, snapshot: .empty)
        let findings = await ReeveSelfProbe().run(context: ctx)
        XCTAssertFalse(findings.isEmpty, "Self-probe must produce findings for Reeve's own process")
        let selfFinding = findings.first { $0.cause.contains("Reeve resident") }
        XCTAssertNotNil(selfFinding)
    }

    func testReeveSelfProbeSkipsNonReeve() async {
        let proc = ProcessRecord(pid: 9999, name: "Other",
                                 residentMemory: 50_000_000, cpuPercent: 1)
        let ctx = ProbeContext(bundleID: "com.other.app", displayName: "Other",
                               processes: [proc], totalMemory: 50_000_000, snapshot: .empty)
        let findings = await ReeveSelfProbe().run(context: ctx)
        XCTAssertTrue(findings.isEmpty)
    }

    // MARK: - SafariTabProbe

    func testSafariTabProbeID() {
        XCTAssertEqual(SafariTabProbe().probeID, "safari.tabs")
    }

    // MARK: - ProbeRegistry

    func testRegistryReturnsUniversalForAnyApp() {
        let ctx = makeContext(pid: 1, bundleID: "com.example.app", name: "Example")
        let probes = ProbeRegistry.probes(for: ctx)
        XCTAssertTrue(probes.contains { $0.probeID == "universal.vmtags" })
    }

    func testRegistryReturnsSelfProbeForReeve() {
        let proc = ProcessRecord(pid: getpid(), name: "Reeve",
                                 residentMemory: 50_000_000, cpuPercent: 1)
        let ctx = ProbeContext(bundleID: "com.reeve.app", displayName: "Reeve",
                               processes: [proc], totalMemory: 50_000_000, snapshot: .empty)
        let probes = ProbeRegistry.probes(for: ctx)
        XCTAssertTrue(probes.contains { $0.probeID == "reeve.self" })
    }

    func testRegistryReturnsChromeProbes() {
        let ctx = makeContext(pid: 1, bundleID: "com.google.Chrome", name: "Chrome")
        let probes = ProbeRegistry.probes(for: ctx)
        XCTAssertTrue(probes.contains { $0.probeID == "browser.tabs" })
        XCTAssertTrue(probes.contains { $0.probeID == "universal.vmtags" })
    }

    func testRegistryReturnsXcodeProbes() {
        let ctx = makeContext(pid: 1, bundleID: "com.apple.dt.Xcode", name: "Xcode")
        let probes = ProbeRegistry.probes(for: ctx)
        XCTAssertTrue(probes.contains { $0.probeID == "xcode.deriveddata" })
    }

    func testRegistryReturnsSafariProbes() {
        let ctx = makeContext(pid: 1, bundleID: "com.apple.Safari", name: "Safari")
        let probes = ProbeRegistry.probes(for: ctx)
        XCTAssertTrue(probes.contains { $0.probeID == "safari.tabs" })
    }

    func testRegistryReturnsDockerProbes() {
        let ctx = makeContext(pid: 1, bundleID: "com.docker.docker", name: "Docker")
        let probes = ProbeRegistry.probes(for: ctx)
        XCTAssertTrue(probes.contains { $0.probeID == "docker.memory" })
    }

    func testRegistryReturnsVSCodeProbes() {
        let ctx = makeContext(pid: 1, bundleID: "com.microsoft.VSCode", name: "Code")
        let probes = ProbeRegistry.probes(for: ctx)
        XCTAssertTrue(probes.contains { $0.probeID == "vscode.extensions" })
    }

    // MARK: - Helpers

    private func makeContext(pid: pid_t, bundleID: String?, name: String) -> ProbeContext {
        let proc = ProcessRecord(pid: pid, name: name, residentMemory: 100_000_000, cpuPercent: 1)
        return ProbeContext(bundleID: bundleID, displayName: name,
                            processes: [proc], totalMemory: 100_000_000, snapshot: .empty)
    }
}
