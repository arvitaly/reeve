import SwiftUI
import ReeveKit

/// Full-width bar showing system RAM usage and total CPU, placed in the popover/widget header.
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
                    .foregroundStyle(Color.rvTextFaint)
                Spacer()
                Text(cpuLabel)
                    .font(RVFont.mono(size: 10))
                    .foregroundStyle(Color.rvTextFaint)
            }
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
    }
}
