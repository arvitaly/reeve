import XCTest
@testable import ReeveKit

final class TypesTests: XCTestCase {
    // MARK: ProcessRecord

    func testIsReeveForSelf() {
        let rec = ProcessRecord(pid: ProcessRecord.reevePID, name: "self", residentMemory: 0, cpuPercent: 0)
        XCTAssertTrue(rec.isReeve)
    }

    func testIsReeveForOtherPID() {
        let rec = ProcessRecord(pid: 1, name: "launchd", residentMemory: 0, cpuPercent: 0)
        XCTAssertFalse(rec.isReeve)
    }

    func testIDEqualsPI() {
        let rec = ProcessRecord(pid: 42, name: "x", residentMemory: 0, cpuPercent: 0)
        XCTAssertEqual(rec.id, 42)
    }

    func testFormattedMemoryIsNonEmpty() {
        let rec = ProcessRecord(pid: 1, name: "x", residentMemory: 1024 * 1024, cpuPercent: 0)
        XCTAssertFalse(rec.formattedMemory.isEmpty)
    }

    func testFormattedCPU() {
        let rec = ProcessRecord(pid: 1, name: "x", residentMemory: 0, cpuPercent: 42.5)
        XCTAssertEqual(rec.formattedCPU, "42.5%")
    }

    func testFormattedCPUZero() {
        let rec = ProcessRecord(pid: 1, name: "x", residentMemory: 0, cpuPercent: 0)
        XCTAssertEqual(rec.formattedCPU, "0.0%")
    }

    func testFormattedDiskWriteAboveThreshold() {
        let rec = ProcessRecord(pid: 1, name: "x", residentMemory: 0, cpuPercent: 0, diskWriteRate: 2048)
        XCTAssertNotNil(rec.formattedDiskWrite)
        XCTAssertTrue(rec.formattedDiskWrite!.hasSuffix("↑"))
    }

    func testFormattedDiskWriteBelowThreshold() {
        let rec = ProcessRecord(pid: 1, name: "x", residentMemory: 0, cpuPercent: 0, diskWriteRate: 512)
        XCTAssertNil(rec.formattedDiskWrite)
    }

    func testFormattedDiskReadAboveThreshold() {
        let rec = ProcessRecord(pid: 1, name: "x", residentMemory: 0, cpuPercent: 0, diskReadRate: 2048)
        XCTAssertNotNil(rec.formattedDiskRead)
        XCTAssertTrue(rec.formattedDiskRead!.hasSuffix("↓"))
    }

    func testFormattedDiskReadBelowThreshold() {
        let rec = ProcessRecord(pid: 1, name: "x", residentMemory: 0, cpuPercent: 0, diskReadRate: 512)
        XCTAssertNil(rec.formattedDiskRead)
    }

    func testHashableDistinctRecords() {
        let a = ProcessRecord(pid: 1, name: "a", residentMemory: 0, cpuPercent: 0)
        let b = ProcessRecord(pid: 2, name: "b", residentMemory: 100, cpuPercent: 1)
        var set = Set<ProcessRecord>()
        set.insert(a)
        set.insert(b)
        XCTAssertEqual(set.count, 2)
    }

    func testHashableSamePIDSameRecord() {
        let a = ProcessRecord(pid: 7, name: "same", residentMemory: 0, cpuPercent: 0)
        let b = ProcessRecord(pid: 7, name: "same", residentMemory: 0, cpuPercent: 0)
        XCTAssertEqual(a, b)
    }

    // MARK: SystemSnapshot

    func testEmptySnapshot() {
        XCTAssertTrue(SystemSnapshot.empty.processes.isEmpty)
    }

    func testTopByMemoryOrdering() {
        let low = ProcessRecord(pid: 1, name: "low", residentMemory: 100, cpuPercent: 0)
        let high = ProcessRecord(pid: 2, name: "high", residentMemory: 200, cpuPercent: 0)
        let snap = SystemSnapshot(processes: [low, high], sampledAt: .now)
        XCTAssertEqual(snap.topByMemory.first?.pid, high.pid)
        XCTAssertEqual(snap.topByMemory.last?.pid, low.pid)
    }

    func testTopByCPUOrdering() {
        let low = ProcessRecord(pid: 1, name: "low", residentMemory: 0, cpuPercent: 1)
        let high = ProcessRecord(pid: 2, name: "high", residentMemory: 0, cpuPercent: 99)
        let snap = SystemSnapshot(processes: [low, high], sampledAt: .now)
        XCTAssertEqual(snap.topByCPU.first?.pid, high.pid)
        XCTAssertEqual(snap.topByCPU.last?.pid, low.pid)
    }

    func testSampledAtIsPreserved() {
        let date = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let snap = SystemSnapshot(processes: [], sampledAt: date)
        XCTAssertEqual(snap.sampledAt, date)
    }

    func testTopByMemoryEmptySnapshot() {
        XCTAssertTrue(SystemSnapshot.empty.topByMemory.isEmpty)
    }

    func testTopByCPUEmptySnapshot() {
        XCTAssertTrue(SystemSnapshot.empty.topByCPU.isEmpty)
    }

    func testTopByDiskWriteOrdering() {
        let low  = ProcessRecord(pid: 1, name: "low",  residentMemory: 0, cpuPercent: 0, diskWriteRate: 100)
        let high = ProcessRecord(pid: 2, name: "high", residentMemory: 0, cpuPercent: 0, diskWriteRate: 200)
        let snap = SystemSnapshot(processes: [low, high], sampledAt: .now)
        XCTAssertEqual(snap.topByDiskWrite.first?.pid, high.pid)
        XCTAssertEqual(snap.topByDiskWrite.last?.pid,  low.pid)
    }

    func testTopByDiskWriteEmptySnapshot() {
        XCTAssertTrue(SystemSnapshot.empty.topByDiskWrite.isEmpty)
    }
}
