import Darwin
import XCTest
@testable import ReeveKit

final class ProcessIdentityTests: XCTestCase {

    func testCWDReturnsSomethingForSelf() {
        let cwd = ProcessIdentity.cwd(pid: getpid())
        XCTAssertNotNil(cwd, "Own process must have a working directory")
        if let cwd {
            XCTAssertFalse(cwd.isEmpty)
            XCTAssertTrue(cwd.hasPrefix("/"), "CWD must be an absolute path")
        }
    }

    func testCWDReturnsNilForInvalidPID() {
        XCTAssertNil(ProcessIdentity.cwd(pid: -1))
    }

    func testArgvReturnsSomethingForSelf() {
        let args = ProcessIdentity.argv(pid: getpid())
        XCTAssertFalse(args.isEmpty, "Own process must have at least one argument (executable)")
    }

    func testArgvReturnsEmptyForInvalidPID() {
        XCTAssertTrue(ProcessIdentity.argv(pid: -1).isEmpty)
    }

    func testShortenPathReplacesHome() {
        let home = NSHomeDirectory()
        let shortened = ProcessIdentity.shortenPath(home + "/Documents/test")
        XCTAssertEqual(shortened, "~/Documents/test")
    }

    func testShortenPathLeavesNonHomeAlone() {
        XCTAssertEqual(ProcessIdentity.shortenPath("/usr/bin"), "/usr/bin")
    }

    func testChromeProfileReturnsNilForSelf() {
        XCTAssertNil(ProcessIdentity.chromeProfile(pid: getpid()))
    }
}
