import XCTest
@testable import ReeveKit

final class RuleSpecTests: XCTestCase {
    private func record(cpu: Double = 0, memBytes: UInt64 = 0, name: String = "test") -> ProcessRecord {
        ProcessRecord(pid: 1, name: name, residentMemory: memBytes, cpuPercent: cpu)
    }

    // MARK: ConditionKind.matches

    func testCPUAboveMatches() {
        XCTAssertTrue(RuleSpec.ConditionKind.cpuAbove(50).matches(record(cpu: 51)))
    }

    func testCPUAboveDoesNotMatchEqual() {
        XCTAssertFalse(RuleSpec.ConditionKind.cpuAbove(50).matches(record(cpu: 50)))
    }

    func testCPUAboveDoesNotMatchBelow() {
        XCTAssertFalse(RuleSpec.ConditionKind.cpuAbove(50).matches(record(cpu: 49)))
    }

    func testMemoryAboveGBMatches() {
        let oneGB: UInt64 = 1_073_741_824
        XCTAssertTrue(RuleSpec.ConditionKind.memoryAboveGB(1.0).matches(record(memBytes: oneGB + 1)))
    }

    func testMemoryAboveGBDoesNotMatchBelow() {
        let oneGB: UInt64 = 1_073_741_824
        XCTAssertFalse(RuleSpec.ConditionKind.memoryAboveGB(1.0).matches(record(memBytes: oneGB - 1)))
    }

    func testNameContainsMatchesCaseInsensitive() {
        XCTAssertTrue(RuleSpec.ConditionKind.nameContains("safari").matches(record(name: "Safari")))
    }

    func testNameContainsNoMatch() {
        XCTAssertFalse(RuleSpec.ConditionKind.nameContains("chrome").matches(record(name: "Safari")))
    }

    // MARK: ConditionKind.displayName

    func testCPUDisplayName() {
        XCTAssertTrue(RuleSpec.ConditionKind.cpuAbove(75).displayName.contains("75"))
    }

    func testMemoryDisplayName() {
        XCTAssertTrue(RuleSpec.ConditionKind.memoryAboveGB(2.0).displayName.contains("2"))
    }

    func testNameDisplayName() {
        XCTAssertTrue(RuleSpec.ConditionKind.nameContains("foo").displayName.contains("foo"))
    }

    // MARK: ActionKind

    func testAllActionKindsCovered() {
        XCTAssertEqual(RuleSpec.ActionKind.allCases.count, 4)
    }

    func testReniceDownMapsToRenice10() {
        guard case .renice(let v) = RuleSpec.ActionKind.reniceDown.toActionKind() else {
            return XCTFail("expected renice")
        }
        XCTAssertEqual(v, 10)
    }

    // MARK: toRule

    func testToRulePreservesID() {
        let spec = RuleSpec(name: "test")
        XCTAssertEqual(spec.toRule().id, spec.id)
    }

    func testToRulePreservesName() {
        let spec = RuleSpec(name: "MyRule")
        XCTAssertEqual(spec.toRule().name, "MyRule")
    }

    func testToRuleConditionEvaluated() {
        let spec = RuleSpec(name: "r", condition: .cpuAbove(10))
        let rule = spec.toRule()
        XCTAssertTrue(rule.condition(record(cpu: 20)))
        XCTAssertFalse(rule.condition(record(cpu: 5)))
    }

    func testToRuleCooldown() {
        let spec = RuleSpec(name: "r", cooldownSeconds: 30)
        XCTAssertEqual(spec.toRule().cooldown, .seconds(30))
    }

    // MARK: Codable round-trip

    func testCodableRoundTrip() throws {
        let spec = RuleSpec(
            name: "round-trip",
            condition: .memoryAboveGB(2.5),
            action: .kill,
            cooldownSeconds: 120,
            isEnabled: false
        )
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(RuleSpec.self, from: data)
        XCTAssertEqual(decoded.id, spec.id)
        XCTAssertEqual(decoded.name, spec.name)
        XCTAssertEqual(decoded.action, spec.action)
        XCTAssertEqual(decoded.cooldownSeconds, spec.cooldownSeconds)
        XCTAssertEqual(decoded.isEnabled, spec.isEnabled)
        XCTAssertEqual(decoded.condition, spec.condition)
    }
}
