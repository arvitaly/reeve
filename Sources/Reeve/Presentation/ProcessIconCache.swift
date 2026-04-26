import AppKit
import SwiftUI
import Darwin
import ReeveKit

/// Resolves NSRunningApplication icons and display names by PID.
///
/// Icon hits are cached by process name (stable across restarts of the same app).
/// Display names are looked up fresh each call — `localizedName` from
/// NSRunningApplication is preferred over the raw Mach process name so that
/// helper processes ("2.1.119") show their bundle name ("Google Chrome Helper").
final class ProcessIconCache {
    private var iconCache: [String: NSImage] = [:]

    @MainActor
    func icon(for process: ProcessRecord) -> NSImage? {
        if let hit = iconCache[process.name] { return hit }
        guard let icon = NSRunningApplication(processIdentifier: process.pid)?.icon else {
            return nil
        }
        iconCache[process.name] = icon
        return icon
    }

    /// Returns the best available display name for a process.
    ///
    /// Priority:
    /// 1. NSRunningApplication.localizedName (GUI apps registered with the window server)
    /// 2. Last path component from proc_pidpath (catches helpers like Chrome GPU process
    ///    whose Mach names are version strings like "2.1.119")
    /// 3. ProcessRecord.name (raw proc_name result, up to MAXCOMLEN chars)
    @MainActor
    func displayName(for process: ProcessRecord) -> String {
        if let name = NSRunningApplication(processIdentifier: process.pid)?.localizedName,
           !name.isEmpty {
            return name
        }
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(process.pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 {
            let fullPath = String(cString: pathBuffer)
            let lastName = (fullPath as NSString).lastPathComponent
            if !lastName.isEmpty && lastName != process.name {
                return lastName
            }
        }
        return process.name
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
