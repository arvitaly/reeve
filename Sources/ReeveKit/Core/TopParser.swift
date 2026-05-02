import Darwin
import Foundation

/// Reads per-process phys_footprint via `/usr/bin/top`.
///
/// `top` ships with the private `com.apple.system-task-ports.read` entitlement
/// (verifiable via `codesign -d --entitlements - /usr/bin/top`) and reports
/// `phys_footprint` for *every* process — including root-owned processes that
/// `proc_pid_rusage` returns EPERM for. The MEM column documented in `top(1)` is
/// "Physical memory footprint of the process."
///
/// Cost: ~1.3-1.5 s for one snapshot of all processes. Caller must run this
/// off the polling loop and cache the result.
public enum TopParser {
    /// Runs `top -l 1 -F -stats pid,mem -n 0` and returns `[pid: phys_footprint_bytes]`.
    /// Returns an empty dictionary on parse failure or non-zero exit.
    public static func snapshot() -> [pid_t: UInt64] {
        let proc = Foundation.Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        proc.arguments = ["-l", "1", "-F", "-stats", "pid,mem", "-n", "100000"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return [:] }
        return parse(text)
    }

    /// Parses the body of a `top -l 1 -stats pid,mem` invocation. Public for tests.
    public static func parse(_ text: String) -> [pid_t: UInt64] {
        var result: [pid_t: UInt64] = [:]
        var sawHeader = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if !sawHeader {
                if line.hasPrefix("PID") { sawHeader = true }
                continue
            }
            if line.isEmpty { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  let pid = pid_t(parts[0]),
                  let bytes = parseSize(String(parts[1])) else { continue }
            result[pid] = bytes
        }
        return result
    }

    /// Converts top's compact size strings ("11M", "817K", "1521K", "0B", "1G") to bytes.
    /// `top` uses 1024-based units and prints integers (no decimals).
    static func parseSize(_ s: String) -> UInt64? {
        guard !s.isEmpty else { return nil }
        let suffix = s.last!
        let body = s.dropLast()
        let multiplier: UInt64
        let valueStr: String
        switch suffix {
        case "K": multiplier = 1024;                valueStr = String(body)
        case "M": multiplier = 1024 * 1024;         valueStr = String(body)
        case "G": multiplier = 1024 * 1024 * 1024;  valueStr = String(body)
        case "T": multiplier = 1024 * 1024 * 1024 * 1024; valueStr = String(body)
        case "B": multiplier = 1;                   valueStr = String(body)
        default:
            // No suffix — interpret as raw bytes if numeric.
            multiplier = 1
            valueStr = s
        }
        guard let value = UInt64(valueStr) else { return nil }
        return value * multiplier
    }
}
