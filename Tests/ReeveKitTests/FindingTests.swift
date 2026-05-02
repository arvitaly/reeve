import XCTest
@testable import ReeveKit

final class FindingTests: XCTestCase {

    func testConfidenceComparable() {
        XCTAssertTrue(Finding.Confidence.info < .advisory)
        XCTAssertTrue(Finding.Confidence.advisory < .actionable)
        XCTAssertTrue(Finding.Confidence.info < .actionable)
    }

    func testFindingWithNilRemediation() {
        let f = Finding(cause: "test", evidence: "ev", severity: .info)
        XCTAssertNil(f.suggestedRemediation)
    }

    func testFindingWithRemediation() {
        let rem = Remediation(kind: .reveal(path: "/tmp"), title: "Show", detail: "")
        let f = Finding(cause: "test", evidence: "ev", severity: .actionable, suggestedRemediation: rem)
        XCTAssertNotNil(f.suggestedRemediation)
        XCTAssertEqual(f.severity, .actionable)
    }

    func testFindingIdentifiable() {
        let a = Finding(cause: "a", evidence: "", severity: .info)
        let b = Finding(cause: "b", evidence: "", severity: .info)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testEmptyEvidence() {
        let f = Finding(cause: "something", evidence: "", severity: .advisory)
        XCTAssertEqual(f.evidence, "")
    }
}
