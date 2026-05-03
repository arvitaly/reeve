import AppKit
import SwiftUI
import ReeveKit

/// Top-N daemon list shown when the macOS System group is expanded.
/// Each row carries a `?` button when DaemonCatalog has knowledge about
/// the process — clicking it expands an inline explanation:
///   - what the daemon does
///   - whether the memory size is normal
///   - an action when there is one (open System Settings, advisory)
///
/// Goal per CLAUDE.md: every screen should support a decision. A daemon
/// the user understands and that's behaving normally is a decision —
/// "leave it alone". A daemon the user can disable is also a decision.
struct DaemonListView: View {
    let group: ApplicationGroup
    @State private var expandedPID: pid_t?

    private var top: [ProcessRecord] {
        Array(group.processes.sorted { $0.residentMemory > $1.residentMemory }.prefix(20))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(top, id: \.pid) { proc in
                row(proc)
            }
            if group.processes.count > 20 {
                Text("+ \(group.processes.count - 20) more")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.rvTextFaint)
                    .padding(.top, 2)
            }
            Text(group.approximateMemory
                 ? "RSS includes shared pages — sizes approximate, ranking reliable."
                 : "phys_footprint via top — refreshed every 15s.")
                .font(.system(size: 9))
                .foregroundStyle(Color.rvTextFaint)
                .padding(.top, 4)
        }
        .padding(10)
        .background(Color.rvInputBg, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func row(_ proc: ProcessRecord) -> some View {
        let entry = DaemonCatalog.entry(for: proc.name)
        let isExpanded = expandedPID == proc.pid

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(proc.name)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.rvTextDim)
                    .lineLimit(1)

                if proc.name.hasPrefix("com.reeve.help") {
                    Text("(Reeve)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.rvAccent.opacity(0.7))
                }

                if let entry {
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.15)) {
                            expandedPID = isExpanded ? nil : proc.pid
                        }
                    }) {
                        Image(systemName: isExpanded ? "info.circle.fill" : "info.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.rvAccent.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help(entry.title + " — " + entry.what)
                }

                Spacer()
                Text(proc.formattedMemory)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.rvTextFaint)
            }

            if isExpanded, let entry {
                infoBlock(entry)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func infoBlock(_ entry: DaemonCatalog.Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.rvText)
            Text(entry.what)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.rvTextDim)
                .fixedSize(horizontal: false, vertical: true)
            Text(entry.normalcy)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.rvTextDim)
                .fixedSize(horizontal: false, vertical: true)
            actionView(for: entry.action)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.rvBgElev.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.rvHairline, lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private func actionView(for action: DaemonCatalog.Action) -> some View {
        switch action {
        case .openSettings(let url, let label):
            Button(action: { NSWorkspace.shared.open(url) }) {
                HStack(spacing: 4) {
                    Image(systemName: "gear")
                        .font(.system(size: 10))
                    Text(label)
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(Color.rvAccent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.rvAccentGlow, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        case .advisory(let text):
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(Color.rvTextFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        case .copyCommand(let command, let hint):
            CopyCommandView(command: command, hint: hint)
                .padding(.top, 2)
        case .immutable:
            Text("System component — leave alone.")
                .font(.system(size: 10))
                .foregroundStyle(Color.rvTextFaint)
                .padding(.top, 2)
        }
    }
}

private struct CopyCommandView: View {
    let command: String
    let hint: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: copy) {
                HStack(spacing: 6) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                    Text(command)
                        .font(.system(size: 10.5, design: .monospaced))
                    Spacer(minLength: 4)
                    Text(copied ? "Copied" : "Copy")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.rvTextFaint)
                }
                .foregroundStyle(copied ? Color.rvOk : Color.rvAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.rvInputBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.rvHairline, lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
            .help("Click to copy this command")

            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(Color.rvTextFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(command, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            copied = false
        }
    }
}
