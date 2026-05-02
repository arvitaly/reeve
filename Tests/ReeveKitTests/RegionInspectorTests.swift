import Darwin
import XCTest
@testable import ReeveKit

final class RegionInspectorTests: XCTestCase {

    func testInspectSelfReturnsCategories() {
        let categories = RegionInspector.inspect(pid: getpid())
        XCTAssertFalse(categories.isEmpty, "Reeve must have at least one memory region")
    }

    func testInspectSelfHasMALLOC() {
        let categories = RegionInspector.inspect(pid: getpid())
        let malloc = categories.first { $0.label == "MALLOC" }
        XCTAssertNotNil(malloc, "Every process allocates heap memory")
        if let m = malloc {
            XCTAssertGreaterThan(m.residentBytes, 0)
        }
    }

    func testInspectSelfTotalResidentIsPositive() {
        let categories = RegionInspector.inspect(pid: getpid())
        let total = categories.reduce(0 as UInt64) { $0 + $1.residentBytes }
        XCTAssertGreaterThan(total, 0)
    }

    func testInspectSelfCategoriesAreSortedByResident() {
        let categories = RegionInspector.inspect(pid: getpid())
        for i in 1..<categories.count {
            XCTAssertGreaterThanOrEqual(
                categories[i - 1].residentBytes,
                categories[i].residentBytes,
                "Categories should be sorted descending by residentBytes"
            )
        }
    }

    func testInspectInvalidPIDReturnsEmpty() {
        let categories = RegionInspector.inspect(pid: -1)
        XCTAssertTrue(categories.isEmpty)
    }

    func testInspectZeroPIDReturnsEmpty() {
        let categories = RegionInspector.inspect(pid: 0)
        XCTAssertTrue(categories.isEmpty)
    }

    func testVMRegionCategoryIdentifiable() {
        let cat = VMRegionCategory(tag: 1, label: "MALLOC", residentBytes: 1000, dirtyBytes: 500)
        XCTAssertEqual(cat.id, "MALLOC")
    }
}
