import AppKit

/// Registers a process-global keyboard shortcut (⌥⇧R) to toggle the overlay.
///
/// Requires Accessibility permission. If not yet granted the monitor stays dormant
/// and the UI shows the shortcut dimmed. Calling `requestPermission()` shows the
/// macOS system prompt; calling `tryActivate()` after returning activates the
/// monitor without relaunch.
@MainActor
final class GlobalHotkeyMonitor: ObservableObject {
    @Published private(set) var isActive = false

    private var eventMonitor: Any?
    private var storedHandler: (@MainActor () -> Void)?

    static let shortcutLabel = "⌥⇧R"
    private static let keyCode: UInt16 = 15
    private static let requiredFlags: NSEvent.ModifierFlags = [.option, .shift]

    func register(handler: @escaping @MainActor () -> Void) {
        storedHandler = handler
        tryActivate()
    }

    /// Re-checks Accessibility and activates the monitor if now trusted.
    /// Safe to call repeatedly — no-ops if already active.
    func tryActivate() {
        guard eventMonitor == nil, let handler = storedHandler, AXIsProcessTrusted() else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard flags == Self.requiredFlags, event.keyCode == Self.keyCode else { return }
            Task { @MainActor in handler() }
        }
        isActive = eventMonitor != nil
    }

    /// Shows the macOS Accessibility permission prompt.
    func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func unregister() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
        isActive = false
    }
}
