import XCTest
@testable import ReeveKit

final class RuleTests: XCTestCase {
    private let dummyRecord = ProcessRecord(pid: 42, name: "test", residentMemory: 0, cpuPercent: 0)

    // MARK: Rule

    func testRuleDefaultCooldownIsSixtySeconds() {
        let rule = Rule(name: "r", condition: { _ in true }, makeAction: { rec in
            Action(target: rec, kind: .suspend)
        })
        XCTAssertEqual(rule.cooldown, .seconds(60))
    }

    func testRuleCustomCooldown() {
        let rule = Rule(name: "r", cooldown: .seconds(120), condition: { _ in false }, makeAction: { rec in
            Action(target: rec, kind: .suspend)
        })
        XCTAssertEqual(rule.cooldown, .seconds(120))
    }

    func testRuleConditionEvaluated() {
        let rule = Rule(name: "r", condition: { $0.pid == 42 }, makeAction: { rec in
            Action(target: rec, kind: .suspend)
        })
        XCTAssertTrue(rule.condition(dummyRecord))
        let other = ProcessRecord(pid: 99, name: "other", residentMemory: 0, cpuPercent: 0)
        XCTAssertFalse(rule.condition(other))
    }

    func testRuleMakeActionProducesCorrectTarget() {
        let rule = Rule(name: "r", condition: { _ in true }, makeAction: { rec in
            Action(target: rec, kind: .renice(10))
        })
        let action = rule.makeAction(dummyRecord)
        XCTAssertEqual(action.target.pid, dummyRecord.pid)
        if case .renice(let p) = action.kind {
            XCTAssertEqual(p, 10)
        } else {
            XCTFail("wrong kind")
        }
    }

    func testRuleHasStableID() {
        let id = UUID()
        let rule = Rule(id: id, name: "stable", condition: { _ in true }, makeAction: { rec in
            Action(target: rec, kind: .suspend)
        })
        XCTAssertEqual(rule.id, id)
    }

    func testRuleAutoGeneratesID() {
        let r1 = Rule(name: "a", condition: { _ in true }, makeAction: { rec in Action(target: rec, kind: .suspend) })
        let r2 = Rule(name: "b", condition: { _ in true }, makeAction: { rec in Action(target: rec, kind: .suspend) })
        XCTAssertNotEqual(r1.id, r2.id)
    }

    // MARK: ActionLogEntry

    func testActionLogEntryPreservesRuleName() {
        let action = Action(target: dummyRecord, kind: .renice(5))
        let preflight = action.preflight()
        let entry = ActionLogEntry(ruleName: "My Rule", action: action, preflight: preflight)
        XCTAssertEqual(entry.ruleName, "My Rule")
    }

    func testActionLogEntryHasRecentTimestamp() {
        let before = Date.now
        let action = Action(target: dummyRecord, kind: .suspend)
        let entry = ActionLogEntry(ruleName: "r", action: action, preflight: action.preflight())
        XCTAssertGreaterThanOrEqual(entry.firedAt, before)
    }

    func testActionLogEntryHasUniqueIDs() {
        let action = Action(target: dummyRecord, kind: .suspend)
        let e1 = ActionLogEntry(ruleName: "r", action: action, preflight: action.preflight())
        let e2 = ActionLogEntry(ruleName: "r", action: action, preflight: action.preflight())
        XCTAssertNotEqual(e1.id, e2.id)
    }

    func testActionLogEntryPreservesAction() {
        let action = Action(target: dummyRecord, kind: .kill)
        let entry = ActionLogEntry(ruleName: "r", action: action, preflight: action.preflight())
        XCTAssertEqual(entry.action.target.pid, dummyRecord.pid)
        if case .kill = entry.action.kind { } else { XCTFail("wrong kind") }
    }
}
