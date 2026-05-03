import SwiftUI
import ReeveKit

/// Single source of truth for everything the memory UI needs to render.
/// Compute once per snapshot; pass into bar, summary line, and detail panel.
///
/// Keeping the breakdown logic in one place keeps the bar and the panel
/// honestly synchronised — no chance of one segment appearing in the bar
/// but not in the legend, or summing differently.
struct MemoryModel {
    let segments: [MemorySegment]
    let physical: UInt64
    let usedBytes: UInt64
    let availableBytes: UInt64

    /// Convenience: every entry that contributes to "in use".
    var usedSegments: [MemorySegment] { segments.filter { $0.role == .used } }
    /// Convenience: cached + free.
    var availableSegments: [MemorySegment] { segments.filter { $0.role == .available } }

    /// Top three used segments, biggest first — for the compact summary line.
    /// Always includes the unmeasured "Other" segment when its bytes are non-zero,
    /// even if it isn't in the natural top three.
    var summaryHighlights: [MemorySegment] {
        let used = usedSegments
        let topThree = Array(used.sorted { $0.bytes > $1.bytes }.prefix(3))
        if let other = used.first(where: { $0.isUnmeasurable }), !topThree.contains(where: { $0.id == other.id }) {
            return Array(topThree.prefix(2)) + [other]
        }
        return topThree
    }

    /// True when at least one used segment is unmeasurable; tells the summary
    /// line whether to render the [?] hint after the highlights.
    var hasUnmeasurable: Bool { usedSegments.contains { $0.isUnmeasurable && $0.bytes > 0 } }

    init(snapshot: SystemSnapshot) {
        guard let bd = snapshot.memoryBreakdown else {
            self.segments = []
            self.physical = snapshot.physicalMemory
            self.usedBytes = 0
            self.availableBytes = 0
            return
        }

        let attributed = snapshot.processFootprintSum + snapshot.invisibleFootprintSum
        let appsBytes = min(attributed, bd.appMemory)
        let remaining = bd.appMemory.subtractingClampedToZero(appsBytes)
        let iokitBytes = min(bd.iokitPageable, remaining)
        let otherBytes = remaining.subtractingClampedToZero(iokitBytes)

        let physical = snapshot.physicalMemory
        let usedBytes = bd.used                       // appMemory + wired + compressed
        let availableBytes = bd.cached + bd.free

        var raw: [MemorySegment] = []

        raw.append(MemorySegment(
            id: "apps",
            label: "Apps",
            bytes: appsBytes,
            color: .rvMemActive,
            role: .used,
            isUnmeasurable: false,
            description: "Things you opened. Click an app below to act.",
            source: "Σ phys_footprint per process (proc_pid_rusage + top for root-owned)"
        ))

        raw.append(MemorySegment(
            id: "iokit",
            label: "IOKit buffers",
            bytes: iokitBytes,
            color: .blue.opacity(0.55),
            role: .used,
            isUnmeasurable: false,
            description: "Kernel-side buffers for graphics, audio and video that don't belong to a specific app.",
            source: "IORegistry root → IOKitDiagnostics[\"Pageable allocation\"], clamped to remaining anonymous"
        ))

        raw.append(MemorySegment(
            id: "other",
            label: "Other (unmeasured)",
            bytes: otherBytes,
            color: Color.rvDotNormal.opacity(0.45),
            role: .used,
            isUnmeasurable: true,
            description: "Memory used by the system that we cannot attribute without running as root. Likely contains: shared buffers between apps · kernel data structures · GPU mappings we can't probe.",
            source: "vm_stat anonymous − everything we can name"
        ))

        raw.append(MemorySegment(
            id: "wired",
            label: "System wired",
            bytes: bd.wired,
            color: .rvMemWired,
            role: .used,
            isUnmeasurable: false,
            description: "Locked memory the kernel and drivers can never give up. Always present, varies a little.",
            source: "wire_count × page_size (host_statistics64 / HOST_VM_INFO64)"
        ))

        raw.append(MemorySegment(
            id: "gpu",
            label: "GPU",
            bytes: bd.gpuInUse,
            color: .purple.opacity(0.7),
            role: .used,
            isUnmeasurable: false,
            description: "What your screen, video and ML are using right now. Some of this overlaps with apps.",
            source: "IOAccelerator → PerformanceStatistics[\"In use system memory\"]"
        ))

        raw.append(MemorySegment(
            id: "compressed",
            label: "Compressed",
            bytes: bd.compressed,
            color: .rvMemCompressed,
            role: .used,
            isUnmeasurable: false,
            description: "App memory the system squeezed smaller because it wasn't actively used. Counts as used until uncompressed.",
            source: "compressor_page_count × page_size"
        ))

        raw.append(MemorySegment(
            id: "cached",
            label: "Cached files",
            bytes: bd.cached,
            color: .rvMemInactive,
            role: .available,
            isUnmeasurable: false,
            description: "Files and code kept in RAM in case you need them again. Reclaimed instantly under pressure. Counts as available.",
            source: "(active + inactive) − appMemory"
        ))

        raw.append(MemorySegment(
            id: "free",
            label: "Free",
            bytes: bd.free,
            color: .rvBarTrack,
            role: .available,
            isUnmeasurable: false,
            description: "Untouched RAM. Most healthy systems run with very little here — that's normal, not a problem.",
            source: "free_count × page_size"
        ))

        let total = max(Double(physical), 1)
        self.segments = raw.map { seg in
            var s = seg
            s.fraction = Double(seg.bytes) / total
            return s
        }
        self.physical = physical
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
    }
}

/// One row in the memory model. Carries enough metadata to render the bar
/// segment, the summary pill, the detail row, and the educational tooltip.
struct MemorySegment: Identifiable {
    enum Role { case used, available }

    let id: String
    /// Plain-English label. Suitable for direct display.
    let label: String
    let bytes: UInt64
    let color: Color
    let role: Role
    /// True when we cannot attribute this number to anything specific — render
    /// with the diagonal-stripe swatch and dim copy.
    let isUnmeasurable: Bool
    /// One-sentence plain-English description for the detail panel.
    let description: String
    /// Source-of-truth API or computation, shown in dim mono in the detail panel.
    let source: String
    var fraction: Double = 0

    var percentOfPhysical: Int {
        Int((fraction * 100).rounded())
    }
}

private extension UInt64 {
    func subtractingClampedToZero(_ other: UInt64) -> UInt64 {
        self > other ? self - other : 0
    }
}
