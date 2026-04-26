import SwiftUI
import ReeveKit

struct MenuBarLabel: View {
    @ObservedObject var engine: MonitoringEngine
    @EnvironmentObject var appState: AppState

    private enum LabelState {
        case normal
        case warn
        case over(ApplicationGroup)
    }

    private var labelState: LabelState {
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
        case .normal:    normalLabel
        case .warn:      warnLabel
        case .over(let g): overLabel(g)
        }
    }

    private var cpuText: some View {
        let pct = engine.snapshot.totalCPU
        return Group {
            if pct >= 1.0 {
                Text(String(format: "%.0f%%", pct))
                    .font(.caption.monospacedDigit())
            }
        }
    }

    private var normalLabel: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.rvDotNormal).frame(width: 7, height: 7)
            cpuText
        }
    }

    private var warnLabel: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.rvAccent).frame(width: 7, height: 7)
            cpuText
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
