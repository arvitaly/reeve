@testable import Reeve
import ReeveKit
import XCTest

final class GroupRuleLogicTests: XCTestCase {

    // MARK: - ConditionKind.matches

    func testMemoryConditionMatchesAbove() {
        let cond = GroupRuleSpec.ConditionKind.totalMemoryAboveGB(2.0)
        let group = makeGroup(mem: 3 * 1_073_741_824)
        XCTAssertTrue(cond.matches(group))
    }

    func testMemoryConditionDoesNotMatchBelow() {
        let cond = GroupRuleSpec.ConditionKind.totalMemoryAboveGB(2.0)
        let group = makeGroup(mem: 1 * 1_073_741_824)
        XCTAssertFalse(cond.matches(group))
    }

    func testCPUConditionMatchesAbove() {
        let cond = GroupRuleSpec.ConditionKind.totalCPUAbove(50)
        let group = makeGroup(cpu: 60)
        XCTAssertTrue(cond.matches(group))
    }

    func testCPUConditionDoesNotMatchBelow() {
        let cond = GroupRuleSpec.ConditionKind.totalCPUAbove(50)
        let group = makeGroup(cpu: 30)
        XCTAssertFalse(cond.matches(group))
    }

    func testConditionDisplayNames() {
        let mem = GroupRuleSpec.ConditionKind.totalMemoryAboveGB(2.5)
        XCTAssertTrue(mem.displayName.contains("2.5"))

        let cpu = GroupRuleSpec.ConditionKind.totalCPUAbove(80)
        XCTAssertTrue(cpu.displayName.contains("80"))
    }

    // MARK: - ActionKind.toActionKind

    func testActionKindConversions() {
        XCTAssertEqual(actionKindTag(GroupRuleSpec.ActionKind.terminate.toActionKind()), "terminate")
        XCTAssertEqual(actionKindTag(GroupRuleSpec.ActionKind.kill.toActionKind()), "kill")
        XCTAssertEqual(actionKindTag(GroupRuleSpec.ActionKind.suspend.toActionKind()), "suspend")
        XCTAssertEqual(actionKindTag(GroupRuleSpec.ActionKind.resume.toActionKind()), "resume")
        XCTAssertEqual(actionKindTag(GroupRuleSpec.ActionKind.reniceDown.toActionKind()), "renice")
    }

    func testActionKindDisplayNames() {
        for kind in GroupRuleSpec.ActionKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty)
        }
    }

    // MARK: - GroupRuleSpec codability

    func testGroupRuleSpecRoundTrip() throws {
        let spec = GroupRuleSpec(
            appNamePattern: "Chrome",
            condition: .totalMemoryAboveGB(3.5),
            action: .reniceDown,
            cooldownSeconds: 120
        )
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(GroupRuleSpec.self, from: data)
        XCTAssertEqual(decoded.appNamePattern, spec.appNamePattern)
        XCTAssertEqual(decoded.action, spec.action)
        XCTAssertEqual(decoded.cooldownSeconds, 120)
        XCTAssertTrue(decoded.isEnabled)
    }

    func testMemoryPressurePolicyCodability() throws {
        var policy = MemoryPressurePolicy()
        policy.isEnabled = true
        policy.thresholdGB = 12.0
        policy.killList = ["Chrome", "Slack"]
        let data = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(MemoryPressurePolicy.self, from: data)
        XCTAssertTrue(decoded.isEnabled)
        XCTAssertEqual(decoded.thresholdGB, 12.0)
        XCTAssertEqual(decoded.killList, ["Chrome", "Slack"])
    }

    // MARK: - ApplicationGroup computed properties

    func testTotalMemoryAggregation() {
        let group = makeGroup(processMems: [100_000, 200_000, 300_000])
        XCTAssertEqual(group.totalMemory, 600_000)
    }

    func testTotalCPUAggregation() {
        let group = makeGroup(processCPUs: [10, 20, 30])
        XCTAssertEqual(group.totalCPU, 60, accuracy: 0.01)
    }

    func testIsSuspendedAllSuspended() {
        let group = makeGroupWithSuspended([true, true, true])
        XCTAssertTrue(group.isSuspended)
    }

    func testIsSuspendedMixed() {
        let group = makeGroupWithSuspended([true, false, true])
        XCTAssertFalse(group.isSuspended)
    }

    func testFormattedCPU() {
        let group = makeGroup(cpu: 45.67)
        XCTAssertEqual(group.formattedCPU, "45.7%")
    }

    // MARK: - Helpers

    private func makeGroup(mem: UInt64 = 100_000_000, cpu: Double = 10) -> ApplicationGroup {
        let proc = ProcessRecord(
            pid: 1000, name: "Test",
            residentMemory: mem, cpuPercent: cpu,
            physFootprint: mem
        )
        return ApplicationGroup(
            id: 1000, displayName: "Test",
            bundleIdentifier: nil, icon: nil,
            category: .utility, processes: [proc]
        )
    }

    private func makeGroup(processMems: [UInt64]) -> ApplicationGroup {
        let procs = processMems.enumerated().map { i, mem in
            ProcessRecord(
                pid: pid_t(1000 + i), name: "Test-\(i)",
                residentMemory: mem, cpuPercent: 0,
                physFootprint: mem
            )
        }
        return ApplicationGroup(
            id: 1000, displayName: "Test",
            bundleIdentifier: nil, icon: nil,
            category: .utility, processes: procs
        )
    }

    private func makeGroup(processCPUs: [Double]) -> ApplicationGroup {
        let procs = processCPUs.enumerated().map { i, cpu in
            ProcessRecord(
                pid: pid_t(1000 + i), name: "Test-\(i)",
                residentMemory: 100_000, cpuPercent: cpu,
                physFootprint: 100_000
            )
        }
        return ApplicationGroup(
            id: 1000, displayName: "Test",
            bundleIdentifier: nil, icon: nil,
            category: .utility, processes: procs
        )
    }

    private func makeGroupWithSuspended(_ suspended: [Bool]) -> ApplicationGroup {
        let procs = suspended.enumerated().map { i, sus in
            ProcessRecord(
                pid: pid_t(1000 + i), name: "Test-\(i)",
                residentMemory: 100_000, cpuPercent: 0,
                physFootprint: 100_000, isSuspended: sus
            )
        }
        return ApplicationGroup(
            id: 1000, displayName: "Test",
            bundleIdentifier: nil, icon: nil,
            category: .utility, processes: procs
        )
    }

    private func actionKindTag(_ kind: Action.Kind) -> String {
        switch kind {
        case .kill: return "kill"
        case .terminate: return "terminate"
        case .terminateGracefully: return "terminateGracefully"
        case .suspend: return "suspend"
        case .resume: return "resume"
        case .renice: return "renice"
        }
    }
}
