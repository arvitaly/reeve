@testable import Reeve
import ReeveKit
import XCTest

final class SeverityTests: XCTestCase {

    // MARK: - Severity ordering

    func testSeverityComparable() {
        XCTAssertTrue(Severity.normal < Severity.warn)
        XCTAssertTrue(Severity.warn < Severity.over)
        XCTAssertTrue(Severity.normal < Severity.over)
    }

    // MARK: - memSeverity

    func testMemSeverityWithCapNormal() {
        let group = makeGroup(memoryBytes: 500_000_000)
        XCTAssertEqual(group.memSeverity(cap: 1_073_741_824), .normal) // 500MB / 1GB = 50%
    }

    func testMemSeverityWithCapWarn() {
        let group = makeGroup(memoryBytes: 800_000_000)
        XCTAssertEqual(group.memSeverity(cap: 1_073_741_824), .warn) // 800MB / 1GB = ~74.5%
    }

    func testMemSeverityWithCapOver() {
        let group = makeGroup(memoryBytes: 1_200_000_000)
        XCTAssertEqual(group.memSeverity(cap: 1_073_741_824), .over) // 1.2GB / 1GB = 120%
    }

    func testMemSeverityNoCap10GBOver() {
        let group = makeGroup(memoryBytes: 11 * 1_073_741_824)
        XCTAssertEqual(group.memSeverity(cap: nil), .over)
    }

    func testMemSeverityNoCap6GBWarn() {
        let group = makeGroup(memoryBytes: 7 * 1_073_741_824)
        XCTAssertEqual(group.memSeverity(cap: nil), .warn)
    }

    func testMemSeverityNoCapNormal() {
        let group = makeGroup(memoryBytes: 2 * 1_073_741_824)
        XCTAssertEqual(group.memSeverity(cap: nil), .normal)
    }

    func testMemSeverityCapBoundary70Percent() {
        let cap: UInt64 = 10_000_000_000
        let group = makeGroup(memoryBytes: 7_000_000_000) // exactly 70%
        XCTAssertEqual(group.memSeverity(cap: cap), .warn)
    }

    func testMemSeverityCapBoundary100Percent() {
        let cap: UInt64 = 10_000_000_000
        let group = makeGroup(memoryBytes: 10_000_000_000)
        XCTAssertEqual(group.memSeverity(cap: cap), .over)
    }

    // MARK: - cpuSeverity

    func testCpuSeverityNormal() {
        let group = makeGroup(cpu: 30)
        XCTAssertEqual(group.cpuSeverity(), .normal)
    }

    func testCpuSeverityWarn() {
        let group = makeGroup(cpu: 60)
        XCTAssertEqual(group.cpuSeverity(), .warn)
    }

    func testCpuSeverityOver() {
        let group = makeGroup(cpu: 90)
        XCTAssertEqual(group.cpuSeverity(), .over)
    }

    func testCpuSeverityBoundary50() {
        let group = makeGroup(cpu: 50)
        XCTAssertEqual(group.cpuSeverity(), .warn)
    }

    func testCpuSeverityBoundary80() {
        let group = makeGroup(cpu: 80)
        XCTAssertEqual(group.cpuSeverity(), .over)
    }

    // MARK: - overallSeverity

    func testOverallSeverityTakesMax() {
        let highCpu = makeGroup(memoryBytes: 100_000_000, cpu: 90)
        XCTAssertEqual(highCpu.overallSeverity(cap: nil), .over)

        let highMem = makeGroup(memoryBytes: 11 * 1_073_741_824, cpu: 10)
        XCTAssertEqual(highMem.overallSeverity(cap: nil), .over)

        let bothNormal = makeGroup(memoryBytes: 100_000_000, cpu: 10)
        XCTAssertEqual(bothNormal.overallSeverity(cap: nil), .normal)
    }

    // MARK: - memCap

    func testMemCapMatchingRule() {
        let specs = [
            GroupRuleSpec(appNamePattern: "Chrome", condition: .totalMemoryAboveGB(2.0))
        ]
        let group = makeGroup(name: "Google Chrome")
        let cap = memCap(for: group, in: specs)
        XCTAssertEqual(cap, UInt64(2.0 * 1_073_741_824))
    }

    func testMemCapNoMatch() {
        let specs = [
            GroupRuleSpec(appNamePattern: "Firefox", condition: .totalMemoryAboveGB(2.0))
        ]
        let group = makeGroup(name: "Google Chrome")
        XCTAssertNil(memCap(for: group, in: specs))
    }

    func testMemCapDisabledRule() {
        let specs = [
            GroupRuleSpec(appNamePattern: "Chrome", condition: .totalMemoryAboveGB(2.0), isEnabled: false)
        ]
        let group = makeGroup(name: "Google Chrome")
        XCTAssertNil(memCap(for: group, in: specs))
    }

    func testMemCapTightestWins() {
        let specs = [
            GroupRuleSpec(appNamePattern: "Chrome", condition: .totalMemoryAboveGB(4.0)),
            GroupRuleSpec(appNamePattern: "Chrome", condition: .totalMemoryAboveGB(2.0)),
            GroupRuleSpec(appNamePattern: "Chrome", condition: .totalMemoryAboveGB(6.0)),
        ]
        let group = makeGroup(name: "Google Chrome")
        XCTAssertEqual(memCap(for: group, in: specs), UInt64(2.0 * 1_073_741_824))
    }

    func testMemCapEmptyPattern() {
        let specs = [
            GroupRuleSpec(appNamePattern: "", condition: .totalMemoryAboveGB(2.0))
        ]
        let group = makeGroup(name: "Chrome")
        XCTAssertNil(memCap(for: group, in: specs))
    }

    func testMemCapCPUConditionIgnored() {
        let specs = [
            GroupRuleSpec(appNamePattern: "Chrome", condition: .totalCPUAbove(50))
        ]
        let group = makeGroup(name: "Chrome")
        XCTAssertNil(memCap(for: group, in: specs))
    }

    // MARK: - Helpers

    private func makeGroup(
        name: String = "TestApp",
        memoryBytes: UInt64 = 100_000_000,
        cpu: Double = 10,
        pid: pid_t = 1000
    ) -> ApplicationGroup {
        let proc = ProcessRecord(
            pid: pid, name: name,
            residentMemory: memoryBytes, cpuPercent: cpu,
            physFootprint: memoryBytes
        )
        return ApplicationGroup(
            id: pid, displayName: name,
            bundleIdentifier: nil, icon: nil,
            category: .utility, processes: [proc]
        )
    }
}
