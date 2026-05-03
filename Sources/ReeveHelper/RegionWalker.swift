@preconcurrency import Darwin
import Foundation
import OSLog
import ReeveKit

/// Walks a target task's VM map via `proc_pidinfo(PROC_PIDREGIONPATHINFO)`,
/// categorising regions by `pri_user_tag`. Running as root, this works for
/// every process — including root-owned daemons that return EPERM when the
/// non-privileged Reeve.app calls the same API.
///
/// Output: `PIDRegionSummary` with per-tag buckets, the shared-anonymous
/// total (regions with no tag we recognise where share_mode == SM_SHARED),
/// and the page-table total (tag 27 in xnu's `<mach/vm_statistics.h>`).
enum RegionWalker {
    private static let log = Logger(subsystem: "com.reeve.helper", category: "regions")

    static func summaries(for pids: [pid_t]) -> [PIDRegionSummary] {
        pids.compactMap { summary(for: $0) }
    }

    static func summary(for pid: pid_t) -> PIDRegionSummary? {
        let pageSize = UInt64(vm_kernel_page_size)
        var address: UInt64 = 0
        var info = proc_regionwithpathinfo()
        let infoSize = Int32(MemoryLayout<proc_regionwithpathinfo>.size)

        var buckets: [UInt32: (resident: UInt64, dirty: UInt64, swapped: UInt64)] = [:]
        var sharedAnon: UInt64 = 0
        var pageTable: UInt64 = 0

        var sawAny = false

        while true {
            let result = proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, address, &info, infoSize)
            if result != infoSize { break }
            sawAny = true

            let tag = UInt32(info.prp_prinfo.pri_user_tag)
            let resident = UInt64(max(0, info.prp_prinfo.pri_pages_resident)) * pageSize
            let dirty = UInt64(max(0, info.prp_prinfo.pri_pages_dirtied)) * pageSize
            let swapped = UInt64(max(0, info.prp_prinfo.pri_pages_swapped_out)) * pageSize

            if tag == VMRegionCategorizer.pageTableTag {
                pageTable += resident
            } else if VMRegionCategorizer.isSharedAnonymous(info.prp_prinfo) {
                sharedAnon += resident
            } else {
                var bucket = buckets[tag, default: (0, 0, 0)]
                bucket.resident += resident
                bucket.dirty += dirty
                bucket.swapped += swapped
                buckets[tag] = bucket
            }

            let next = info.prp_prinfo.pri_address &+ info.prp_prinfo.pri_size
            if next <= address { break }
            address = next
        }

        if !sawAny {
            return PIDRegionSummary(
                pid: pid, physFootprint: 0, buckets: [],
                sharedAnonBytes: 0, pageTableBytes: 0, unavailable: true
            )
        }

        let mappedBuckets = buckets.compactMap { (tag, totals) -> RegionBucket? in
            guard totals.resident > 0 else { return nil }
            let label = VMRegionCategorizer.label(for: tag)
            return RegionBucket(
                tag: tag, label: label,
                residentBytes: totals.resident,
                dirtyBytes: totals.dirty,
                swappedBytes: totals.swapped
            )
        }
        .sorted { $0.residentBytes > $1.residentBytes }

        let footprint = readPhysFootprint(pid: pid)

        return PIDRegionSummary(
            pid: pid,
            physFootprint: footprint,
            buckets: mappedBuckets,
            sharedAnonBytes: sharedAnon,
            pageTableBytes: pageTable,
            unavailable: false
        )
    }

    private static func readPhysFootprint(pid: pid_t) -> UInt64 {
        var rusage = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &rusage) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return ok == 0 ? rusage.ri_phys_footprint : 0
    }
}

/// Centralised tag→label table. xnu's vm_statistics.h enumerates the tags;
/// Apple may add more, so unknown tags get a synthesised "Tag #N" label
/// instead of being silently dropped.
enum VMRegionCategorizer {
    /// VM_MEMORY_PAGE_TABLE in xnu's `<mach/vm_statistics.h>`.
    static let pageTableTag: UInt32 = 27

    /// True when the region is anonymous (no file backing in this flavor)
    /// AND share_mode reports SM_SHARED (multiple tasks see it).
    /// Conservatively treat SM_SHARED_ALIASED as well.
    static func isSharedAnonymous(_ info: proc_regioninfo) -> Bool {
        let shareMode = Int32(info.pri_share_mode)
        let isShared = shareMode == SM_SHARED || shareMode == SM_SHARED_ALIASED
        let untagged = info.pri_user_tag == 0
        return isShared && untagged
    }

    static func label(for tag: UInt32) -> String {
        if let known = knownLabels[tag] { return known }
        return "Tag #\(tag)"
    }

    private static let knownLabels: [UInt32: String] = {
        var m: [UInt32: String] = [:]
        for t: UInt32 in 1...11 { m[t] = "MALLOC" }
        m[20] = "Mach msg"
        m[21] = "IOKit"
        m[27] = "Page table"
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
}
