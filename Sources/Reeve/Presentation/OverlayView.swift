import SwiftUI
import ReeveKit

enum WidgetMode: String {
    case compact, expanded, pinned, dashboard

    var helpText: String {
        switch self {
        case .compact:   return "Compact (top 5)"
        case .expanded:  return "Expanded (full list)"
        case .pinned:    return "Pinned apps"
        case .dashboard: return "Dashboard (sparklines)"
        }
    }
}

/// Desktop widget — application-group view matching the popover layout.
struct OverlayView: View {
    @ObservedObject var engine: MonitoringEngine
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var groupRuleEngine: GroupRuleEngine
    let onClose: () -> Void

    @AppStorage("widgetMode") private var widgetMode: WidgetMode = .expanded
    @AppStorage("pinnedGroupIDsJSON") private var pinnedGroupIDsJSON: String = "[]"

    @State private var sortMode: SortMode = .memory
    @State private var showProcesses: Bool = false
    @State private var searchText: String = ""
    @State private var expandedPIDs: Set<pid_t> = []
    @State private var expandedGroupIDs: Set<pid_t> = []
    @State private var pendingAction: AppAction?
    @State private var selectedGroupID: pid_t?
    @State private var pendingChipGroup: ApplicationGroup?
    @State private var pendingChipKind: Action.Kind = .suspend
    @State private var pendingRuleGroup: ApplicationGroup?
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var seenRuleLogCount = 0

    private var isSearching: Bool { !searchText.isEmpty }

    private var pinnedGroupIDs: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: Data(pinnedGroupIDsJSON.utf8))) ?? []
    }

    private func togglePin(_ name: String) {
        var ids = pinnedGroupIDs
        if ids.contains(name) { ids.remove(name) } else { ids.insert(name) }
        pinnedGroupIDsJSON = (try? String(data: JSONEncoder().encode(ids), encoding: .utf8)) ?? "[]"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.fixedSize(horizontal: false, vertical: true)
            Divider()
            if widgetMode != .dashboard {
                columnHeaders.fixedSize(horizontal: false, vertical: true)
                Divider()
            }
            content
            Divider()
            footer.fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                if let msg = toastMessage {
                    Toast(message: msg)
                        .transition(.opacity)
                }
                if let ruleGroup = pendingRuleGroup {
                    GroupRuleSheet(
                        group: ruleGroup,
                        onSave: { spec in
                            appState.groupRuleSpecs.append(spec)
                            withAnimation(.easeOut(duration: 0.2)) { pendingRuleGroup = nil }
                            showToast("Rule saved")
                        },
                        onCancel: {
                            withAnimation(.easeOut(duration: 0.2)) { pendingRuleGroup = nil }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let chipGroup = pendingChipGroup {
                    ConfirmChip(
                        group: chipGroup,
                        kind: pendingChipKind,
                        onConfirm: {
                            let g = chipGroup, k = pendingChipKind
                            withAnimation(.easeOut(duration: 0.2)) { pendingChipGroup = nil }
                            Task {
                                for p in g.processes { try? await Action(target: p, kind: k).execute() }
                                selectedGroupID = nil
                            }
                        },
                        onCancel: {
                            withAnimation(.easeOut(duration: 0.2)) { pendingChipGroup = nil }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: pendingChipGroup?.id)
        .animation(.easeOut(duration: 0.2), value: pendingRuleGroup?.id)
        .animation(.easeOut(duration: 0.15), value: toastMessage)
        .onAppear { seenRuleLogCount = groupRuleEngine.actionLog.count }
        .onChange(of: groupRuleEngine.actionLog.count) { newCount in
            defer { seenRuleLogCount = newCount }
            guard newCount > seenRuleLogCount, let entry = groupRuleEngine.actionLog.last else { return }
            showToast("Rule: \(entry.actionName) → \(entry.appName)")
        }
        .sheet(item: $pendingAction) { action in
            if case .process(let p) = action { ActionSheet(process: p) }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("Reeve").font(.headline)
                Spacer()
                modeButton(.compact, systemImage: "square.grid.2x2")
                modeButton(.expanded, systemImage: "list.bullet")
                modeButton(.pinned, systemImage: "pin")
                modeButton(.dashboard, systemImage: "chart.bar")
                Spacer()
                Text(engine.snapshot.sampledAt, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            PressureBar(snapshot: engine.snapshot)
            if widgetMode == .expanded {
                HStack(spacing: 6) {
                    TextField(showProcesses ? "Search processes" : "Search apps", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Button {
                        showProcesses.toggle()
                    } label: {
                        Label(showProcesses ? "Processes" : "Apps",
                              systemImage: showProcesses ? "list.bullet.indent" : "app.badge")
                            .font(.caption)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(showProcesses ? .secondary : Color.accentColor)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func modeButton(_ mode: WidgetMode, systemImage: String) -> some View {
        Button { widgetMode = mode } label: {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(widgetMode == mode ? Color.accentColor.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .foregroundStyle(widgetMode == mode ? Color.accentColor : .secondary)
        .help(mode.helpText)
        .animation(.easeOut(duration: 0.12), value: widgetMode)
    }

    // MARK: Column headers

    private var columnHeaders: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: showProcesses ? 18 : 40)
            Text(showProcesses ? "Process" : "Application")
                .frame(maxWidth: .infinity, alignment: .leading)
            if showProcesses {
                Text("Mem").frame(width: 68, alignment: .trailing)
                Text("CPU").frame(width: 44, alignment: .trailing)
            } else {
                Color.clear.frame(width: 18)
                sortHeader("CPU", mode: .cpu, width: 44)
                sortHeader("RSS", mode: .rss, width: 52)
                sortHeader("Foot", mode: .memory, width: 60)
                Color.clear.frame(width: 90)
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.04))
    }

    private func sortHeader(_ label: String, mode: SortMode, width: CGFloat) -> some View {
        Button {
            sortMode = (sortMode == mode) ? .memory : mode
        } label: {
            HStack(spacing: 2) {
                Text(label)
                if sortMode == mode {
                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                }
            }
            .frame(width: width, alignment: .trailing)
            .foregroundStyle(sortMode == mode ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch widgetMode {
        case .expanded:
            if showProcesses { processContent } else { appsContent }
        case .compact:
            compactContent
        case .pinned:
            pinnedContent
        case .dashboard:
            dashboardContent
        }
    }

    // MARK: Expanded (app groups, full list)

    private var appsContent: some View {
        let (apps, system) = buildApplicationGroups(snapshot: engine.snapshot)
        var sorted = sortedGroups(apps)
        let query = searchText
        if !query.isEmpty {
            sorted = sorted.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
        }
        return ScrollView {
            LazyVStack(spacing: 0) {
                if sorted.isEmpty && !query.isEmpty {
                    Text("No apps matching \u{201C}\(query)\u{201D}")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                } else if sorted.isEmpty {
                    Text("Sampling…")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                } else {
                    ForEach(sorted) { group in
                        groupBlock(group: group)
                    }
                    if !system.isEmpty && query.isEmpty {
                        systemSection(system)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Compact (top 5)

    private var compactContent: some View {
        let (apps, _) = buildApplicationGroups(snapshot: engine.snapshot)
        let top = Array(apps.sorted { $0.totalMemory > $1.totalMemory }.prefix(5))
        return VStack(spacing: 0) {
            if top.isEmpty {
                Text("Sampling…")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
            } else {
                ForEach(top) { group in
                    groupBlock(group: group)
                }
            }
        }
    }

    // MARK: Pinned (card layout)

    @ViewBuilder
    private var pinnedContent: some View {
        let (apps, _) = buildApplicationGroups(snapshot: engine.snapshot)
        let pinned = apps.filter { pinnedGroupIDs.contains($0.displayName) }
        if pinned.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "pin").font(.title3).foregroundStyle(.tertiary)
                Text("No pinned apps").font(.caption).foregroundStyle(.secondary)
                Text("Right-click an app to pin it").font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(pinned) { group in
                        pinnedCard(group: group)
                    }
                }
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private func pinnedCard(group: ApplicationGroup) -> some View {
        let cap = memCap(for: group, in: appState.groupRuleSpecs)
        let capGB = cap.map { Double($0) / 1_073_741_824 }
        let severity = group.overallSeverity(cap: cap)
        let memGB = Double(group.totalMemory) / 1_073_741_824

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let icon = group.icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                        .frame(width: 22, height: 22)
                        .opacity(group.isSuspended ? 0.4 : 1.0)
                } else {
                    Color.clear.frame(width: 22, height: 22)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(group.displayName).font(.caption.weight(.medium)).lineLimit(1)
                        if group.isSuspended {
                            Text("paused")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        } else if group.maxNiceValue > 0 {
                            Text("nice +\(group.maxNiceValue)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.rvAccent)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.rvAccent.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    let metaMem = capGB.map { String(format: "%.1f GB / %.1f GB cap", memGB, $0) }
                               ?? String(format: "%.1f GB", memGB)
                    Text("\(metaMem) · \(String(format: "%.0f", group.totalCPU))% CPU")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                SeverityDot(severity: severity)
            }
            if let _ = cap {
                MiniBar(value: Double(group.totalMemory), cap: cap.map(Double.init),
                        height: 4, severity: severity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.rvRowExpanded)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .contextMenu {
            Button(group.displayName) {}.disabled(true)
            Divider()
            Button("Unpin from Widget") { togglePin(group.displayName) }
            Button("Action…") {
                widgetMode = .expanded
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    selectedGroupID = group.id
                }
            }
            Button("Open in Activity Monitor") {
                NSWorkspace.shared.open(
                    URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
        }
    }

    // MARK: Dashboard (sparklines + stat blocks)

    private var dashboardContent: some View {
        let snap = engine.snapshot
        let (apps, _) = buildApplicationGroups(snapshot: snap)
        let sorted = apps.sorted { $0.totalMemory > $1.totalMemory }
        let physGB = Double(snap.physicalMemory) / 1_073_741_824
        let usedGB = snap.usedMemory.map { Double($0) / 1_073_741_824 }
        let memPct = usedGB.map { $0 / physGB * 100 }
        let memSev: Severity = memPct.map { $0 >= 90 ? .over : $0 >= 70 ? .warn : .normal } ?? .normal

        return ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    dashStatBlock(
                        eyebrow: "MEMORY · \(GroupRuleEngine.historyCapacity)S",
                        value: usedGB.map { String(format: "%.1f GB", $0) } ?? "—",
                        sub: usedGB.map { String(format: "of %.0f GB · %.0f%%", physGB, $0 / physGB * 100) } ?? "of \(Int(physGB)) GB",
                        history: groupRuleEngine.systemMemHistory,
                        color: memSev.barColor
                    )
                    dashStatBlock(
                        eyebrow: "CPU",
                        value: String(format: "%.0f%%", snap.totalCPU),
                        sub: "\(snap.processes.count) processes",
                        history: groupRuleEngine.systemCPUHistory,
                        color: snap.totalCPU >= 80 ? Color.rvDanger : snap.totalCPU >= 50 ? Color.rvAccent : Color.rvBarNormal
                    )
                }
                HStack(spacing: 8) {
                    dashMiniCard(title: "Top Consumer") {
                        if let top = sorted.first {
                            HStack(spacing: 6) {
                                if let icon = top.icon {
                                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(top.displayName).font(.caption).lineLimit(1)
                                    Text(String(format: "%@ · %.0f%%", top.formattedMemory, top.totalCPU))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text("No data").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    dashMiniCard(title: "Active Rules") {
                        let enabled = appState.groupRuleSpecs.filter { $0.isEnabled }.count
                        let firings = appState.groupRuleEngine.actionLog.count
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(enabled) rule\(enabled == 1 ? "" : "s") active")
                                .font(.caption)
                            Text("\(firings) firing\(firings == 1 ? "" : "s") total")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
                LazyVStack(spacing: 0) {
                    ForEach(sorted.prefix(10)) { group in
                        let history = groupRuleEngine.groupMemHistory[group.displayName] ?? []
                        let cap = memCap(for: group, in: appState.groupRuleSpecs)
                        let sev = group.overallSeverity(cap: cap)
                        HStack(spacing: 8) {
                            if let icon = group.icon {
                                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 14, height: 14)
                            } else {
                                Color.clear.frame(width: 14, height: 14)
                            }
                            Text(group.displayName).font(.caption).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Sparkline(data: history, width: 50, height: 14, color: sev.barColor)
                            Text(group.formattedMemory)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(sev.textColor)
                                .frame(width: 52, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                    }
                }
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private func dashStatBlock(eyebrow: String, value: String, sub: String,
                                history: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(value)
                .font(.system(size: 20, weight: .medium).monospacedDigit())
                .foregroundStyle(color)
            Text(sub)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Sparkline(data: history, height: 24, color: color.opacity(0.8))
        }
        .padding(10)
        .background(Color.rvRowExpanded)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder
    private func dashMiniCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rvRowExpanded)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    // MARK: Shared row block

    @ViewBuilder
    private func groupBlock(group: ApplicationGroup) -> some View {
        let cap = memCap(for: group, in: appState.groupRuleSpecs)
        let isSelected = selectedGroupID == group.id
        let canExpand = widgetMode == .expanded
        let isExpanded = canExpand && expandedGroupIDs.contains(group.id)
        let isPinned = pinnedGroupIDs.contains(group.displayName)
        ApplicationGroupRow(
            group: group,
            cap: cap,
            isSelected: isSelected,
            isExpanded: isExpanded,
            onToggle: {
                guard canExpand else { return }
                if expandedGroupIDs.contains(group.id) { expandedGroupIDs.remove(group.id) }
                else { expandedGroupIDs.insert(group.id) }
            },
            onSelect: {
                selectedGroupID = isSelected ? nil : group.id
                if isSelected { pendingChipGroup = nil }
            }
        )
        .contextMenu {
            let currentGB = Double(group.totalMemory) / 1_073_741_824
            let suggestedCap = GroupRuleSheet.suggestedCap(currentGB: currentGB)
            Button(group.displayName) {}.disabled(true)
            Divider()
            Button("Cap at \(String(format: "%.1f", suggestedCap)) GB → lower priority") {
                appState.groupRuleSpecs.append(GroupRuleSpec(
                    appNamePattern: group.displayName,
                    condition: .totalMemoryAboveGB(suggestedCap),
                    action: .reniceDown,
                    cooldownSeconds: 60,
                    isEnabled: true
                ))
                selectedGroupID = nil
                showToast("Rule saved")
            }
            Button("Custom rule…") {
                selectedGroupID = nil
                pendingChipGroup = nil
                withAnimation(.easeOut(duration: 0.2)) { pendingRuleGroup = group }
            }
            Divider()
            Button(isPinned ? "Unpin from Widget" : "Pin to Widget") { togglePin(group.displayName) }
            Button("Action…") { selectedGroupID = isSelected ? nil : group.id }
            Button("Open in Activity Monitor") {
                NSWorkspace.shared.open(
                    URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
        }
        if isSelected {
            InlineActionBar(
                group: group,
                onKill: {
                    selectedGroupID = nil
                    appState.triggerKillFlash()
                    let procs = group.processes
                    Task {
                        for p in procs { try? await Action(target: p, kind: .kill).execute() }
                    }
                },
                onChipAction: { kind in
                    if case .resume = kind {
                        let procs = group.processes
                        Task {
                            for p in procs { try? await Action(target: p, kind: .resume).execute() }
                            selectedGroupID = nil
                        }
                    } else {
                        pendingRuleGroup = nil
                        pendingChipGroup = group
                        pendingChipKind = kind
                    }
                },
                onAddRule: {
                    pendingChipGroup = nil
                    withAnimation(.easeOut(duration: 0.2)) { pendingRuleGroup = group }
                }
            )
        }
        if isExpanded && widgetMode == .expanded {
            ForEach(group.processes.sorted { ($0.physFootprint ?? $0.residentMemory) > ($1.physFootprint ?? $1.residentMemory) }) { process in
                ProcessRow(process: process, sortMode: sortMode) {
                    pendingAction = .process(process)
                }
                .padding(.leading, 22)
            }
        }
    }

    // MARK: Helpers

    private func sortedGroups(_ groups: [ApplicationGroup]) -> [ApplicationGroup] {
        switch sortMode {
        case .memory: return groups.sorted { $0.totalMemory > $1.totalMemory }
        case .rss:    return groups.sorted { $0.totalRSS > $1.totalRSS }
        case .cpu:    return groups.sorted { $0.totalCPU > $1.totalCPU }
        case .disk:   return groups.sorted { $0.totalDiskWrite > $1.totalDiskWrite }
        }
    }

    private func showToast(_ msg: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { toastMessage = msg }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) { toastMessage = nil }
        }
    }

    private func systemSection(_ procs: [ProcessRecord]) -> some View {
        VStack(spacing: 0) {
            Divider().padding(.vertical, 2)
            HStack {
                Text("System").font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
                Spacer()
                Text("\(procs.count) processes").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            ForEach(procs.prefix(10)) { proc in
                ProcessRow(process: proc, sortMode: .memory) {
                    pendingAction = .process(proc)
                }
            }
        }
    }

    // MARK: Process view (expanded mode only)

    private var processContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isSearching {
                    let matches = engine.snapshot.processes
                        .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
                        .sorted { $0.residentMemory > $1.residentMemory }
                    ForEach(matches) { process in
                        ProcessRow(process: process, sortMode: sortMode) {
                            pendingAction = .process(process)
                        }
                    }
                } else {
                    treeRows
                }
            }
        }
    }

    @ViewBuilder
    private var treeRows: some View {
        let roots = engine.snapshot.buildTree()
        let rows = Array(visibleNodes(from: roots).prefix(200))
        ForEach(rows, id: \.id) { node in
            TreeProcessRow(
                node: node,
                isExpanded: expandedPIDs.contains(node.record.pid),
                onTap: {
                    if node.children.isEmpty {
                        pendingAction = .process(node.record)
                    } else {
                        let pid = node.record.pid
                        if expandedPIDs.contains(pid) { collapseSubtree(node) }
                        else { expandedPIDs.insert(pid) }
                    }
                },
                onAction: { pendingAction = .process(node.record) }
            )
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            let procs = engine.snapshot.processes.count
            let (apps, _) = buildApplicationGroups(snapshot: engine.snapshot)
            Text("\(apps.count) apps · \(procs) procs")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if widgetMode == .expanded && !showProcesses {
                Picker("Sort", selection: $sortMode) {
                    ForEach(SortMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            Button {
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if #available(macOS 14, *) {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } else {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: Tree helpers

    private func visibleNodes(from nodes: [ProcessTreeNode]) -> [ProcessTreeNode] {
        var result: [ProcessTreeNode] = []
        for node in nodes {
            result.append(node)
            if expandedPIDs.contains(node.record.pid) {
                result += visibleNodes(from: node.children)
            }
        }
        return result
    }

    private func collapseSubtree(_ node: ProcessTreeNode) {
        expandedPIDs.remove(node.record.pid)
        for child in node.children { collapseSubtree(child) }
    }
}
