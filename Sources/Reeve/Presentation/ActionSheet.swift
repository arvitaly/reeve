import SwiftUI
import ReeveKit

struct ActionSheet: View {
    let process: ProcessInfo
    @Environment(\.dismiss) private var dismiss
    @State private var pending: (action: Action, preflight: PreflightResult)?
    @State private var isExecuting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            processHeader
            Divider()
            if let (_, preflight) = pending {
                PreflightView(result: preflight)
                Divider()
                confirmButtons(preflight: preflight)
            } else {
                actionMenu
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private var processHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(process.name).font(.headline)
                if process.isReeve {
                    Text("(this app)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("PID \(process.pid)  ·  \(process.formattedMemory)  ·  \(process.formattedCPU)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var actionMenu: some View {
        VStack(spacing: 8) {
            actionButton("Terminate", kind: .terminate)
            actionButton("Force Kill", kind: .kill)
            actionButton("Suspend", kind: .suspend)
            actionButton("Lower Priority", kind: .renice(10))
            Button("Cancel") { dismiss() }.buttonStyle(.plain).font(.caption)
        }
    }

    private func actionButton(_ label: String, kind: Action.Kind) -> some View {
        Button(label) {
            let action = Action(target: process, kind: kind)
            pending = (action, action.preflight())
            error = nil
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }

    private func confirmButtons(preflight: PreflightResult) -> some View {
        HStack {
            Button("Back") { pending = nil }
            Spacer()
            Button(preflight.isReversible ? "Proceed" : "Proceed — cannot undo") {
                guard let (action, _) = pending else { return }
                isExecuting = true
                Task {
                    do {
                        try await action.execute()
                        dismiss()
                    } catch ActionError.processGone {
                        error = "Process no longer exists"
                    } catch ActionError.permissionDenied {
                        error = "Permission denied"
                    } catch {
                        self.error = error.localizedDescription
                    }
                    isExecuting = false
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(preflight.isReversible ? .accentColor : .red)
            .disabled(isExecuting)
        }
    }
}

struct PreflightView: View {
    let result: PreflightResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(result.description)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: result.isReversible ? "arrow.uturn.left.circle" : "exclamationmark.triangle")
                Text(result.isReversible ? "Reversible" : "Irreversible")
            }
            .font(.caption)
            .foregroundStyle(result.isReversible ? Color.green : Color.red)

            effectRow

            ForEach(result.warnings, id: \.self) { warning in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                    Text(warning)
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var effectRow: some View {
        switch result.effect {
        case .known(let desc):
            Text(desc).font(.caption).foregroundStyle(.secondary)
        case .unknown(let reason):
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                Text("Effect unknown: \(reason)")
            }
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }
}
