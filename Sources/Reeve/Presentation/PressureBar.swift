import SwiftUI
import ReeveKit

/// Full-width bar showing system RAM breakdown and total CPU.
///
/// In v0.2.16 the legend below the bar was killed in favor of a sibling
/// `MemorySummaryLine` (3 highlights + Detail chevron) and an inline
/// `MemoryDetailPanel`. This view renders only the header text + the
/// stacked bar visual, with the diagonal-stripe pattern overlaying any
/// unmeasurable segment per CLAUDE.md's honest-absence rule.
struct PressureBar: View {
    let snapshot: SystemSnapshot
    let model: MemoryModel

    private var fill: Double {
        guard let used = snapshot.usedMemory, snapshot.physicalMemory > 0 else { return 0 }
        return min(1.0, Double(used) / Double(snapshot.physicalMemory))
    }

    private var severity: Severity {
        if fill >= 0.90 { return .over }
        if fill >= 0.75 { return .warn }
        return .normal
    }

    private var usedLabel: String {
        guard let used = snapshot.usedMemory else { return "—" }
        return shortGB(used)
    }

    private var availLabel: String {
        guard let bd = snapshot.memoryBreakdown else { return "" }
        return shortGB(bd.free + bd.cached)
    }

    private var cpuLabel: String {
        String(format: "CPU %.0f%%", snapshot.totalCPU)
    }

    private func shortGB(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return gb >= 10 ? String(format: "%.0fG", gb) : String(format: "%.1fG", gb)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(usedLabel)
                    .font(RVFont.mono(size: 10))
                    .foregroundStyle(severity != .normal ? severity.textColor : Color.rvTextFaint)
                Text("/")
                    .font(RVFont.mono(size: 10))
                    .foregroundStyle(Color.rvTextFaint)
                Text(shortGB(snapshot.physicalMemory))
                    .font(RVFont.mono(size: 10))
                    .foregroundStyle(Color.rvTextFaint)
                if !availLabel.isEmpty {
                    Text("(\(availLabel) avail)")
                        .font(RVFont.mono(size: 9))
                        .foregroundStyle(.green.opacity(0.7))
                }
                Spacer()
                Text(cpuLabel)
                    .font(RVFont.mono(size: 10))
                    .foregroundStyle(Color.rvTextFaint)
            }
            if snapshot.memoryBreakdown != nil {
                MemoryBreakdownBar(model: model)
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Color.rvBarTrack)
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(severity.barColor)
                            .frame(width: geo.size.width * fill)
                    }
                }
                .frame(height: 10)
            }
        }
    }
}

// MARK: - Stacked breakdown bar

struct MemoryBreakdownBar: View {
    let model: MemoryModel

    var body: some View {
        let segs = orderedSegments
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(segs) { seg in
                    segmentView(seg, width: max(0, geo.size.width * seg.fraction))
                }
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2.5))
            .background(RoundedRectangle(cornerRadius: 2.5).fill(Color.rvBarTrack))
        }
        .frame(height: 10)
        .animation(.easeInOut(duration: 0.45), value: model.usedBytes)
    }

    /// Used segments first, biggest-first within each group; available segments
    /// at the tail (cached then free) so visual weight always matches reality.
    private var orderedSegments: [MemorySegment] {
        let used = model.usedSegments.filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
        let avail = model.availableSegments.filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
        return used + avail
    }

    @ViewBuilder
    private func segmentView(_ seg: MemorySegment, width: CGFloat) -> some View {
        if seg.isUnmeasurable {
            ZStack {
                Rectangle().fill(seg.color)
                UnmeasurableStripes(spacing: 2.5, lineWidth: 0.8, opacity: 0.6)
            }
            .frame(width: width)
        } else {
            Rectangle()
                .fill(seg.color)
                .frame(width: width)
        }
    }
}
