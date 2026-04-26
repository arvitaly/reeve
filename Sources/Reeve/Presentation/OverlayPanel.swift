import AppKit
import SwiftUI
import ReeveKit

/// Manages the desktop-level overlay widget.
///
/// The panel sits at `desktopIconWindow` level — below all application windows, above
/// the wallpaper. It is visible on the desktop but never covers active work.
/// Position is persisted via autosave name in UserDefaults.
@MainActor
final class OverlayController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isVisible = false

    private weak var engine: MonitoringEngine?
    private weak var appState: AppState?
    private let iconCache: ProcessIconCache
    private var panel: NSPanel?

    init(engine: MonitoringEngine, iconCache: ProcessIconCache) {
        self.engine = engine
        self.iconCache = iconCache
    }

    func configure(appState: AppState) {
        self.appState = appState
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        let p = panel ?? makePanel()
        p.orderFrontRegardless()
        isVisible = true
        engine?.showWindow(id: "overlay")
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
        engine?.hideWindow(id: "overlay")
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.isVisible = false
            self.engine?.hideWindow(id: "overlay")
        }
    }

    // MARK: -

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 1100),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        p.minSize = NSSize(width: 280, height: 200)
        // Desktop level: below all app windows, above wallpaper
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        p.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        // Restore saved frame. If no frame was saved the origin stays at 0 (from contentRect).
        // x==0 means either "no autosave" or a stale left-edge position — reset to default top-right.
        p.setFrameAutosaveName("ReeveOverlay")
        if p.frame.minX == 0 {
            if let screen = NSScreen.main {
                let margin: CGFloat = 16
                let x = screen.visibleFrame.maxX - p.frame.width - margin
                let y = screen.visibleFrame.maxY - p.frame.height - margin
                p.setFrameOrigin(NSPoint(x: x, y: y))
                p.saveFrame(usingName: "ReeveOverlay")
            } else {
                p.center()
            }
        }

        guard let engine, let appState else { return p }
        let content = NSHostingView(rootView:
            OverlayView(engine: engine, onClose: { [weak self] in self?.hide() })
                .environmentObject(appState)
                .environment(\.iconCache, iconCache)
        )
        content.autoresizingMask = [.width, .height]
        p.contentView = content

        p.delegate = self
        panel = p
        return p
    }
}
