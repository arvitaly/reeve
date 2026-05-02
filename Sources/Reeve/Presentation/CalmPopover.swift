import SwiftUI
import ReeveKit

// MARK: - Calm popover

struct CalmPopover: View {
    @ObservedObject var engine: MonitoringEngine
    @ObservedObject var groupRuleEngine: GroupRuleEngine
    @ObservedObject var overlay: OverlayController
    @ObservedObject var hotkey: GlobalHotkeyMonitor
    @EnvironmentObject var appState: AppState
    let mainWindow: MainWindowController

    @State private var expandedID: pid_t?
    @State private var filter: FilterMode = .all
    @State private var diagnosticCache = DiagnosticCache()

    enum FilterMode { case all, high, capped }

    var body: some View {
        let (apps, _) = buildApplicationGroups(snapshot: engine.snapshot)
        let specs = appState.groupRuleSpecs
        let visible = filtered(apps, specs: specs)
        let totalMem = apps.reduce(0.0) { $0 + Double($1.totalMemory) }
        let totalCpu = apps.reduce(0.0) { $0 + $1.totalCPU }
        let overCount = apps.filter { $0.overallSeverity(cap: memCap(for: $0, in: specs)) == .over }.count
        let allQuiet = !visible.isEmpty && overCount == 0 &&
            apps.allSatisfy { $0.overallSeverity(cap: memCap(for: $0, in: specs)) == .normal }

        VStack(spacing: 0) {
            header(totalMem: totalMem, totalCpu: totalCpu,
                   appCount: visible.count, overCount: overCount, allQuiet: allQuiet)
            Rectangle().fill(Color.rvHairline).frame(height: 0.5)

            if visible.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { i, group in
                            let cap = memCap(for: group, in: specs)
                            let exp = expandedID == group.id
                            CalmRow(
                                group: group,
                                memHistory: groupRuleEngine.groupMemHistory[group.displayName] ?? [],
                                cpuHistory: groupRuleEngine.groupCpuHistory[group.displayName] ?? [],
                                cap: cap, expanded: exp,
                                snapshot: engine.snapshot,
                                diagnosticCache: diagnosticCache,
                                onToggle: { toggle(group.id) },
                                onSetCap: { gb in setCapRule(for: group, capGB: gb) },
                                onRemoveCap: { removeCapRule(for: group) },
                                onAction: { kind in execute(group, kind) }
                            )
                            if i < visible.count - 1,
                               !exp, expandedID != visible[i + 1].id {
                                Rectangle().fill(Color.rvHairline).frame(height: 0.5)
                                    .padding(.leading, 48)
                            }
                        }
                    }
                }
                .frame(minHeight: 300, maxHeight: 480)
            }

            Rectangle().fill(Color.rvHairline).frame(height: 0.5)
            footer
        }
        .frame(width: 380)
        .onAppear {
            engine.showWindow(id: "menuBar")
            hotkey.tryActivate()
        }
        .onDisappear {
            engine.hideWindow(id: "menuBar")
        }
    }

    // MARK: Header

    private func header(totalMem: Double, totalCpu: Double,
                        appCount: Int, overCount: Int, allQuiet: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Reeve")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.1)
                Text("\(appCount) apps")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.rvTextFaint)
                Spacer()
                if overCount > 0 {
                    HStack(spacing: 5) {
                        SeverityDot(severity: .over, pulse: true)
                        Text("\(overCount) over")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.rvOver)
                } else if allQuiet {
                    HStack(spacing: 5) {
                        SeverityDot(severity: .normal)
                        Text("All quiet")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.rvOk)
                }
            }
            .padding(.bottom, 8)

            PressureBar(snapshot: engine.snapshot)
                .padding(.bottom, 10)

            HStack(spacing: 4) {
                filterChip("All", .all)
                filterChip("Needs attention", .high)
                filterChip("Capped", .capped)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func filterChip(_ label: String, _ mode: FilterMode) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { filter = mode }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(filter == mode ? Color.rvText : Color.rvTextDim)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(
                    filter == mode
                        ? RoundedRectangle(cornerRadius: 6).fill(Color.rvPillHover)
                        : nil
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("\u{2713}")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Color.rvOk)
                .padding(.bottom, 6)
            Text("All quiet")
                .font(.system(size: 14, weight: .semibold))
            Text("Every app is under its cap. Reeve is just watching.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.rvTextFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) { SeverityDot(severity: .normal, size: 5); Text("OK") }
            HStack(spacing: 4) { SeverityDot(severity: .warn, size: 5); Text("Warn") }
            HStack(spacing: 4) { SeverityDot(severity: .over, size: 5); Text("Over") }
            Spacer()
            Button("Window") { mainWindow.show(appState: appState) }
                .buttonStyle(.plain)
                .foregroundStyle(Color.rvTextFaint)
            Divider().frame(height: 14)
            Button("Settings") {
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if #available(macOS 14, *) {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } else {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.rvTextFaint)
            Divider().frame(height: 14)
            Button("Widget") { overlay.toggle() }
                .buttonStyle(.plain)
                .foregroundStyle(overlay.isVisible ? Color.primary : Color.rvTextFaint)
            Divider().frame(height: 14)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(Color.rvTextFaint)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.rvTextFaint)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Logic

    private func filtered(_ apps: [ApplicationGroup], specs: [GroupRuleSpec]) -> [ApplicationGroup] {
        calmFilterApps(apps, specs: specs, filter: filter)
    }

    private func toggle(_ id: pid_t) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedID = expandedID == id ? nil : id
        }
    }

    private func setCapRule(for group: ApplicationGroup, capGB: Double) {
        var specs = appState.groupRuleSpecs
        if let idx = specs.firstIndex(where: {
            $0.appNamePattern.localizedCaseInsensitiveCompare(group.displayName) == .orderedSame
        }) {
            specs[idx].condition = .totalMemoryAboveGB(capGB)
            specs[idx].isEnabled = true
        } else {
            let currentGB = Double(group.totalMemory) / 1_073_741_824
            specs.append(GroupRuleSpec(
                appNamePattern: group.displayName,
                condition: .totalMemoryAboveGB(capGB),
                action: currentGB > 3 ? .reniceDown : .suspend
            ))
        }
        appState.groupRuleSpecs = specs
    }

    private func removeCapRule(for group: ApplicationGroup) {
        appState.groupRuleSpecs.removeAll {
            $0.appNamePattern.localizedCaseInsensitiveCompare(group.displayName) == .orderedSame
        }
    }

    private func execute(_ group: ApplicationGroup, _ kind: Action.Kind) {
        let processes = group.processes
        Task { for p in processes { try? await Action(target: p, kind: kind).execute() } }
        if case .kill = kind { appState.triggerKillFlash() }
    }
}

// MARK: - Calm row

private struct CalmRow: View {
    let group: ApplicationGroup
    let memHistory: [Double]
    let cpuHistory: [Double]
    let cap: UInt64?
    let expanded: Bool
    let snapshot: SystemSnapshot
    let diagnosticCache: DiagnosticCache
    let onToggle: () -> Void
    let onSetCap: (Double) -> Void
    let onRemoveCap: () -> Void
    let onAction: (Action.Kind) -> Void

    @State private var isDragging = false
    @State private var dragCapMB: Double?
    @State private var isHovered = false
    @State private var confirmingQuit = false

    private var memSev: Severity { group.memSeverity(cap: cap) }
    private var cpuSev: Severity { group.cpuSeverity() }
    private var memMB: Double { Double(group.totalMemory) / (1024 * 1024) }
    private var capMB: Double? { cap.map { Double($0) / (1024 * 1024) } }

    private var barMax: Double { calmBarMax(capMB: capMB, memMB: memMB) }

    private var activeCap: Double? { isDragging ? dragCapMB : capMB }

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if expanded { expandedSection }
        }
        .background { expanded ? Color.rvRowExpanded : isHovered ? Color.rvRowHover : Color.clear }
        .overlay(alignment: .leading) { categoryStripe }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    // MARK: Main row

    private var mainRow: some View {
        HStack(spacing: 12) {
            appIcon

            VStack(alignment: .leading, spacing: 3) {
                nameRow
                capBar
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statsColumn
            chevron
        }
        .frame(height: 38)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = group.icon {
            Image(nsImage: icon)
                .resizable().interpolation(.high)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .shadow(color: .black.opacity(0.18), radius: 0.5, y: 0.5)
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(group.category.color)
                .frame(width: 20, height: 20)
                .overlay {
                    Text(String(group.displayName.prefix(1)))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
        }
    }

    private var nameRow: some View {
        HStack(spacing: 7) {
            Text(group.displayName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1).truncationMode(.tail)
            statePill
        }
    }

    @ViewBuilder
    private var statePill: some View {
        if group.isSuspended {
            MetricPill(text: "Suspended", color: .rvTextDim, mono: false)
        } else if group.maxNiceValue >= 10 {
            MetricPill(text: "Low priority", color: .rvWarn, mono: false)
        }
    }

    // MARK: Cap bar — drag to set memory cap

    private var capBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let memPct = CGFloat(min(1, memMB / barMax))
            let capPctVal = activeCap.map { CGFloat(min(1, $0 / barMax)) }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5).fill(Color.rvInputBg)
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(memSev.color)
                    .frame(width: max(0, w * memPct))
                    .opacity(isDragging ? 0.6 : 1)
            }
            .frame(height: 7)
            .overlay {
                if let pct = capPctVal {
                    let x = max(1, min(w - 1, w * pct))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isDragging ? Color.rvAccent : Color.rvTextDim)
                        .frame(width: 2, height: 13)
                        .shadow(color: .black.opacity(0.3), radius: 0.25)
                        .position(x: x, y: 3.5)
                }
            }
            .overlay {
                if isDragging, let val = dragCapMB, let pct = capPctVal {
                    Text("cap \(calmFormatCap(val))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.rvAccent, in: RoundedRectangle(cornerRadius: 4))
                        .fixedSize()
                        .position(x: max(0, min(w, w * pct)), y: -14)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        let pct = max(0.05, min(0.98, drag.location.x / w))
                        dragCapMB = (pct * barMax / 100).rounded() * 100
                    }
                    .onEnded { drag in
                        let pct = max(0.05, min(0.98, drag.location.x / w))
                        let finalMB = (pct * barMax / 100).rounded() * 100
                        onSetCap(finalMB / 1024)
                        isDragging = false
                        dragCapMB = nil
                    }
            )
            .onHover { h in
                if h { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
        }
        .frame(height: 7)
    }

    private var statsColumn: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(formatMem(Double(group.totalMemory)))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(-0.2)
                .foregroundStyle(memSev == .normal ? Color.rvText : memSev.color)
            Text(String(format: "%.1f%%", group.totalCPU))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(cpuSev == .normal ? Color.rvTextFaint : cpuSev.color)
        }
    }

    private var chevron: some View {
        Text("\u{203A}")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.rvTextFaint)
            .frame(width: 14)
            .rotationEffect(expanded ? .degrees(90) : .zero)
            .animation(.easeOut(duration: 0.15), value: expanded)
    }

    @ViewBuilder
    private var categoryStripe: some View {
        if expanded {
            RoundedRectangle(cornerRadius: 2)
                .fill(group.category.color)
                .frame(width: 3)
                .padding(.vertical, 6)
                .opacity(0.9)
        }
    }

    // MARK: Expanded detail

    private var expandedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                CategoryChip(category: group.category)
                let diskR = calmFormatDisk(group.totalDiskRead)
                let diskW = calmFormatDisk(group.totalDiskWrite)
                Text("\(group.processes.count) proc · disk \u{2193}\(diskR) \u{2191}\(diskW)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.rvTextFaint)
            }
            .padding(.bottom, 10)

            HStack(spacing: 12) {
                sparkPanel("Memory", formatMem(Double(group.totalMemory)),
                           memHistory, memSev.color,
                           capLine: capMB,
                           capMax: max(memHistory.max() ?? 1, capMB ?? 0) * 1.1)
                sparkPanel("CPU", String(format: "%.1f%%", group.totalCPU),
                           cpuHistory, cpuSev.color, capMax: 100)
            }
            .padding(.bottom, 12)

            DiagnosticPanel(
                context: ProbeContext(
                    bundleID: group.bundleIdentifier,
                    displayName: group.displayName,
                    processes: group.processes,
                    totalMemory: group.totalMemory,
                    snapshot: snapshot
                ),
                cache: diagnosticCache
            )

            smartSuggestion

            if confirmingQuit {
                quitPreflight
            } else {
                actionRow
            }
        }
        .padding(.init(top: 4, leading: 32, bottom: 10, trailing: 16))
    }

    private func sparkPanel(_ title: String, _ value: String,
                            _ data: [Double], _ color: Color,
                            capLine: Double? = nil, capMax: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5).textCase(.uppercase)
                    .foregroundStyle(Color.rvTextFaint)
                Spacer()
                Text(value)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.rvTextDim)
            }
            if data.count >= 2 {
                Sparkline(data: data, height: 28, color: color,
                          capLine: capLine, capMax: capMax)
            } else {
                Color.clear.frame(height: 28)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.rvInputBg, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var smartSuggestion: some View {
        if cap == nil && memSev != .normal {
            let s = suggestion()
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.rvAccent)
                    .frame(width: 16, height: 16)
                    .overlay {
                        Text("\u{2726}")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                Text("When memory > **\(String(format: "%.2g", s.capGB)) GB**, \(s.label)")
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Apply") { onSetCap(s.capGB) }
                    .buttonStyle(.borderedProminent)
                    .tint(.rvAccent)
                    .controlSize(.small)
            }
            .padding(10)
            .background(Color.rvAccentGlow, in: RoundedRectangle(cornerRadius: 8))
            .padding(.bottom, 10)
        }
    }

    private func suggestion() -> (capGB: Double, label: String) {
        calmSuggestion(memHistory: memHistory, currentMemMB: memMB)
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            ActionChip(label: "Lower", icon: "\u{2193}", action: { onAction(.renice(10)) })
            if group.isSuspended {
                ActionChip(label: "Resume", icon: "\u{25B6}", action: { onAction(.resume) })
            } else {
                ActionChip(label: "Suspend", icon: "\u{275A}\u{275A}", action: { onAction(.suspend) })
            }
            // Quit is irreversible — CLAUDE.md requires preflight
            ActionChip(label: "Quit", icon: "\u{2715}", kind: .over) { confirmingQuit = true }
            if cap != nil {
                ActionChip(label: "Uncap", icon: "\u{25CB}") { onRemoveCap() }
            }
        }
    }

    private var quitPreflight: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SIGKILL \(group.displayName) — \(group.processes.count) processes")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.rvOver)
            Text("Irreversible. Unsaved work will be lost.")
                .font(.system(size: 10.5)).foregroundStyle(Color.rvTextDim)
            HStack(spacing: 8) {
                ActionChip(label: "Kill \(group.processes.count) procs", kind: .over) {
                    onAction(.kill); confirmingQuit = false
                }
                ActionChip(label: "Cancel") { confirmingQuit = false }
            }
        }
        .padding(10)
        .background(Color.rvOverGlow, in: RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 4)
    }
}

// MARK: - File-private formatting

func calmFormatCap(_ mb: Double) -> String {
    if mb >= 1024 {
        let s = String(format: "%.2f", mb / 1024)
            .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
        return s + " GB"
    }
    return "\(Int(mb)) MB"
}

func calmFormatDisk(_ bytesPerSec: UInt64) -> String {
    let mb = Double(bytesPerSec) / (1024 * 1024)
    if mb >= 1 { return String(format: "%.1f", mb) }
    let kb = Double(bytesPerSec) / 1024
    if kb >= 1 { return String(format: "%.0fK", kb) }
    return "0"
}

// MARK: - Extracted pure logic

func calmSuggestion(memHistory: [Double], currentMemMB: Double) -> (capGB: Double, label: String) {
    let peakMB = memHistory.max() ?? currentMemMB
    let peakGB = peakMB / 1024
    let capGB = max(0.25, (peakGB * 0.75 * 4).rounded() / 4)
    return (capGB, peakGB > 3 ? "lower priority" : "suspend")
}

func calmBarMax(capMB: Double?, memMB: Double) -> Double {
    if let c = capMB { return c * 1.25 }
    return max(8000, memMB * 2)
}

func calmFilterApps(
    _ apps: [ApplicationGroup],
    specs: [GroupRuleSpec],
    filter: CalmPopover.FilterMode
) -> [ApplicationGroup] {
    apps.filter { group in
        switch filter {
        case .all:    return true
        case .high:   return group.overallSeverity(cap: memCap(for: group, in: specs)) != .normal
        case .capped: return memCap(for: group, in: specs) != nil
        }
    }
    .sorted { $0.totalMemory > $1.totalMemory }
}
