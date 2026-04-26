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
    private let iconCache: ProcessIconCache
    private var panel: NSPanel?

    init(engine: MonitoringEngine, iconCache: ProcessIconCache) {
        self.engine = engine
        self.iconCache = iconCache
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
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 340),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled, .closable],
            backing: .buffered,
            defer: false
        )
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
        p.setFrameAutosaveName("ReeveOverlay")

        if p.frame.origin == .zero {
            // Default position: bottom-right of main screen
            if let screen = NSScreen.main {
                let x = screen.visibleFrame.maxX - 320
                let y = screen.visibleFrame.minY + 60
                p.setFrameOrigin(NSPoint(x: x, y: y))
            } else {
                p.center()
            }
        }

        guard let engine else { return p }
        let content = NSHostingView(rootView:
            OverlayView(engine: engine, onClose: { [weak self] in self?.hide() })
                .environment(\.iconCache, iconCache)
        )
        content.translatesAutoresizingMaskIntoConstraints = false
        p.contentView = content

        p.delegate = self
        panel = p
        return p
    }
}
