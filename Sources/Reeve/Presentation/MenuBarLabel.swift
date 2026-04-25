import SwiftUI
import ReeveKit

/// The live menu bar label: chip icon + CPU of the top consumer when above 1%.
/// Below 1% the label is icon-only — noise at idle is hostile.
struct MenuBarLabel: View {
    @ObservedObject var engine: MonitoringEngine

    private var topProcess: ProcessRecord? {
        engine.snapshot.topByCPU.first.flatMap { $0.cpuPercent >= 1.0 ? $0 : nil }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "memorychip")
            if let p = topProcess {
                Text(p.formattedCPU)
                    .font(.caption.monospacedDigit())
            }
        }
    }
}
