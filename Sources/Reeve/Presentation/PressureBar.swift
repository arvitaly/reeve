import SwiftUI
import ReeveKit

/// Full-width bar showing system RAM breakdown and total CPU, placed in the popover/widget header.
struct PressureBar: View {
    let snapshot: SystemSnapshot

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
        VStack(alignment: .leading, spacing: 3) {
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
                MemoryBreakdownBar(snapshot: snapshot)
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
            if snapshot.memoryBreakdown != nil {
                MemoryBreakdownLegend(snapshot: snapshot)
            }
        }
    }
}

// MARK: - Stacked breakdown bar

private struct MemSegment: Identifiable {
    let id: String
    let bytes: UInt64
    let color: Color
    var fraction: Double = 0
}

private func memSegments(_ snapshot: SystemSnapshot) -> [MemSegment] {
    guard let bd = snapshot.memoryBreakdown else { return [] }
    let physical = snapshot.physicalMemory
    let measured = snapshot.processFootprintSum + snapshot.epermProcessRSS + snapshot.invisibleRSSSum
    let procsBytes = min(snapshot.processFootprintSum, bd.appMemory)
    let daemonRSS = snapshot.invisibleRSSSum
    let untraced = bd.appMemory.subtractingClamped(min(measured, bd.appMemory))
    let used: [MemSegment] = [
        MemSegment(id: "Apps", bytes: procsBytes, color: .rvMemActive),
        MemSegment(id: "Daemons", bytes: daemonRSS, color: .orange.opacity(0.6)),
        MemSegment(id: "Untraced", bytes: untraced, color: .gray.opacity(0.4)),
        MemSegment(id: "GPU", bytes: bd.gpuInUse, color: .purple.opacity(0.7)),
        MemSegment(id: "Wired", bytes: bd.wired, color: .rvMemWired),
        MemSegment(id: "Compr", bytes: bd.compressed, color: .rvMemCompressed),
    ]
    .filter { $0.bytes > 0 }
    .sorted { $0.bytes > $1.bytes }
    let avail: [MemSegment] = [
        MemSegment(id: "Cached", bytes: bd.cached, color: .rvMemInactive),
        MemSegment(id: "Free", bytes: bd.free, color: .rvBarTrack),
    ]
    .filter { $0.bytes > 0 }
    .sorted { $0.bytes > $1.bytes }
    var segs = used + avail
    let total = Double(physical)
    guard total > 0 else { return segs }
    for i in segs.indices { segs[i].fraction = Double(segs[i].bytes) / total }
    return segs
}

private extension UInt64 {
    func subtractingClamped(_ other: UInt64) -> UInt64 {
        self > other ? self - other : 0
    }
}

struct MemoryBreakdownBar: View {
    let snapshot: SystemSnapshot

    var body: some View {
        let segs = memSegments(snapshot)
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(segs) { seg in
                    Rectangle()
                        .fill(seg.color)
                        .frame(width: max(0, geo.size.width * seg.fraction))
                }
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2.5))
            .background(RoundedRectangle(cornerRadius: 2.5).fill(Color.rvBarTrack))
        }
        .frame(height: 10)
    }
}

// MARK: - Legend row

struct MemoryBreakdownLegend: View {
    let snapshot: SystemSnapshot

    var body: some View {
        let segs = memSegments(snapshot)
        FlowLayout(spacing: 6) {
            ForEach(segs) { seg in
                HStack(spacing: 2) {
                    Circle().fill(seg.color).frame(width: 5, height: 5)
                    Text("\(seg.id) \(shortMem(seg.bytes))")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func shortMem(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 10 { return String(format: "%.0fG", gb) }
        if gb >= 1.0 { return String(format: "%.1fG", gb) }
        return String(format: "%.0fM", Double(bytes) / 1_048_576)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrangeRows(proposal: proposal, subviews: subviews)
        guard let last = rows.last else { return .zero }
        return CGSize(width: proposal.width ?? 0, height: last.y + last.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrangeRows(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (i, pos) in rows.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y),
                              proposal: .unspecified)
        }
    }

    private struct Pos { var x: CGFloat; var y: CGFloat; var height: CGFloat }

    private func arrangeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Pos] {
        let maxW = proposal.width ?? .infinity
        var result: [Pos] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxW && x > 0 {
                y += rowH + 2
                x = 0
                rowH = 0
            }
            result.append(Pos(x: x, y: y, height: size.height))
            rowH = max(rowH, size.height)
            x += size.width + spacing
        }
        return result
    }
}
