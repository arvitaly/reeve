@testable import Reeve
import XCTest

final class CategorizationTests: XCTestCase {

    // MARK: - categorize(bundleID:)

    func testBrowserBundleIDs() {
        XCTAssertEqual(categorize(bundleID: "com.google.Chrome"), .browser)
        XCTAssertEqual(categorize(bundleID: "com.apple.Safari"), .browser)
        XCTAssertEqual(categorize(bundleID: "org.mozilla.firefox"), .browser)
        XCTAssertEqual(categorize(bundleID: "com.brave.Browser"), .browser)
    }

    func testDevBundleIDs() {
        XCTAssertEqual(categorize(bundleID: "com.apple.dt.Xcode"), .dev)
        XCTAssertEqual(categorize(bundleID: "com.microsoft.VSCode"), .dev)
        XCTAssertEqual(categorize(bundleID: "com.jetbrains.AppCode"), .dev)
        XCTAssertEqual(categorize(bundleID: "dev.zed.Zed"), .dev)
    }

    func testTerminalsBelongToDev() {
        XCTAssertEqual(categorize(bundleID: "com.apple.Terminal"), .dev)
        XCTAssertEqual(categorize(bundleID: "com.googlecode.iterm2"), .dev)
        XCTAssertEqual(categorize(bundleID: "dev.warp.Warp"), .dev)
    }

    func testCommBundleIDs() {
        XCTAssertEqual(categorize(bundleID: "com.tinyspeck.slackmacgap"), .comm)
        XCTAssertEqual(categorize(bundleID: "ru.keepcoder.Telegram"), .comm)
        XCTAssertEqual(categorize(bundleID: "com.hnc.Discord"), .comm)
    }

    func testMediaBundleIDs() {
        XCTAssertEqual(categorize(bundleID: "com.spotify.client"), .media)
        XCTAssertEqual(categorize(bundleID: "com.apple.Music"), .media)
        XCTAssertEqual(categorize(bundleID: "io.mpv"), .media)
    }

    func testCreativeBundleIDs() {
        XCTAssertEqual(categorize(bundleID: "com.figma.Desktop"), .creative)
        XCTAssertEqual(categorize(bundleID: "com.adobe.Photoshop"), .creative)
        XCTAssertEqual(categorize(bundleID: "md.obsidian"), .creative)
    }

    func testSystemBundleIDs() {
        XCTAssertEqual(categorize(bundleID: "com.apple.finder"), .system)
        XCTAssertEqual(categorize(bundleID: "com.apple.dock"), .system)
    }

    func testUtilityBundleIDs() {
        XCTAssertEqual(categorize(bundleID: "com.1password.1password"), .utility)
        XCTAssertEqual(categorize(bundleID: "com.raycast.macos"), .utility)
    }

    func testReeveSelfDetection() {
        XCTAssertEqual(categorize(bundleID: "com.example.reeve"), .utility)
        XCTAssertEqual(categorize(bundleID: "com.example.Reeve"), .utility)
    }

    func testNilBundleIDReturnsSystem() {
        XCTAssertEqual(categorize(bundleID: nil), .system)
    }

    func testUnknownAppleBundleIDReturnsSystem() {
        XCTAssertEqual(categorize(bundleID: "com.apple.SomethingUnknown"), .system)
    }

    func testUnknownThirdPartyReturnsUtility() {
        XCTAssertEqual(categorize(bundleID: "com.example.SomeRandomApp"), .utility)
    }

    // MARK: - AppCategory properties

    func testAppCategoryLabels() {
        XCTAssertEqual(AppCategory.browser.label, "Browser")
        XCTAssertEqual(AppCategory.dev.label, "Dev")
        XCTAssertEqual(AppCategory.comm.label, "Comms")
        XCTAssertEqual(AppCategory.media.label, "Media")
        XCTAssertEqual(AppCategory.creative.label, "Creative")
        XCTAssertEqual(AppCategory.system.label, "System")
        XCTAssertEqual(AppCategory.utility.label, "Utility")
    }

    func testAllCategoriesCovered() {
        XCTAssertEqual(AppCategory.allCases.count, 7)
    }
}
