@testable import Reeve
import XCTest

final class FormattingTests: XCTestCase {

    // MARK: - formatMem

    func testFormatMemMegabytes() {
        XCTAssertEqual(formatMem(0), "0 MB")
        XCTAssertEqual(formatMem(1_048_576), "1 MB")
        XCTAssertEqual(formatMem(512 * 1_048_576), "512 MB")
    }

    func testFormatMemGigabytes() {
        XCTAssertEqual(formatMem(1_073_741_824), "1 GB")
        XCTAssertEqual(formatMem(2.5 * 1_073_741_824), "2.5 GB")
        XCTAssertEqual(formatMem(10 * 1_073_741_824), "10 GB")
    }

    func testFormatMemTrailingZeros() {
        XCTAssertEqual(formatMem(3.10 * 1_073_741_824), "3.1 GB")
        XCTAssertEqual(formatMem(4.00 * 1_073_741_824), "4 GB")
    }

    // MARK: - formatMemShort

    func testFormatMemShortMegabytes() {
        XCTAssertEqual(formatMemShort(0), "0M")
        XCTAssertEqual(formatMemShort(256 * 1_048_576), "256M")
    }

    func testFormatMemShortGigabytes() {
        XCTAssertEqual(formatMemShort(1_073_741_824), "1.0G")
        XCTAssertEqual(formatMemShort(3.7 * 1_073_741_824), "3.7G")
    }

    // MARK: - calmFormatCap

    func testCalmFormatCapMB() {
        XCTAssertEqual(calmFormatCap(512), "512 MB")
        XCTAssertEqual(calmFormatCap(100), "100 MB")
    }

    func testCalmFormatCapGB() {
        XCTAssertEqual(calmFormatCap(1024), "1 GB")
        XCTAssertEqual(calmFormatCap(2048), "2 GB")
        XCTAssertEqual(calmFormatCap(1536), "1.5 GB")
        XCTAssertEqual(calmFormatCap(2560), "2.5 GB")
    }

    // MARK: - calmFormatDisk

    func testCalmFormatDiskZero() {
        XCTAssertEqual(calmFormatDisk(0), "0")
    }

    func testCalmFormatDiskKilobytes() {
        XCTAssertEqual(calmFormatDisk(1024), "1K")
        XCTAssertEqual(calmFormatDisk(500 * 1024), "500K")
    }

    func testCalmFormatDiskMegabytes() {
        XCTAssertEqual(calmFormatDisk(1_048_576), "1.0")
        XCTAssertEqual(calmFormatDisk(5 * 1_048_576), "5.0")
    }

    func testCalmFormatDiskSubKilobyte() {
        XCTAssertEqual(calmFormatDisk(500), "0")
    }
}
