import XCTest
@testable import ReeveKit

final class ProcessSamplerTests: XCTestCase {
    func testSnapshotIncludesReeve() async {
        let sampler = ProcessSampler()
        let snapshot = await sampler.sample()
        XCTAssertTrue(
            snapshot.processes.contains { $0.isReeve },
            "Reeve must appear in its own process list"
        )
    }

    func testSnapshotIsNonEmpty() async {
        let sampler = ProcessSampler()
        let snapshot = await sampler.sample()
        XCTAssertFalse(snapshot.processes.isEmpty)
    }

    func testCPUPercentBoundsOnSecondSample() async {
        let sampler = ProcessSampler()
        _ = await sampler.sample()
        try? await Task.sleep(for: .milliseconds(200))
        let snapshot = await sampler.sample()
        for process in snapshot.processes {
            XCTAssertGreaterThanOrEqual(process.cpuPercent, 0)
            XCTAssertLessThanOrEqual(process.cpuPercent, 100)
        }
    }

    func testDiskRatesAreNonNegativeOnSecondSample() async {
        let sampler = ProcessSampler()
        _ = await sampler.sample()
        try? await Task.sleep(for: .milliseconds(200))
        let snapshot = await sampler.sample()
        for process in snapshot.processes {
            XCTAssertGreaterThanOrEqual(process.diskReadRate, 0)
            XCTAssertGreaterThanOrEqual(process.diskWriteRate, 0)
        }
    }

    func testPreflightUnknownEffectHasReason() {
        let record = ProcessRecord(pid: 1, name: "test", residentMemory: 0, cpuPercent: 0)
        for kind: Action.Kind in [.terminate, .kill] {
            let action = Action(target: record, kind: kind)
            let preflight = action.preflight()
            if case .unknown(let reason) = preflight.effect {
                XCTAssertFalse(reason.isEmpty, "unknown effect must state a reason")
            }
        }
    }

    func testRenicePreflightIsReversible() {
        let record = ProcessRecord(pid: 1, name: "test", residentMemory: 0, cpuPercent: 0)
        let action = Action(target: record, kind: .renice(10))
        XCTAssertTrue(action.preflight().isReversible)
    }

    func testKillPreflightIsIrreversible() {
        let record = ProcessRecord(pid: 1, name: "test", residentMemory: 0, cpuPercent: 0)
        let action = Action(target: record, kind: .kill)
        XCTAssertFalse(action.preflight().isReversible)
    }
}
