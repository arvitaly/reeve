import SwiftUI
import ReeveKit

/// The "Memory" tab of the main window. Replaces the popover's inline
/// detail accordion (popover was too narrow for honest detail) and
/// folds the helper-attribution toggle into the same surface.
///
/// Layout, top to bottom:
/// 1. Title block — what you're looking at, in plain English
/// 2. Large stacked bar (24pt tall) + readable legend chips
/// 3. USED breakdown rows — every category with bytes / percent /
///    plain-English meaning / source API
/// 4. AVAILABLE breakdown rows
/// 5. "How memory accounting works" link → opens the existing help sheet
/// 6. Helper installation card at the bottom (the old MemoryAttributionTab)
struct MemoryTab: View {
    @ObservedObject var engine: MonitoringEngine

    @State private var helpVisible = false
    @State private var helperState: HelperLifecycle.State = HelperLifecycle.shared.state
    @State private var lastHelperError: String?
    @State private var showInstallSheet = false
    @State private var showUninstallSheet = false
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                titleBlock
                bigBarBlock
                breakdown
                helpLink
                Rectangle().fill(Color.rvHairline).frame(height: 0.5)
                helperCard
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { helperState = HelperLifecycle.shared.state }
        .sheet(isPresented: $helpVisible) {
            MemoryHelpSheet(onClose: { helpVisible = false })
        }
        .sheet(isPresented: $showInstallSheet) { installSheet }
        .sheet(isPresented: $showUninstallSheet) { uninstallSheet }
    }

    private var model: MemoryModel { MemoryModel(snapshot: engine.snapshot) }

    // MARK: - Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Memory")
                .font(.system(size: 22, weight: .semibold))
            Text(headlineText)
                .font(.system(size: 13))
                .foregroundStyle(Color.rvTextDim)
        }
    }

    private var headlineText: String {
        let used = ByteCountFormatter.string(fromByteCount: Int64(model.usedBytes), countStyle: .memory)
        let phys = ByteCountFormatter.string(fromByteCount: Int64(model.physical), countStyle: .memory)
        let avail = ByteCountFormatter.string(fromByteCount: Int64(model.availableBytes), countStyle: .memory)
        var line = "\(used) of \(phys) physical RAM in use · \(avail) available"
        if model.helperActive {
            line += " · Detailed attribution active"
        }
        return line
    }

    // MARK: - Big bar

    private var bigBarBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            BigBreakdownBar(model: model)
            BigLegend(model: model)
        }
    }

    // MARK: - Breakdown rows

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader("USED — what's holding memory right now")
            VStack(spacing: 10) {
                ForEach(model.usedSegments.filter { $0.bytes > 0 }
                    .sorted { $0.bytes > $1.bytes }) { seg in
                    DetailRow(seg: seg, totalPhys: model.physical, helperActive: model.helperActive,
                              onSetup: { showInstallSheet = true })
                }
            }
            sectionHeader("AVAILABLE — what the system can hand out")
            VStack(spacing: 10) {
                ForEach(model.availableSegments.filter { $0.bytes > 0 }
                    .sorted { $0.bytes > $1.bytes }) { seg in
                    DetailRow(seg: seg, totalPhys: model.physical, helperActive: model.helperActive,
                              onSetup: { showInstallSheet = true })
                }
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Color.rvTextFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var helpLink: some View {
        Button(action: { helpVisible = true }) {
            HStack(spacing: 4) {
                Text("How memory accounting works")
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Color.rvAccent)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helper card (was MemoryAttributionTab)

    private var helperCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DETAILED ATTRIBUTION")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.rvTextFaint)

            VStack(alignment: .leading, spacing: 14) {
                Text(headlineForHelper)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.rvText)

                Text(helperBody)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.rvTextDim)
                    .fixedSize(horizontal: false, vertical: true)

                helperToggleRow

                helperBullets

                Text("Reeve will not write, mutate or escalate beyond reading memory accounting.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.rvTextFaint)
                    .padding(.top, 2)

                if let err = lastHelperError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.rvOver)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.rvBgElev)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.rvHairline, lineWidth: 0.5)
                    )
            )
        }
    }

    private var headlineForHelper: String {
        switch helperState {
        case .enabled:           return "Running as root"
        case .requiresApproval:  return "Awaiting approval in System Settings"
        case .notRegistered:     return "Off"
        case .notFound:          return "Not found — reinstall Reeve"
        case .unknown:           return "Unknown"
        case .unsupported:       return "Requires macOS 13 or later"
        }
    }

    private var helperBody: String {
        switch helperState {
        case .enabled:
            return "The helper is loaded and providing kernel zone totals plus per-process VM region maps for root-owned processes. Reeve still runs as a single unprivileged binary; the helper is a separate Mach-O signed by us."
        case .requiresApproval:
            return "macOS opened System Settings → Login Items. Find the “Reeve Helper” entry and turn it on. Reeve is waiting — recheck below or click Open Settings."
        default:
            return "Reeve runs as a single unprivileged binary by default. Some memory cannot be attributed without root — we mark it as ▥ Other (unmeasured) and tell you what's likely inside.\n\nThis is the default and stays the default."
        }
    }

    private var helperToggleRow: some View {
        HStack(spacing: 12) {
            Toggle(isOn: helperBinding) {
                Text("Install privileged helper")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.rvText)
            }
            .toggleStyle(.switch)
            .disabled(helperState == .unsupported || working)

            Spacer()
            statusBadge
            if helperState == .requiresApproval {
                Button("Open Settings") {
                    HelperLifecycle.shared.openLoginItemsSettings()
                }
                .buttonStyle(.bordered)
            }
            Button("Recheck") { helperState = HelperLifecycle.shared.state }
                .buttonStyle(.bordered)
        }
    }

    private var helperBinding: Binding<Bool> {
        Binding(
            get: { helperState == .enabled || helperState == .requiresApproval },
            set: { newValue in
                if newValue { showInstallSheet = true }
                else { showUninstallSheet = true }
            }
        )
    }

    private var statusBadge: some View {
        let (text, color): (String, Color)
        switch helperState {
        case .enabled:          (text, color) = ("Running",          Color.rvAccent.opacity(0.85))
        case .requiresApproval: (text, color) = ("Pending approval",  Color.rvWarn)
        case .notRegistered:    (text, color) = ("Off",               Color.rvTextFaint)
        case .notFound:         (text, color) = ("Not found",         Color.rvOver)
        case .unknown:          (text, color) = ("Unknown",           Color.rvTextFaint)
        case .unsupported:      (text, color) = ("Unsupported",       Color.rvTextFaint)
        }
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(color)
        }
    }

    private var helperBullets: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach([
                "installs a helper LaunchDaemon (com.reeve.helper) as root",
                "grants Reeve read-only access to mach_zone_info and per-process VM regions",
                "expands Reeve past its single-binary scope (Phase 1 is read-only — no kill, no signal)",
                "can be uninstalled at any time, no residue"
            ], id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Text("·")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.rvTextFaint)
                    Text(line)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.rvTextDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Sheets

    private var installSheet: some View {
        ConfirmHelperSheet(
            title: "Install privileged helper?",
            message: "macOS will ask you to authorize a background item from Reeve. The helper runs as root and exposes a Mach service used only by Reeve. You can uninstall it any time from this tab.",
            warning: "Reeve will require an admin password.",
            confirmTitle: "Install",
            kind: .warn,
            onCancel: { showInstallSheet = false },
            onConfirm: {
                showInstallSheet = false
                install()
            }
        )
    }

    private var uninstallSheet: some View {
        ConfirmHelperSheet(
            title: "Uninstall helper?",
            message: "Reeve will go back to its default unprivileged behaviour. The detail panel’s “Other (unmeasured)” bucket will reappear.",
            warning: nil,
            confirmTitle: "Uninstall",
            kind: .neutral,
            onCancel: { showUninstallSheet = false },
            onConfirm: {
                showUninstallSheet = false
                uninstall()
            }
        )
    }

    // MARK: - Actions

    private func install() {
        working = true
        lastHelperError = nil
        Task {
            do {
                let new = try HelperLifecycle.shared.register()
                await MainActor.run { helperState = new; working = false }
            } catch {
                await MainActor.run {
                    lastHelperError = "Install failed: \(error.localizedDescription)"
                    helperState = HelperLifecycle.shared.state
                    working = false
                }
            }
        }
    }

    private func uninstall() {
        working = true
        lastHelperError = nil
        Task {
            do {
                let new = try await HelperLifecycle.shared.unregister()
                await MainActor.run { helperState = new; working = false }
            } catch {
                await MainActor.run {
                    lastHelperError = "Uninstall failed: \(error.localizedDescription)"
                    helperState = HelperLifecycle.shared.state
                    working = false
                }
            }
        }
    }
}

// MARK: - Bigger bar variant

private struct BigBreakdownBar: View {
    let model: MemoryModel
    private let height: CGFloat = 22

    var body: some View {
        let segs = orderedSegments
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(segs) { seg in
                    segmentView(seg, width: max(0, geo.size.width * seg.fraction))
                }
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.rvBarTrack))
            .overlay(
                RoundedRectangle(cornerRadius: 5).stroke(Color.rvHairline, lineWidth: 0.5)
            )
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.45), value: model.usedBytes)
    }

    private var orderedSegments: [MemorySegment] {
        let used = model.usedSegments.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
        let avail = model.availableSegments.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
        return used + avail
    }

    @ViewBuilder
    private func segmentView(_ seg: MemorySegment, width: CGFloat) -> some View {
        if seg.isUnmeasurable {
            ZStack {
                Rectangle().fill(seg.color)
                UnmeasurableStripes(spacing: 4, lineWidth: 1, opacity: 0.6)
            }
            .frame(width: width)
        } else {
            Rectangle().fill(seg.color).frame(width: width)
        }
    }
}

private struct BigLegend: View {
    let model: MemoryModel

    var body: some View {
        let segs = (model.usedSegments + model.availableSegments).filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
        WrapHStack(spacing: 14, lineSpacing: 6) {
            ForEach(segs) { seg in
                HStack(spacing: 5) {
                    if seg.isUnmeasurable {
                        UnmeasurableDot(size: 9)
                    } else {
                        Circle().fill(seg.color).frame(width: 9, height: 9)
                    }
                    Text(seg.label)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.rvTextDim)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(seg.bytes), countStyle: .memory))
                        .font(RVFont.mono(size: 11.5))
                        .foregroundStyle(Color.rvText)
                }
            }
        }
    }
}

// MARK: - Detail row

private struct DetailRow: View {
    let seg: MemorySegment
    let totalPhys: UInt64
    let helperActive: Bool
    let onSetup: () -> Void

    var body: some View {
        let pct = seg.percentOfPhysical
        HStack(alignment: .top, spacing: 12) {
            if seg.isUnmeasurable {
                UnmeasurableDot(size: 11)
                    .padding(.top, 5)
            } else {
                Circle().fill(seg.color).frame(width: 11, height: 11)
                    .padding(.top, 5)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(seg.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(seg.isUnmeasurable ? Color.rvTextDim : Color.rvText)
                    if seg.isUnmeasurable {
                        Text("?")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.rvTextFaint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.rvInputBg, in: RoundedRectangle(cornerRadius: 3))
                    }
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(seg.bytes), countStyle: .memory))
                        .font(RVFont.mono(size: 13, weight: .medium))
                        .foregroundStyle(seg.isUnmeasurable ? Color.rvTextDim : Color.rvText)
                    Text("\(pct)%")
                        .font(RVFont.mono(size: 12))
                        .foregroundStyle(Color.rvTextFaint)
                        .frame(width: 42, alignment: .trailing)
                }
                Text(seg.description)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.rvTextDim)
                    .fixedSize(horizontal: false, vertical: true)
                Text(seg.source)
                    .font(RVFont.mono(size: 10))
                    .foregroundStyle(Color.rvTextFaint)
                    .lineLimit(2)
                if seg.isUnmeasurable && seg.bytes > 0 && !helperActive {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.rvTextFaint)
                        Text("Enable detailed attribution to split this into kernel zones, shared buffers and per-process anonymous regions.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.rvTextDim)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button("Setup", action: onSetup)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.rvInputBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.rvHairline, lineWidth: 0.5)
                            )
                    )
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Confirm sheet

private struct ConfirmHelperSheet: View {
    enum Kind { case neutral, warn, danger }
    let title: String
    let message: String
    let warning: String?
    let confirmTitle: String
    let kind: Kind
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(message).font(.system(size: 12)).foregroundStyle(Color.rvTextDim)
                .fixedSize(horizontal: false, vertical: true)
            if let warning {
                Text(warning).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.rvWarn)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(kind == .warn ? Color.rvWarn : kind == .danger ? Color.rvOver : Color.rvAccent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

// MARK: - Wrap layout for the legend

private struct WrapHStack<Content: View>: View {
    let spacing: CGFloat
    let lineSpacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        WrapLayout(spacing: spacing, lineSpacing: lineSpacing) { content }
    }
}

private struct WrapLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        guard let last = rows.last else { return .zero }
        return CGSize(width: proposal.width ?? 0, height: last.maxY)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for r in rows {
            subviews[r.index].place(at: CGPoint(x: bounds.minX + r.x, y: bounds.minY + r.y),
                                    proposal: .unspecified)
        }
    }

    private struct Pos { let index: Int; let x: CGFloat; let y: CGFloat; let maxY: CGFloat }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Pos] {
        let maxW = proposal.width ?? .infinity
        var out: [Pos] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for (i, sub) in subviews.enumerated() {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 {
                y += rowH + lineSpacing
                x = 0
                rowH = 0
            }
            out.append(Pos(index: i, x: x, y: y, maxY: y + s.height))
            rowH = max(rowH, s.height)
            x += s.width + spacing
        }
        return out
    }
}
