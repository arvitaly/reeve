import SwiftUI
import ReeveKit

enum MenuBarMetric: String, CaseIterable {
    case cpu    = "cpu"
    case memory = "memory"
    case none   = "none"

    var label: String {
        switch self {
        case .cpu:    return "CPU %"
        case .memory: return "Memory"
        case .none:   return "None"
        }
    }
}

// Brackets + filled rect — mirrors reeve-menubar-template.svg geometry (viewBox 0 0 1024 1024).
private struct ReeveIcon: View {
    var color: Color = .primary
    var size: CGFloat = 16

    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            let sw = max(1.5, w * 0.09)

            var lb = Path()
            lb.move(to:    CGPoint(x: w * 0.273, y: h * 0.273))
            lb.addLine(to: CGPoint(x: w * 0.195, y: h * 0.273))
            lb.addLine(to: CGPoint(x: w * 0.195, y: h * 0.727))
            lb.addLine(to: CGPoint(x: w * 0.273, y: h * 0.727))
            ctx.stroke(lb, with: .color(color),
                       style: StrokeStyle(lineWidth: sw, lineCap: .round, lineJoin: .round))

            var rb = Path()
            rb.move(to:    CGPoint(x: w * 0.727, y: h * 0.273))
            rb.addLine(to: CGPoint(x: w * 0.805, y: h * 0.273))
            rb.addLine(to: CGPoint(x: w * 0.805, y: h * 0.727))
            rb.addLine(to: CGPoint(x: w * 0.727, y: h * 0.727))
            ctx.stroke(rb, with: .color(color),
                       style: StrokeStyle(lineWidth: sw, lineCap: .round, lineJoin: .round))

            let rx = w * 0.375, ry = h * 0.406, rw = w * 0.250, rh = h * 0.188
            let cr = min(rw, rh) * 0.125
            ctx.fill(Path(roundedRect: CGRect(x: rx, y: ry, width: rw, height: rh),
                          cornerRadius: cr),
                     with: .color(color))
        }
        .frame(width: size, height: size)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var engine: MonitoringEngine
    @EnvironmentObject var appState: AppState
    @AppStorage("menuBarMetric") private var metric: MenuBarMetric = .cpu

    private enum LabelState {
        case flash
        case normal
        case warn
        case over(ApplicationGroup)
    }

    private var labelState: LabelState {
        if let exp = appState.killFlashExpiry, exp > .now { return .flash }
        let (apps, _) = buildApplicationGroups(snapshot: engine.snapshot)
        var hasWarn = false
        for app in apps {
            let cap = memCap(for: app, in: appState.groupRuleSpecs)
            switch app.overallSeverity(cap: cap) {
            case .over: return .over(app)
            case .warn: hasWarn = true
            case .normal: break
            }
        }
        if hasWarn || engine.snapshot.totalCPU > 50 { return .warn }
        return .normal
    }

    var body: some View {
        switch labelState {
        case .flash:       flashLabel
        case .normal:      normalLabel
        case .warn:        warnLabel
        case .over(let g): overLabel(g)
        }
    }

    @ViewBuilder private var metricText: some View {
        switch metric {
        case .cpu:
            let pct = engine.snapshot.totalCPU
            if pct >= 1.0 {
                Text(String(format: "%.0f%%", pct))
                    .font(.caption.monospacedDigit())
            }
        case .memory:
            if let used = engine.snapshot.usedMemory {
                Text(shortMem(used))
                    .font(.caption.monospacedDigit())
            }
        case .none:
            EmptyView()
        }
    }

    private var flashLabel: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.green).frame(width: 7, height: 7)
                .shadow(color: .green.opacity(0.6), radius: 3)
            Text("—").font(.caption.monospacedDigit()).foregroundStyle(Color.green)
        }
    }

    private var normalLabel: some View {
        HStack(spacing: 4) {
            ReeveIcon(color: .primary.opacity(0.6))
            metricText
        }
    }

    private var warnLabel: some View {
        HStack(spacing: 4) {
            ReeveIcon(color: Color.rvAccent)
            metricText
        }
    }

    @ViewBuilder
    private func overLabel(_ group: ApplicationGroup) -> some View {
        HStack(spacing: 3) {
            if let icon = group.icon {
                Image(nsImage: icon)
                    .resizable().interpolation(.high)
                    .frame(width: 14, height: 14)
            }
            Circle().fill(Color.rvDanger).frame(width: 6, height: 6)
            Text(shortMem(group.totalMemory))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.rvDanger)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.rvDanger.opacity(0.12))
        .clipShape(Capsule())
    }

    private func shortMem(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1.0 { return String(format: "%.1fG", gb) }
        return String(format: "%.0fM", Double(bytes) / (1024 * 1024))
    }
}
