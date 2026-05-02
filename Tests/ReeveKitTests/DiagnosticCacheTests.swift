import XCTest
@testable import ReeveKit

final class DiagnosticCacheTests: XCTestCase {

    func testCacheHitWithinTTL() async {
        let cache = DiagnosticCache(ttl: .seconds(30))
        let finding = Finding(cause: "test", evidence: "", severity: .info)
        await cache.set(key: "app", probeID: "p1", findings: [finding])
        let result = await cache.get(key: "app", probeID: "p1")
        XCTAssertEqual(result?.count, 1)
        XCTAssertEqual(result?.first?.cause, "test")
    }

    func testCacheMissForDifferentKey() async {
        let cache = DiagnosticCache(ttl: .seconds(30))
        let finding = Finding(cause: "test", evidence: "", severity: .info)
        await cache.set(key: "app", probeID: "p1", findings: [finding])
        let result = await cache.get(key: "other", probeID: "p1")
        XCTAssertNil(result)
    }

    func testCacheMissForDifferentProbe() async {
        let cache = DiagnosticCache(ttl: .seconds(30))
        let finding = Finding(cause: "test", evidence: "", severity: .info)
        await cache.set(key: "app", probeID: "p1", findings: [finding])
        let result = await cache.get(key: "app", probeID: "p2")
        XCTAssertNil(result)
    }

    func testEvictStaleRemovesExpired() async {
        let cache = DiagnosticCache(ttl: .seconds(0))
        let finding = Finding(cause: "test", evidence: "", severity: .info)
        await cache.set(key: "app", probeID: "p1", findings: [finding])
        try? await Task.sleep(for: .milliseconds(10))
        await cache.evictStale()
        let result = await cache.get(key: "app", probeID: "p1")
        XCTAssertNil(result)
    }

    func testEmptyFindingsCacheable() async {
        let cache = DiagnosticCache(ttl: .seconds(30))
        await cache.set(key: "app", probeID: "p1", findings: [])
        let result = await cache.get(key: "app", probeID: "p1")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 0)
    }
}
