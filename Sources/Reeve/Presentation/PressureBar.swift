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
                MemoryBreakdownLegend(breakdown: bd)
            }
        }
    }
}

// MARK: - Stacked breakdown bar

struct MemoryBreakdownBar: View {
    let breakdown: MemoryBreakdown
    let physical: UInt64

    private var segments: [(color: Color, fraction: Double)] {
        let total = Double(physical)
        guard total > 0 else { return [] }
        let cached = Double(breakdown.active) + Double(breakdown.inactive) - Double(breakdown.appMemory)
        return [
            (.rvMemWired,      Double(breakdown.wired) / total),
            (.rvMemActive,     Double(breakdown.appMemory) / total),
            (.rvMemCompressed, Double(breakdown.compressed) / total),
            (.rvMemInactive,   max(0, cached) / total),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
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

    var body: some View {
        HStack(spacing: 8) {
            let cached = (breakdown.active + breakdown.inactive) > breakdown.appMemory
                ? (breakdown.active + breakdown.inactive - breakdown.appMemory) : 0
            legendItem("Apps", bytes: breakdown.appMemory, color: .rvMemActive)
            legendItem("Wired", bytes: breakdown.wired, color: .rvMemWired)
            legendItem("Compressed", bytes: breakdown.compressed, color: .rvMemCompressed)
            legendItem("Cached", bytes: cached, color: .rvMemInactive)
            legendItem("Free", bytes: breakdown.free, color: .rvBarTrack)
            Spacer()
        }
    }

    private func legendItem(_ label: String, bytes: UInt64, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(label) \(shortMem(bytes))")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func shortMem(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1.0 { return String(format: "%.1fG", gb) }
        return String(format: "%.0fM", Double(bytes) / 1_048_576)
    }
}
