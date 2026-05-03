import Foundation

/// Quick file-based logger so we can debug helper activity without needing
/// `log show` access (which requires root or Full Disk Access on the user
/// account). DEBUG only — release builds log to OSLog.
enum DebugLog {
    private static let path = "/tmp/reeve-helper.log"
    private static let lock = NSLock()

    static func line(_ s: String) {
        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        let stamp = ISO8601DateFormatter().string(from: .now)
        let entry = "[\(stamp)] \(s)\n"
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
            chmod(path, 0o666)
        }
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(entry.data(using: .utf8) ?? Data())
            try? h.close()
        }
        #endif
    }
}
