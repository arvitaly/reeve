import SwiftUI
import ReeveKit

struct DiagnosticPanel: View {
    let context: ProbeContext
    let cache: DiagnosticCache

    @State private var findings: [Finding] = []
    @State private var isLoading = false
    @State private var confirmingRemediation: Remediation?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("DIAGNOSTICS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.rvTextFaint)
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                }
                Spacer()
            }

            if let rem = confirmingRemediation {
                remediationPreflight(rem)
            } else {
                ForEach(findings) { finding in
                    findingRow(finding)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.rvInputBg, in: RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 10)
        .task(id: context.leadPID) {
            await loadFindings()
        }
    }

    private func findingRow(_ finding: Finding) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(confidenceColor(finding.severity))
                .frame(width: 5, height: 5)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(finding.cause)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.rvText)
                Text(finding.evidence)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.rvTextFaint)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if let rem = finding.suggestedRemediation {
                ActionChip(
                    label: rem.title,
                    kind: remediationChipKind(rem.kind),
                    action: { confirmingRemediation = rem }
                )
            }
        }
    }

    private func remediationPreflight(_ rem: Remediation) -> some View {
        let pf = rem.preflight()
        return VStack(alignment: .leading, spacing: 6) {
            Text(pf.description)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(pf.isReversible ? Color.rvText : Color.rvOver)
            if !pf.warnings.isEmpty {
                ForEach(pf.warnings, id: \.self) { w in
                    Text(w)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.rvWarn)
                }
            }
            HStack(spacing: 6) {
                ActionChip(
                    label: pf.isReversible ? "Proceed" : "Proceed \u{2014} check Trash",
                    kind: pf.isReversible ? .accent : .over,
                    action: {
                        RemediationExecutor.execute(rem)
                        confirmingRemediation = nil
                        findings.removeAll { $0.suggestedRemediation?.title == rem.title }
                    }
                )
                ActionChip(label: "Cancel") {
                    confirmingRemediation = nil
                }
            }
        }
        .padding(8)
        .background(
            (pf.isReversible ? Color.rvAccentGlow : Color.rvOverGlow),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    private func loadFindings() async {
        isLoading = true
        let results = await ProbeRegistry.runAll(context: context, cache: cache)
        isLoading = false
        findings = results
    }

    private func confidenceColor(_ c: Finding.Confidence) -> Color {
        switch c {
        case .info:       return .rvTextFaint
        case .advisory:   return .rvWarn
        case .actionable: return .rvOver
        }
    }

    private func remediationChipKind(_ kind: Remediation.Kind) -> ActionChip.ActionChipKind {
        switch kind {
        case .reveal, .openSettings: return .default
        case .clear:                 return .over
        case .move:                  return .accent
        case .reduceProcesses:       return .default
        }
    }
}
