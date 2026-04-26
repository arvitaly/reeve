import SwiftUI
import ReeveKit

// MARK: - Inline rule creation (sentence syntax)

struct GroupRuleSheet: View {
    let group: ApplicationGroup
    let onSave: (GroupRuleSpec) -> Void
    let onCancel: () -> Void

    @State private var appNamePattern: String
    @State private var capGB: Double
    @State private var action: GroupRuleSpec.ActionKind = .reniceDown

    init(group: ApplicationGroup,
         onSave: @escaping (GroupRuleSpec) -> Void,
         onCancel: @escaping () -> Void)
    {
        self.group = group
        self.onSave = onSave
        self.onCancel = onCancel
        let currentGB = Double(group.totalMemory) / 1_073_741_824
        _appNamePattern = State(initialValue: group.displayName)
        _capGB = State(initialValue: Self.suggestedCap(currentGB: currentGB))
    }

    static func suggestedCap(currentGB: Double) -> Double {
        max(0.25, floor(currentGB * 0.75 / 0.5) * 0.5)
    }

    private var currentGB: Double { Double(group.totalMemory) / 1_073_741_824 }

    private var previewSeverity: Severity {
        let pct = currentGB / capGB
        if pct >= 1.0 { return .over }
        if pct >= 0.7 { return .warn }
        return .normal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Rule").font(.caption.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("When").font(.caption).foregroundStyle(.secondary)
                    TextField("app name", text: $appNamePattern)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 130)
                    Text("memory exceeds").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Stepper(value: $capGB, in: 0.25...64, step: 0.25) {
                        Text(String(format: "%.2f GB", capGB))
                            .font(.caption.monospacedDigit())
                            .frame(width: 62, alignment: .trailing)
                    }
                    Text("→").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $action) {
                        ForEach(GroupRuleSpec.ActionKind.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 6) {
                Text("Now:").font(.caption2).foregroundStyle(.secondary)
                MiniBar(
                    value: Double(group.totalMemory),
                    cap: capGB * 1_073_741_824,
                    width: 80,
                    severity: previewSeverity
                )
                SeverityDot(severity: previewSeverity)
                Text(String(format: "%.1fG / %.1fG cap", currentGB, capGB))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Save Rule") {
                    onSave(GroupRuleSpec(
                        appNamePattern: appNamePattern,
                        condition: .totalMemoryAboveGB(capGB),
                        action: action,
                        cooldownSeconds: 60,
                        isEnabled: true
                    ))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .font(.caption)
                .disabled(appNamePattern.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4, y: -2)
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }
}

// MARK: - Toast

struct Toast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .shadow(radius: 2)
            .padding(.bottom, 10)
    }
}
