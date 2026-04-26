import AppKit
import SwiftUI
import ReeveKit

/// Manages the persistent main application window.
///
/// The window is created lazily on first `show()` call and kept alive after the user
/// closes it (isReleasedWhenClosed = false). Re-opening via `show()` reuses the same
/// window at its persisted frame position.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private weak var engine: MonitoringEngine?

    func show(appState: AppState) {
        engine = appState.engine
        if window == nil { buildWindow(appState: appState) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        appState.engine.showWindow(id: "mainWindow")
    }

    private func buildWindow(appState: AppState) {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Reeve"
        win.minSize = NSSize(width: 760, height: 500)
        win.isReleasedWhenClosed = false
        win.setFrameAutosaveName("ReeveMainWindow")
        if win.frame.origin == .zero { win.center() }
        win.delegate = self
        win.contentView = NSHostingView(rootView:
            MainView()
                .environmentObject(appState)
                .environment(\.iconCache, appState.iconCache)
        )
        window = win
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in self.engine?.hideWindow(id: "mainWindow") }
    }
}
