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

    // MARK: buildTree

    private func rec(_ pid: pid_t, _ ppid: pid_t, mem: UInt64 = 0) -> ProcessRecord {
        ProcessRecord(pid: pid, name: "\(pid)", residentMemory: mem, cpuPercent: 0, parentPID: ppid)
    }

    func testBuildTreeEmptySnapshot() {
        XCTAssertTrue(SystemSnapshot.empty.buildTree().isEmpty)
    }

    func testBuildTreeSingleRoot() {
        let p = rec(100, 0)
        let snap = SystemSnapshot(processes: [p], sampledAt: .now)
        let roots = snap.buildTree()
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots[0].record.pid, 100)
        XCTAssertEqual(roots[0].depth, 0)
    }

    func testBuildTreeParentChildRelationship() {
        // ppid=1 (launchd) not in snapshot → synthetic launchd root wraps parent
        let parent = rec(10, 1)
        let child  = rec(20, 10)
        let snap = SystemSnapshot(processes: [parent, child], sampledAt: .now)
        let roots = snap.buildTree()
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots[0].record.pid, 1)          // synthetic launchd
        XCTAssertEqual(roots[0].record.name, "launchd")
        XCTAssertEqual(roots[0].children.count, 1)
        XCTAssertEqual(roots[0].children[0].record.pid, 10)
        XCTAssertEqual(roots[0].children[0].depth, 1)
        XCTAssertEqual(roots[0].children[0].children[0].record.pid, 20)
        XCTAssertEqual(roots[0].children[0].children[0].depth, 2)
    }

    func testBuildTreeLaunchdChildrenGrouped() {
        // Multiple launchd children → all under one synthetic launchd root
        let a = rec(10, 1)
        let b = rec(20, 1)
        let snap = SystemSnapshot(processes: [a, b], sampledAt: .now)
        let roots = snap.buildTree()
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots[0].record.pid, 1)
        XCTAssertEqual(roots[0].children.count, 2)
    }

    func testBuildTreeOrphanBecomesRoot() {
        // ppid 999 is not in the snapshot — child becomes a root
        let orphan = rec(50, 999)
        let snap = SystemSnapshot(processes: [orphan], sampledAt: .now)
        let roots = snap.buildTree()
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots[0].record.pid, 50)
    }

    func testBuildTreeSiblingsSortedByMemory() {
        let parent = rec(1, 0)
        let bigChild   = rec(10, 1, mem: 200)
        let smallChild = rec(20, 1, mem: 100)
        let snap = SystemSnapshot(processes: [parent, smallChild, bigChild], sampledAt: .now)
        let children = snap.buildTree()[0].children
        XCTAssertEqual(children[0].record.pid, 10)
        XCTAssertEqual(children[1].record.pid, 20)
    }

    func testBuildTreeDepthThreeLevels() {
        let root  = rec(1, 0)
        let mid   = rec(2, 1)
        let leaf  = rec(3, 2)
        let snap = SystemSnapshot(processes: [root, mid, leaf], sampledAt: .now)
        let roots = snap.buildTree()
        XCTAssertEqual(roots[0].depth, 0)
        XCTAssertEqual(roots[0].children[0].depth, 1)
        XCTAssertEqual(roots[0].children[0].children[0].depth, 2)
    }

    func testSubtreeMemorySumsDescendants() {
        let parent = rec(1, 0, mem: 100)
        let child  = rec(2, 1, mem: 200)
        let snap = SystemSnapshot(processes: [parent, child], sampledAt: .now)
        XCTAssertEqual(snap.buildTree()[0].subtreeMemory, 300)
    }

    func testFlattenedOrderIsDepthFirst() {
        let root  = rec(1, 0)
        let child = rec(2, 1)
        let snap = SystemSnapshot(processes: [root, child], sampledAt: .now)
        let flat = snap.buildTree()[0].flattened()
        XCTAssertEqual(flat[0].record.pid, 1)
        XCTAssertEqual(flat[1].record.pid, 2)
    }
}
