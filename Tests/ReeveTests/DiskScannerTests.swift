@testable import Reeve
import XCTest

@MainActor
final class DiskScannerTests: XCTestCase {

    // MARK: - SizeState

    func testSizeStatePendingFormatted() {
        XCTAssertEqual(SizeState.pending.formatted, "—")
        XCTAssertNil(SizeState.pending.bytes)
    }

    func testSizeStateScanningFormatted() {
        XCTAssertEqual(SizeState.scanning.formatted, "…")
        XCTAssertNil(SizeState.scanning.bytes)
    }

    func testSizeStateAbsentFormatted() {
        XCTAssertEqual(SizeState.absent.formatted, "")
        XCTAssertNil(SizeState.absent.bytes)
    }

    func testSizeStateReadyBytes() {
        let state = SizeState.ready(1_000_000)
        XCTAssertEqual(state.bytes, 1_000_000)
        XCTAssertFalse(state.formatted.isEmpty)
    }

    // MARK: - DiskEntry defaults

    func testDiskEntryDefaults() {
        let entry = DiskEntry(
            displayName: "Test",
            detail: "Detail",
            path: URL(fileURLWithPath: "/tmp"),
            category: "Test"
        )
        XCTAssertTrue(entry.isSelected)
        if case .pending = entry.sizeState {} else {
            XCTFail("Expected .pending")
        }
    }

    // MARK: - DiskScanner.makeEntries

    func testMakeEntriesNotEmpty() {
        let entries = DiskScanner.makeEntries()
        XCTAssertFalse(entries.isEmpty)
    }

    func testMakeEntriesHaveCategories() {
        let entries = DiskScanner.makeEntries()
        let categories = Set(entries.map { $0.category })
        XCTAssertTrue(categories.contains("Developer"))
        XCTAssertTrue(categories.contains("Package Managers"))
    }

    func testMakeEntriesAllPending() {
        let entries = DiskScanner.makeEntries()
        for entry in entries {
            if case .pending = entry.sizeState {} else {
                XCTFail("Expected all entries to start as .pending")
            }
        }
    }

    // MARK: - DiskScanner.measure

    func testMeasureNonexistentPath() {
        let url = URL(fileURLWithPath: "/nonexistent/path/\(UUID().uuidString)")
        XCTAssertEqual(DiskScanner.measure(url), 0)
    }

    func testMeasureTmpDirectory() {
        let bytes = DiskScanner.measure(URL(fileURLWithPath: NSTemporaryDirectory()))
        XCTAssertGreaterThanOrEqual(bytes, 0)
    }
}
