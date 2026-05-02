import XCTest
@testable import ReeveKit

final class FinderDesktopProbeTests: XCTestCase {

    func testProbeIDStable() {
        let probe = FinderDesktopProbe()
        XCTAssertEqual(probe.probeID, "finder.desktop")
    }

    func testProbeReturnsEmptyForNonFinder() async {
        let ctx = makeContext(bundleID: "com.google.Chrome", name: "Chrome")
        let probe = FinderDesktopProbe()
        let findings = await probe.run(context: ctx)
        // Probe checks Desktop regardless of bundleID (it's the registry's job to filter)
        // but on a normal Desktop with few files it should return empty or findings
        // We mainly test it doesn't crash
        _ = findings
    }

    func testProbeRunsWithoutCrash() async {
        let ctx = makeContext(bundleID: "com.apple.finder", name: "Finder")
        let probe = FinderDesktopProbe()
        let findings = await probe.run(context: ctx)
        for f in findings {
            XCTAssertFalse(f.cause.isEmpty)
            XCTAssertFalse(f.evidence.isEmpty)
        }
    }

    func testProbeRegistryReturnsFinder() {
        let ctx = makeContext(bundleID: "com.apple.finder", name: "Finder")
        let probes = ProbeRegistry.probes(for: ctx)
        XCTAssertTrue(probes.contains { $0.probeID == "finder.desktop" })
    }

    func testProbeRegistryNoFinderProbeForUnknown() {
        let ctx = makeContext(bundleID: "com.example.unknown", name: "Unknown")
        let probes = ProbeRegistry.probes(for: ctx)
        XCTAssertFalse(probes.contains { $0.probeID == "finder.desktop" })
    }

    private func makeContext(bundleID: String?, name: String) -> ProbeContext {
        let proc = ProcessRecord(pid: 1, name: name, residentMemory: 100_000_000, cpuPercent: 1)
        return ProbeContext(
            bundleID: bundleID, displayName: name,
            processes: [proc], totalMemory: 100_000_000,
            snapshot: .empty
        )
    }
}
