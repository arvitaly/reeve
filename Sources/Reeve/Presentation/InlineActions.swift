import SwiftUI
import ReeveKit

// MARK: - Inline action bar (rendered below a selected ApplicationGroupRow)

struct InlineActionBar: View {
    let group: ApplicationGroup
    let onKill: () -> Void
    let onChipAction: (Action.Kind) -> Void
    let onAddRule: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HoldToKillButton(onFired: onKill)
            if group.isSuspended {
                chipButton("Resume", kind: .resume)
            } else {
                chipButton("Suspend", kind: .suspend)
                chipButton("Lower Priority", kind: .renice(10))
            }
            Spacer()
            Button(action: onAddRule) {
                Label("Rule", systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.rvAccent)
            .opacity(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.rvRowExpanded)
    }

    private func chipButton(_ label: String, kind: Action.Kind) -> some View {
        Button(label) { onChipAction(kind) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.caption)
    }
}

// MARK: - Hold-to-kill

struct HoldToKillButton: View {
    let onFired: () -> Void

    @GestureState private var isPressed = false
    @State private var progress: Double = 0
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.rvDanger.opacity(0.2), lineWidth: 2)
                .frame(width: 26, height: 26)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.rvDanger, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 26, height: 26)
                .rotationEffect(.degrees(-90))
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(progress > 0 ? Color.rvDanger : .secondary)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, state, _ in state = true }
        )
        .onChange(of: isPressed) { pressed in
            if pressed {
                withAnimation(.linear(duration: 0.6)) { progress = 1.0 }
                holdTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.6))
                    guard !Task.isCancelled else { return }
                    onFired()
                }
            } else {
                holdTask?.cancel()
                holdTask = nil
                withAnimation(.easeOut(duration: 0.12)) { progress = 0 }
            }
        }
        .help("Hold to force-kill all processes in this group")
    }
}

// MARK: - Confirm chip (overlay for reversible actions: suspend, renice)

struct ConfirmChip: View {
    let group: ApplicationGroup
    let kind: Action.Kind
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var isExecuting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let icon = group.icon {
                    Image(nsImage: icon)
                        .resizable().interpolation(.high)
                        .frame(width: 16, height: 16)
                }
                Text(chipTitle)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(group.formattedMemory)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(effectDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button(confirmLabel) {
                    guard !isExecuting else { return }
                    isExecuting = true
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .font(.caption)
                .disabled(isExecuting)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4, y: -2)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private var chipTitle: String {
        switch kind {
        case .suspend:   return "Suspend \(group.displayName)?"
        case .resume:    return "Resume \(group.displayName)?"
        case .renice:    return "Lower Priority of \(group.displayName)?"
        default:         return group.displayName
        }
    }

    private var effectDescription: String {
        let n = group.processes.count
        let s = n == 1 ? "" : "es"
        switch kind {
        case .suspend:
            return "Pauses \(n) process\(s) — memory remains reserved. Resume to restore."
        case .resume:
            return "Resumes \(n) paused process\(s)."
        case .renice(let v):
            return "Lowers scheduling priority (nice +\(v)) for \(n) process\(s). Reversible."
        default:
            return ""
        }
    }

    private var confirmLabel: String {
        switch kind {
        case .suspend: return "Suspend All"
        case .resume:  return "Resume All"
        case .renice:  return "Lower Priority"
        default:       return "Proceed"
        }
    }
}
