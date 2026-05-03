import SwiftUI

/// Surface B from the design — inline expansion shown below the pressure bar
/// when the user taps the summary line. Lists every memory category with
/// plain-English meaning, exact bytes, percent of physical RAM, and the
/// API the number came from.
///
/// Intentionally a "reading surface" — only the Apps row is interactive
/// (closes the panel). Honest absence is encoded with the diagonal-stripe
/// swatch on the unmeasurable Other row.
struct MemoryDetailPanel: View {
    let model: MemoryModel
    let onAppsRowTap: () -> Void
    let onDismiss: () -> Void
    let onOpenHelp: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

            sectionHeader("USED — what's holding memory right now")
            VStack(spacing: 0) {
                ForEach(model.usedSegments.filter { $0.bytes > 0 }
                    .sorted { $0.bytes > $1.bytes }) { seg in
                    row(seg, isApps: seg.id == "apps")
                    if seg.id == model.usedSegments.last?.id { EmptyView() }
                }
            }
            .padding(.bottom, 6)

            sectionHeader("AVAILABLE — what the system can hand out")
            VStack(spacing: 0) {
                ForEach(model.availableSegments.filter { $0.bytes > 0 }
                    .sorted { $0.bytes > $1.bytes }) { seg in
                    row(seg, isApps: false)
                }
            }
            .padding(.bottom, 8)

            footerLink
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.rvBgElev)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.rvHairline, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Title row

    private var titleRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("MEMORY")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.rvTextFaint)
                Spacer()
                Button(action: onDismiss) {
                    HStack(spacing: 3) {
                        Text("Close")
                            .font(.system(size: 10, weight: .medium))
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Color.rvTextFaint)
                }
                .buttonStyle(.plain)
            }
            Text(headlineText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.rvTextDim)
            if model.helperActive {
                Text("Detailed attribution active · Helper running as root")
                    .font(RVFont.mono(size: 9.5))
                    .foregroundStyle(Color.rvTextFaint)
                    .padding(.top, 1)
            }
        }
    }

    private var headlineText: String {
        let used = formatBytesPlain(model.usedBytes)
        let phys = formatBytesPlain(model.physical)
        let avail = formatBytesPlain(model.availableBytes)
        return "\(used) of \(phys) physical RAM in use · \(avail) available"
    }

    // MARK: - Section header

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(Color.rvTextFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    // MARK: - Row

    private func row(_ seg: MemorySegment, isApps: Bool) -> some View {
        let pct = seg.percentOfPhysical
        return RowContainer(isInteractive: isApps, onTap: isApps ? onAppsRowTap : nil) {
            HStack(alignment: .top, spacing: 8) {
                if seg.isUnmeasurable {
                    UnmeasurableDot(size: 9)
                        .padding(.top, 4)
                } else {
                    Circle()
                        .fill(seg.color)
                        .frame(width: 9, height: 9)
                        .padding(.top, 4)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(seg.label)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(seg.isUnmeasurable ? Color.rvTextDim : Color.rvText)
                        if seg.isUnmeasurable {
                            Text("?")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.rvTextFaint)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 0.5)
                                .background(Color.rvInputBg, in: RoundedRectangle(cornerRadius: 3))
                        }
                        Spacer()
                        Text(formatBytesPlain(seg.bytes))
                            .font(RVFont.mono(size: 12, weight: .medium))
                            .foregroundStyle(seg.isUnmeasurable ? Color.rvTextDim : Color.rvText)
                        Text("\(pct)%")
                            .font(RVFont.mono(size: 11))
                            .foregroundStyle(Color.rvTextFaint)
                            .frame(width: 36, alignment: .trailing)
                    }
                    Text(seg.description)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.rvTextDim)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(seg.source)
                        .font(RVFont.mono(size: 9.5))
                        .foregroundStyle(Color.rvTextFaint)
                        .lineLimit(2)

                    if seg.isUnmeasurable && seg.bytes > 0 && !model.helperActive {
                        otherCTA
                            .padding(.top, 6)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private var otherCTA: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(Color.rvTextFaint)
            Text("Enable detailed attribution to split this into kernel zones, shared buffers and per-process anonymous regions.")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.rvTextDim)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: onOpenSettings) {
                Text("Setup")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.rvAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.rvAccentGlow, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Coming in v0.3.0 — opt-in privileged helper for full attribution")
            .disabled(true)
            .opacity(0.7)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.rvInputBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.rvHairline, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Footer

    private var footerLink: some View {
        Button(action: onOpenHelp) {
            HStack(spacing: 4) {
                Text("How memory accounting works")
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Color.rvAccent)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formatBytesPlain(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}

private struct RowContainer<Content: View>: View {
    let isInteractive: Bool
    let onTap: (() -> Void)?
    @ViewBuilder var content: Content
    @State private var hover = false

    var body: some View {
        content
            .background(
                (hover && isInteractive) ? Color.rvRowHover : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture {
                if isInteractive { onTap?() }
            }
    }
}
