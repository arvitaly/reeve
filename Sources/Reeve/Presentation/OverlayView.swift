import SwiftUI
import ReeveKit

/// Passive desktop widget: top processes by CPU, no action capability.
///
/// Intended to sit at desktop level beneath all app windows. Actions are available
/// via the main Reeve window or the menu bar popover.
struct OverlayView: View {
    @ObservedObject var engine: MonitoringEngine
    let onClose: () -> Void

    private var topProcesses: [ProcessRecord] {
        Array(engine.snapshot.topByCPU.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            Divider()
            if topProcesses.isEmpty {
                Text("Sampling…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(topProcesses) { process in
                    OverlayRow(process: process)
                }
            }
            Divider()
            timestampBar
        }
        .frame(width: 300)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: -

    private var titleBar: some View {
        HStack {
            Text("Reeve")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var timestampBar: some View {
        HStack {
            Text("CPU · top 8")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(engine.snapshot.sampledAt, style: .time)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

// MARK: - Row

private struct OverlayRow: View {
    let process: ProcessRecord
    @Environment(\.iconCache) private var iconCache

    var body: some View {
        HStack(spacing: 6) {
            processIcon
            Text(process.name)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(process.isReeve ? Color.accentColor : .primary)
            diskBadge
            Text(process.formattedMemory)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
            Text(process.formattedCPU)
                .font(.caption.monospacedDigit())
                .foregroundStyle(cpuColor)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .font(.caption)
    }

    @ViewBuilder
    private var diskBadge: some View {
        if let w = process.formattedDiskWrite {
            Text(w)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else if let r = process.formattedDiskRead {
            Text(r)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.blue)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var processIcon: some View {
        if let icon = iconCache.icon(for: process) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 14, height: 14)
        } else {
            Color.clear.frame(width: 14, height: 14)
        }
    }

    private var cpuColor: Color {
        if process.cpuPercent > 80 { return .red }
        if process.cpuPercent > 40 { return .orange }
        return .secondary
    }
}
