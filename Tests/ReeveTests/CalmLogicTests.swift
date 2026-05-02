@testable import Reeve
import ReeveKit
import XCTest

final class CalmLogicTests: XCTestCase {

    // MARK: - calmSuggestion

    func testSuggestionLowMemorySuspend() {
        let result = calmSuggestion(memHistory: [500, 800, 1200], currentMemMB: 1000)
        XCTAssertEqual(result.label, "suspend")
        XCTAssertGreaterThanOrEqual(result.capGB, 0.25)
    }

    func testSuggestionHighMemoryLowerPriority() {
        let result = calmSuggestion(memHistory: [4000, 5000, 6000], currentMemMB: 5000)
        XCTAssertEqual(result.label, "lower priority")
    }

    func testSuggestionEmptyHistory() {
        let result = calmSuggestion(memHistory: [], currentMemMB: 2000)
        XCTAssertEqual(result.label, "suspend")
        XCTAssertGreaterThanOrEqual(result.capGB, 0.25)
    }

    func testSuggestionMinimumCap() {
        let result = calmSuggestion(memHistory: [10], currentMemMB: 10)
        XCTAssertGreaterThanOrEqual(result.capGB, 0.25)
    }

    func testSuggestionCapQuantized() {
        let result = calmSuggestion(memHistory: [2048], currentMemMB: 2048)
        let remainder = result.capGB.truncatingRemainder(dividingBy: 0.25)
        XCTAssertEqual(remainder, 0, accuracy: 0.001)
    }

    // MARK: - calmBarMax

    func testBarMaxWithCap() {
        XCTAssertEqual(calmBarMax(capMB: 1000, memMB: 500), 1250)
    }

    func testBarMaxWithoutCapLargeMem() {
        XCTAssertEqual(calmBarMax(capMB: nil, memMB: 5000), 10000)
    }

    func testBarMaxWithoutCapSmallMemFloored() {
        XCTAssertEqual(calmBarMax(capMB: nil, memMB: 100), 8000)
    }

    // MARK: - calmFilterApps

    func testFilterAllReturnsEverything() {
        let apps = [makeGroup(name: "A", mem: 200), makeGroup(name: "B", mem: 100)]
        let result = calmFilterApps(apps, specs: [], filter: .all)
        XCTAssertEqual(result.count, 2)
    }

    func testFilterAllSortsByMemory() {
        let apps = [makeGroup(name: "Small", mem: 100), makeGroup(name: "Big", mem: 500)]
        let result = calmFilterApps(apps, specs: [], filter: .all)
        XCTAssertEqual(result.first?.displayName, "Big")
    }

    func testFilterHighShowsOnlyNonNormal() {
        let apps = [
            makeGroup(name: "Heavy", mem: 11 * 1_073_741_824),
            makeGroup(name: "Light", mem: 100_000_000),
        ]
        let result = calmFilterApps(apps, specs: [], filter: .high)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.displayName, "Heavy")
    }

    func testFilterCappedShowsOnlyWithCap() {
        let specs = [
            GroupRuleSpec(appNamePattern: "Chrome", condition: .totalMemoryAboveGB(2.0))
        ]
        let apps = [
            makeGroup(name: "Google Chrome", mem: 500_000_000),
            makeGroup(name: "Firefox", mem: 500_000_000),
        ]
        let result = calmFilterApps(apps, specs: specs, filter: .capped)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.displayName, "Google Chrome")
    }

    func testFilterHighEmpty() {
        let apps = [makeGroup(name: "Light", mem: 100_000_000)]
        let result = calmFilterApps(apps, specs: [], filter: .high)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - SortMode

    func testSortModeAllCases() {
        XCTAssertEqual(SortMode.allCases.count, 4)
        XCTAssertEqual(SortMode.memory.rawValue, "Footprint")
        XCTAssertEqual(SortMode.rss.rawValue, "RSS")
        XCTAssertEqual(SortMode.cpu.rawValue, "CPU")
        XCTAssertEqual(SortMode.disk.rawValue, "Disk")
    }

    // MARK: - WidgetMode

    func testWidgetModeHelpTexts() {
        XCTAssertFalse(WidgetMode.compact.helpText.isEmpty)
        XCTAssertFalse(WidgetMode.expanded.helpText.isEmpty)
        XCTAssertFalse(WidgetMode.pinned.helpText.isEmpty)
        XCTAssertFalse(WidgetMode.dashboard.helpText.isEmpty)
    }

    // MARK: - Helpers

    private func makeGroup(name: String, mem: UInt64, pid: pid_t = .random(in: 100...60000)) -> ApplicationGroup {
        let proc = ProcessRecord(
            pid: pid, name: name,
            residentMemory: mem, cpuPercent: 5,
            physFootprint: mem
        )
        return ApplicationGroup(
            id: pid, displayName: name,
            bundleIdentifier: nil, icon: nil,
            category: .utility, processes: [proc]
        )
    }
}
