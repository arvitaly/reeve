@preconcurrency import Darwin
import Foundation

private let kPageSize = UInt64(vm_kernel_page_size)

public struct VMRegionCategory: Sendable, Identifiable {
    public let tag: UInt32
    public let label: String
    public let residentBytes: UInt64
    public let dirtyBytes: UInt64
    public var id: String { label }
}

public enum RegionInspector {
    // VM tags from <mach/vm_statistics.h>
    private static let categoryForTag: [UInt32: String] = {
        var m: [UInt32: String] = [:]
        for t: UInt32 in 1...11 { m[t] = "MALLOC" }
        m[20] = "Mach msg"
        m[21] = "IOKit"
        m[30] = "Stack"
        m[31] = "Guard"
        m[32] = "Shared pmap"
        m[33] = "Dylib"
        m[34] = "ObjC dispatchers"
        m[35] = "Unshared pmap"
        m[40] = "AppKit"
        m[41] = "Foundation"
        m[42] = "CoreGraphics"
        m[43] = "CoreServices"
        m[44] = "Carbon"
        m[45] = "CoreData"
        m[46] = "CoreData"
        m[50] = "ATS"
        m[51] = "CoreAnimation"
        m[52] = "CGImage"
        m[53] = "tcmalloc"
        m[54] = "CG data"
        m[55] = "CG shared"
        m[56] = "CG framebuffers"
        m[57] = "CG backingstores"
        m[58] = "CG misc"
        m[60] = "dyld"
        m[61] = "dyld malloc"
        m[62] = "SQLite"
        m[63] = "JavaScriptCore"
        m[64] = "JS JIT"
        m[65] = "JS JIT"
        m[66] = "GLSL"
        m[67] = "OpenCL"
        m[68] = "CoreImage"
        m[69] = "WebKit purgeable"
        m[70] = "ImageIO"
        m[71] = "CoreProfile"
        m[72] = "AssetSD"
        m[73] = "OS alloc once"
        m[74] = "libdispatch"
        m[75] = "Accelerate"
        m[76] = "CoreUI"
        m[77] = "CoreUI file"
        m[78] = "Genealogy"
        m[79] = "RawCamera"
        m[80] = "Corpse info"
        m[81] = "ASL"
        m[82] = "Swift runtime"
        m[83] = "Swift metadata"
        m[85] = "SceneKit"
        m[86] = "Skywalk"
        m[87] = "IOSurface"
        m[88] = "libnetwork"
        m[89] = "Audio"
        m[90] = "Video"
        m[96] = "QuickLook Thumbnails"
        m[98] = "Sanitizer"
        m[99] = "IOAccelerator"
        return m
    }()

    // PROC_PIDREGIONPATHINFO — proc_pidinfo flavor 8
    // Documented in /usr/include/sys/proc_info.h
    // Returns per-region VM info with mapped file paths.
    // Cost: 8-18ms per process. On-demand only.
    // Resident page counts only — not footprint. Label accordingly.
    public static func inspectAll(pids: [pid_t]) -> [VMRegionCategory] {
        var merged: [String: (resident: UInt64, dirty: UInt64, tag: UInt32)] = [:]
        for pid in pids {
            for cat in inspect(pid: pid) {
                var bucket = merged[cat.label, default: (0, 0, cat.tag)]
                bucket.resident += cat.residentBytes
                bucket.dirty += cat.dirtyBytes
                merged[cat.label] = bucket
            }
        }
        return merged
            .map { VMRegionCategory(tag: $0.value.tag, label: $0.key,
                                    residentBytes: $0.value.resident,
                                    dirtyBytes: $0.value.dirty) }
            .filter { $0.residentBytes > 0 }
            .sorted { $0.residentBytes > $1.residentBytes }
    }

    public static func inspect(pid: pid_t) -> [VMRegionCategory] {
        var address: UInt64 = 0
        var info = proc_regionwithpathinfo()
        let infoSize = Int32(MemoryLayout<proc_regionwithpathinfo>.size)
        let pageSize = kPageSize

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
