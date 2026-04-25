import AppKit
import SwiftUI
import ReeveKit

/// Manages the floating always-on-top NSPanel and its SwiftUI content.
///
/// The panel is hidden on first launch (overlays imposed unsolicited are hostile).
/// Position is persisted automatically via autosave name — Cocoa writes to UserDefaults.
@MainActor
final class OverlayController: ObservableObject {
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

    // MARK: -

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 10),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled, .closable],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.setFrameAutosaveName("ReeveOverlay")

        if p.frame.origin == .zero {
            p.center()
        }

        guard let engine else { return p }
        let content = NSHostingView(rootView:
            OverlayView(engine: engine, onClose: { [weak self] in self?.hide() })
                .environment(\.iconCache, iconCache)
        )
        content.translatesAutoresizingMaskIntoConstraints = false
        p.contentView = content

        panel = p
        return p
    }
}
