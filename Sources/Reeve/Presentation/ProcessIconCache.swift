import AppKit
import SwiftUI
import ReeveKit

/// Resolves NSRunningApplication icons by PID, caching hits by process name.
/// Miss entries are not cached so a process that wasn't registered yet can be
/// found on the next poll cycle.
final class ProcessIconCache {
    private var cache: [String: NSImage] = [:]

    @MainActor
    func icon(for process: ProcessRecord) -> NSImage? {
        if let hit = cache[process.name] { return hit }
        guard let icon = NSRunningApplication(processIdentifier: process.pid)?.icon else {
            return nil
        }
        cache[process.name] = icon
        return icon
    }
}

private struct ProcessIconCacheKey: EnvironmentKey {
    static let defaultValue = ProcessIconCache()
}

extension EnvironmentValues {
    var iconCache: ProcessIconCache {
        get { self[ProcessIconCacheKey.self] }
        set { self[ProcessIconCacheKey.self] = newValue }
    }
}
