@testable import Reeve
import SnapshotTesting
import SwiftUI
import XCTest

final class AtomSnapshotTests: XCTestCase {

    override func invokeTest() {
        withSnapshotTesting(record: .missing) {
            super.invokeTest()
        }
    }

    // MARK: - SeverityDot

    func testSeverityDotNormal() {
        let view = SeverityDot(severity: .normal, size: 12)
            .frame(width: 24, height: 24)
            .background(Color.black)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 24, height: 24)))
    }

    func testSeverityDotWarn() {
        let view = SeverityDot(severity: .warn, size: 12)
            .frame(width: 24, height: 24)
            .background(Color.black)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 24, height: 24)))
    }

    func testSeverityDotOver() {
        let view = SeverityDot(severity: .over, size: 12)
            .frame(width: 24, height: 24)
            .background(Color.black)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 24, height: 24)))
    }

    // MARK: - CategoryChip

    func testCategoryChipBrowser() {
        let view = CategoryChip(category: .browser)
            .padding(4)
            .background(Color.black)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 100, height: 30)))
    }

    func testCategoryChipDev() {
        let view = CategoryChip(category: .dev)
            .padding(4)
            .background(Color.black)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 100, height: 30)))
    }

    func testCategoryChipComm() {
        let view = CategoryChip(category: .comm)
            .padding(4)
            .background(Color.black)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 100, height: 30)))
    }

    // MARK: - MetricPill

    func testMetricPillDefault() {
        let view = MetricPill(text: "1.2 GB")
            .padding(4)
            .background(Color.black)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 80, height: 30)))
    }

    func testMetricPillColored() {
        let view = MetricPill(text: "Suspended", color: .rvWarn, mono: false)
            .padding(4)
            .background(Color.black)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 100, height: 30)))
    }

    // MARK: - ActionChip

    func testActionChipDefault() {
        let view = ActionChip(label: "Lower", icon: "\u{2193}") {}
            .padding(4)
            .background(Color.black)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 80, height: 32)))
    }

    func testActionChipOver() {
        let view = ActionChip(label: "Kill", icon: "\u{2715}", kind: .over) {}
            .padding(4)
            .background(Color.black)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 80, height: 32)))
    }

    func testActionChipAccent() {
        let view = ActionChip(label: "Apply", kind: .accent) {}
            .padding(4)
            .background(Color.black)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 80, height: 32)))
    }

    // MARK: - MiniBar

    func testMiniBarNormal() {
        let view = MiniBar(value: 500_000_000, cap: 2_000_000_000, width: 80, height: 6, severity: .normal)
            .padding(4)
            .background(Color.black)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 88, height: 14)))
    }

    func testMiniBarOver() {
        let view = MiniBar(value: 3_000_000_000, cap: 2_000_000_000, width: 80, height: 6, severity: .over)
            .padding(4)
            .background(Color.black)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 88, height: 14)))
    }

    func testMiniBarNoCap() {
        let view = MiniBar(value: 2_000_000_000, cap: nil, width: 80, height: 6, severity: .warn)
            .padding(4)
            .background(Color.black)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 88, height: 14)))
    }

    // MARK: - Sparkline

    func testSparklineBasic() {
        let data = [10.0, 30, 20, 50, 40, 60, 45, 70]
        let view = Sparkline(data: data, height: 28, color: .green)
            .frame(width: 120)
            .padding(4)
            .background(Color.black)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 128, height: 36)))
    }

    func testSparklineWithCap() {
        let data = [10.0, 30, 20, 50, 80, 60, 90]
        let view = Sparkline(data: data, height: 28, color: .red, capLine: 70, capMax: 100)
            .frame(width: 120)
            .padding(4)
            .background(Color.black)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 128, height: 36)))
    }

    // MARK: - StackBar

    func testStackBar() {
        let segments: [(label: String, value: Double, color: Color)] = [
            ("A", 40, .blue), ("B", 30, .green), ("C", 30, .red)
        ]
        let view = StackBar(segments: segments, total: 100, height: 6)
            .frame(width: 120)
            .padding(4)
            .background(Color.black)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 128, height: 14)))
    }
}
