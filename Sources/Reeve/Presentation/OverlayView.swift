import SwiftUI
import ReeveKit

/// The floating overlay content: top-5-by-CPU list with inline preflight on tap.
struct OverlayView: View {
    @ObservedObject var engine: MonitoringEngine
    let onClose: () -> Void

    @State private var expanded: ProcessRecord?
    @State private var pendingAction: Action?
    @State private var preflight: PreflightResult?
    @State private var isExecuting = false
    @State private var errorMessage: String?

    private var topProcesses: [ProcessRecord] {
        Array(engine.snapshot.topByCPU.prefix(5))
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
                    OverlayRow(
                        process: process,
                        isExpanded: expanded == process,
                        pendingAction: expanded == process ? pendingAction : nil,
                        preflight: expanded == process ? preflight : nil,
                        isExecuting: expanded == process && isExecuting,
                        errorMessage: expanded == process ? errorMessage : nil,
                        onTap: { rowTapped(process) },
                        onPickKind: { pickAction(process, kind: $0) },
                        onConfirm: { confirmAction() },
                        onBack: { collapse() }
                    )
                }
            }
        }
        .frame(width: 240)
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

    private func rowTapped(_ process: ProcessRecord) {
        if expanded == process {
            collapse()
        } else {
            collapse()
            expanded = process
        }
    }

    private func pickAction(_ process: ProcessRecord, kind: Action.Kind) {
        let action = Action(target: process, kind: kind)
        pendingAction = action
        preflight = action.preflight()
        errorMessage = nil
    }

    private func confirmAction() {
        guard let action = pendingAction else { return }
        isExecuting = true
        errorMessage = nil
        Task {
            do {
                try await action.execute()
                collapse()
            } catch ActionError.processGone {
                errorMessage = "Process gone"
            } catch ActionError.permissionDenied {
                errorMessage = "Permission denied"
            } catch {
                errorMessage = error.localizedDescription
            }
            isExecuting = false
        }
    }

    private func collapse() {
        expanded = nil
        pendingAction = nil
        preflight = nil
        errorMessage = nil
        isExecuting = false
    }
}

// MARK: - Row

private struct OverlayRow: View {
    let process: ProcessRecord
    let isExpanded: Bool
    let pendingAction: Action?
    let preflight: PreflightResult?
    let isExecuting: Bool
    let errorMessage: String?
    let onTap: () -> Void
    let onPickKind: (Action.Kind) -> Void
    let onConfirm: () -> Void
    let onBack: () -> Void
    @Environment(\.iconCache) private var iconCache

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 6) {
                    processIcon
                    Text(process.name)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(process.formattedCPU)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                    Text(process.formattedMemory)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(process.isReeve ? Color.accentColor.opacity(0.08) : .clear)
            }
            .buttonStyle(.plain)
            .font(.caption)

            if isExpanded {
                expansionPanel
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private var expansionPanel: some View {
        if let preflight {
            preflightPanel(preflight)
        } else {
            actionPicker
        }
    }

    private var actionPicker: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                kindButton("Kill", kind: .kill)
                kindButton("Terminate", kind: .terminate)
            }
            HStack(spacing: 4) {
                kindButton("Suspend", kind: .suspend)
                kindButton("Lower Priority", kind: .renice(10))
            }
            Button("Cancel", action: onBack)
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
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

    private func kindButton(_ label: String, kind: Action.Kind) -> some View {
        Button(label) { onPickKind(kind) }
            .buttonStyle(.bordered)
            .font(.caption2)
            .frame(maxWidth: .infinity)
            .controlSize(.mini)
    }

    private func preflightPanel(_ result: PreflightResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.description)
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)

            if !result.warnings.isEmpty {
                ForEach(result.warnings, id: \.self) { w in
                    Label(w, systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            if let msg = errorMessage {
                Text(msg).font(.caption2).foregroundStyle(.red)
            }

            HStack(spacing: 6) {
                Button("Back", action: onBack)
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .disabled(isExecuting)
                Spacer()
                Button(result.isReversible ? "Proceed" : "Proceed — no undo") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(result.isReversible ? .accentColor : .red)
                .font(.caption2)
                .controlSize(.mini)
                .disabled(isExecuting)
            }
        }
    }
}
