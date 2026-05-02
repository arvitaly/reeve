import Darwin
import Foundation

public struct VMRegionCategory: Sendable, Identifiable {
    public let tag: UInt32
    public let label: String
    public let residentBytes: UInt64
    public let dirtyBytes: UInt64
    public var id: UInt32 { tag }
}

public enum RegionInspector {
    private static let categoryForTag: [UInt32: String] = {
        var m: [UInt32: String] = [:]
        for t: UInt32 in 1...11 { m[t] = "MALLOC" }
        m[20] = "IOKit"
        m[21] = "IOKit"
        m[30] = "Stack"
        m[33] = "Frameworks"
        m[35] = "AppKit"
        m[38] = "Foundation"
        m[40] = "AppKit"
        m[41] = "Foundation"
        m[42] = "CoreGraphics"
        m[43] = "CoreServices"
        m[45] = "CoreData"
        m[46] = "CoreData"
        m[48] = "Accelerate"
        m[50] = "CoreUI"
        m[51] = "CoreAnimation"
        m[52] = "CGImage"
        m[53] = "MediaServices"
        m[62] = "SQLite"
        m[63] = "JavaScriptCore"
        m[64] = "JS JIT"
        m[65] = "JS JIT"
        m[67] = "CoreUI"
        m[70] = "ImageIO"
        m[73] = "IOKit"
        m[97] = "QuickLook Thumbnails"
        return m
    }()

    // PROC_PIDREGIONPATHINFO — proc_pidinfo flavor 8
    // Documented in /usr/include/sys/proc_info.h
    // Returns per-region VM info with mapped file paths.
    // Cost: 8-18ms per process. On-demand only.
    // Resident page counts only — not footprint. Label accordingly.
    public static func inspect(pid: pid_t) -> [VMRegionCategory] {
        var address: UInt64 = 0
        var info = proc_regionwithpathinfo()
        let infoSize = Int32(MemoryLayout<proc_regionwithpathinfo>.size)
        let pageSize = UInt64(vm_kernel_page_size)

        var buckets: [String: (resident: UInt64, dirty: UInt64, tag: UInt32)] = [:]

        while true {
            let result = proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, address, &info, infoSize)
            guard result == infoSize else { break }

            let tag = UInt32(info.prp_prinfo.pri_user_tag)
            let resident = UInt64(max(0, info.prp_prinfo.pri_pages_resident)) * pageSize
            let dirty = UInt64(max(0, info.prp_prinfo.pri_pages_dirtied)) * pageSize
            let label = categoryForTag[tag] ?? "Other"

            var bucket = buckets[label, default: (0, 0, tag)]
            bucket.resident += resident
            bucket.dirty += dirty
            buckets[label] = bucket

            let nextAddr = info.prp_prinfo.pri_address &+ info.prp_prinfo.pri_size
            guard nextAddr > address else { break }
            address = nextAddr
        }

        return buckets
            .map { VMRegionCategory(tag: $0.value.tag, label: $0.key,
                                    residentBytes: $0.value.resident,
                                    dirtyBytes: $0.value.dirty) }
            .filter { $0.residentBytes > 0 }
            .sorted { $0.residentBytes > $1.residentBytes }
    }
}
