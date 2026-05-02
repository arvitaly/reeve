import XCTest
@testable import ReeveKit

final class RemediationTests: XCTestCase {

    func testRevealIsReversible() {
        let rem = Remediation(kind: .reveal(path: "/tmp"), title: "Show", detail: "")
        let pf = rem.preflight()
        XCTAssertTrue(pf.isReversible)
        XCTAssertTrue(pf.warnings.isEmpty)
    }

    func testClearIsIrreversible() {
        let rem = Remediation(kind: .clear(path: "/tmp/cache", label: "cache"), title: "Clear", detail: "")
        let pf = rem.preflight()
        XCTAssertFalse(pf.isReversible)
        XCTAssertFalse(pf.warnings.isEmpty)
    }

    func testMoveIsReversible() {
        let rem = Remediation(kind: .move(from: "/a", to: "/b"), title: "Move", detail: "")
        let pf = rem.preflight()
        XCTAssertTrue(pf.isReversible)
    }

    func testOpenSettingsIsReversible() {
        let rem = Remediation(kind: .openSettings(urlString: "x-apple.systempreferences:"), title: "Open", detail: "")
        let pf = rem.preflight()
        XCTAssertTrue(pf.isReversible)
        XCTAssertTrue(pf.warnings.isEmpty)
    }

    func testReduceProcessesIsReversible() {
        let rem = Remediation(kind: .reduceProcesses(hint: "Close tabs"), title: "Tip", detail: "")
        let pf = rem.preflight()
        XCTAssertTrue(pf.isReversible)
    }

    func testClearPreflightDescriptionContainsLabel() {
        let rem = Remediation(kind: .clear(path: "/x", label: "DerivedData"), title: "Clear", detail: "")
        XCTAssertTrue(rem.preflight().description.contains("DerivedData"))
    }

    func testRevealPreflightDescriptionContainsPath() {
        let rem = Remediation(kind: .reveal(path: "/Users/test/Desktop"), title: "Show", detail: "")
        XCTAssertTrue(rem.preflight().description.contains("/Users/test/Desktop"))
    }
}
