import Darwin
import Foundation

/// On-demand identity queries for processes: working directory, command-line arguments.
/// All calls are public libproc/sysctl APIs — no private frameworks.
/// These are NOT called during the hot poll loop (ProcessSampler). They are called
/// only when constructing display names in the UI layer.
public enum ProcessIdentity {

    /// Current working directory via proc_pidinfo(PROC_PIDVNODEPATHINFO).
    /// Documented in <sys/proc_info.h>. Returns nil on EPERM or invalid PID.
    public static func cwd(pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        var pathBytes = info.pvi_cdir.vip_path
        let path = withUnsafePointer(to: &pathBytes) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
        return path.isEmpty ? nil : path
    }

    /// Command-line arguments via sysctl(KERN_PROCARGS2).
    /// Documented in sysctl(3) and <sys/sysctl.h>.
    /// Returns empty array on EPERM or for zombie/kernel processes.
    public static func argv(pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size else { return [] }

        let argc: Int32 = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var offset = MemoryLayout<Int32>.size

        while offset < size && buffer[offset] != 0 { offset += 1 }
        while offset < size && buffer[offset] == 0 { offset += 1 }

        var args: [String] = []
        for _ in 0..<argc {
            guard offset < size else { break }
            var end = offset
            while end < size && buffer[end] != 0 { end += 1 }
            if end > offset, let s = String(bytes: buffer[offset..<end], encoding: .utf8) {
                args.append(s)
            }
            offset = end + 1
        }
        return args
    }

    /// Replaces home directory prefix with ~.
    public static func shortenPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// Extracts --profile-directory value from Chromium process argv.
    public static func chromeProfile(pid: pid_t) -> String? {
        let prefix = "--profile-directory="
        return argv(pid: pid)
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
    }
}
