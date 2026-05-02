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

    private var memLabel: String {
        let total = ByteCountFormatter.string(
            fromByteCount: Int64(snapshot.physicalMemory), countStyle: .memory
        )
        guard let used = snapshot.usedMemory else { return "— / \(total)" }
        let usedStr = ByteCountFormatter.string(fromByteCount: Int64(used), countStyle: .memory)
        return "\(usedStr) / \(total)"
    }

    private var cpuLabel: String {
        String(format: "CPU %.0f%%", snapshot.totalCPU)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(memLabel)
                    .font(RVFont.mono(size: 10))
                    .foregroundStyle(severity != .normal ? severity.textColor : Color.rvTextFaint)
                Spacer()
                Text(cpuLabel)
                    .font(RVFont.mono(size: 10))
                    .foregroundStyle(Color.rvTextFaint)
            }
            if let bd = snapshot.memoryBreakdown {
                MemoryBreakdownBar(breakdown: bd, physical: snapshot.physicalMemory)
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
                .frame(height: 5)
            }
            if let bd = snapshot.memoryBreakdown {
                MemoryBreakdownLegend(breakdown: bd, physical: snapshot.physicalMemory)
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

private func memSegments(_ bd: MemoryBreakdown, physical: UInt64) -> [MemSegment] {
    var segs = [
        MemSegment(id: "Apps", bytes: bd.appMemory, color: .rvMemActive),
        MemSegment(id: "GPU", bytes: bd.gpuInUse, color: .purple.opacity(0.7)),
        MemSegment(id: "Wired", bytes: bd.wired, color: .rvMemWired),
        MemSegment(id: "Compressed", bytes: bd.compressed, color: .rvMemCompressed),
        MemSegment(id: "Cached", bytes: bd.cached, color: .rvMemInactive),
        MemSegment(id: "Free", bytes: bd.free, color: .rvBarTrack),
    ]
    .filter { $0.bytes > 0 }
    .sorted { $0.bytes > $1.bytes }
    let total = Double(physical)
    guard total > 0 else { return segs }
    for i in segs.indices { segs[i].fraction = Double(segs[i].bytes) / total }
    return segs
}

struct MemoryBreakdownBar: View {
    let breakdown: MemoryBreakdown
    let physical: UInt64

    var body: some View {
        let segs = memSegments(breakdown, physical: physical)
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
        .frame(height: 5)
    }
}

// MARK: - Legend row

struct MemoryBreakdownLegend: View {
    let breakdown: MemoryBreakdown
    let physical: UInt64

    var body: some View {
        let segs = memSegments(breakdown, physical: physical)
        HStack(spacing: 8) {
            ForEach(segs) { seg in
                HStack(spacing: 3) {
                    Circle().fill(seg.color).frame(width: 5, height: 5)
                    Text("\(seg.id) \(shortMem(seg.bytes))")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func shortMem(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1.0 { return String(format: "%.1fG", gb) }
        return String(format: "%.0fM", Double(bytes) / 1_048_576)
    }
}
