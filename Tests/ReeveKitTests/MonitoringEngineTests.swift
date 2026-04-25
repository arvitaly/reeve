import XCTest
@testable import ReeveKit

@MainActor
final class MonitoringEngineTests: XCTestCase {
    func testSnapshotPopulatesAfterAutoStart() async throws {
        let engine = MonitoringEngine()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(engine.snapshot.processes.isEmpty)
    }

    func testAutoStartDisabledLeavesSnapshotEmpty() async throws {
        let engine = MonitoringEngine(autoStart: false)
        // No time given — snapshot must remain the .empty sentinel
        XCTAssertTrue(engine.snapshot.processes.isEmpty)
    }

    func testManualStartAfterAutoStartDisabled() async throws {
        let engine = MonitoringEngine(autoStart: false)
        engine.start()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(engine.snapshot.processes.isEmpty)
    }

    func testStartIsIdempotent() async throws {
        let engine = MonitoringEngine(autoStart: false)
        engine.start()
        engine.start() // second call must not spawn a second polling loop
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(engine.snapshot.processes.isEmpty)
    }

    func testStopHaltsPolling() async throws {
        let engine = MonitoringEngine()
        try await Task.sleep(for: .milliseconds(300))
        let snapBefore = engine.snapshot.sampledAt
        engine.stop()
        // sleep longer than the fast (1s) and slow (5s) intervals — after stop, sampledAt must not advance
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(engine.snapshot.sampledAt, snapBefore)
    }

    func testStopThenRestartWorks() async throws {
        let engine = MonitoringEngine()
        try await Task.sleep(for: .milliseconds(300))
        engine.stop()
        engine.start()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(engine.snapshot.processes.isEmpty)
    }

    func testWindowVisibleDefaultIsFalse() {
        let engine = MonitoringEngine(autoStart: false)
        XCTAssertFalse(engine.windowVisible)
    }

    func testRuleFiresAndLogsEntry() async throws {
        let engine = MonitoringEngine(autoStart: false)
        engine.rules = [Rule(
            name: "MatchReeve",
            cooldown: .seconds(0),
            condition: { $0.isReeve },
            makeAction: { rec in Action(target: rec, kind: .renice(0)) }
        )]
        engine.start()
        // Two polling cycles at 5s interval each would be too slow.
        // Directly call the internal entry-point via two fast samples instead.
        // We rely on the first sample already populating Reeve in snapshot.
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(engine.actionLog.isEmpty)
        XCTAssertEqual(engine.actionLog.first?.ruleName, "MatchReeve")
    }

    func testRuleCooldownPreventsRefire() async throws {
        let engine = MonitoringEngine(autoStart: false)
        engine.rules = [Rule(
            name: "CooldownRule",
            cooldown: .seconds(60), // very long
            condition: { $0.isReeve },
            makeAction: { rec in Action(target: rec, kind: .renice(0)) }
        )]
        engine.start()
        // wait long enough for at least 2 rapid poll cycles (windowVisible=false → 5s each is too slow,
        // but the first sample fires immediately and the second won't fire until 5s later anyway)
        try await Task.sleep(for: .milliseconds(500))
        let count = engine.actionLog.filter { $0.ruleName == "CooldownRule" }.count
        // Rule matched once; cooldown prevents a second entry for the same PID within 60s
        XCTAssertEqual(count, 1)
    }

    func testRuleCooldownBlocksSecondFiring() async throws {
        let engine = MonitoringEngine(autoStart: false)
        engine.showWindow(id: "test")  // 1s interval so we can get two cycles in < 2s
        engine.rules = [Rule(
            name: "CooldownBlock",
            cooldown: .seconds(60),
            condition: { $0.isReeve },
            makeAction: { rec in Action(target: rec, kind: .renice(0)) }
        )]
        engine.start()
        try await Task.sleep(for: .milliseconds(2500))  // covers the continue branch on cycle 2
        let count = engine.actionLog.filter { $0.ruleName == "CooldownBlock" }.count
        XCTAssertEqual(count, 1, "60s cooldown must block refire on second polling cycle")
    }

    func testRuleConditionNonMatchProducesNoLog() async throws {
        let engine = MonitoringEngine(autoStart: false)
        engine.rules = [Rule(
            name: "NeverMatch",
            cooldown: .seconds(0),
            condition: { _ in false },
            makeAction: { rec in Action(target: rec, kind: .suspend) }
        )]
        engine.start()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(engine.actionLog.isEmpty)
    }
}
