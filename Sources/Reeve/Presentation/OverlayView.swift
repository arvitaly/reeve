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
        .sheet(item: $pendingAction) { action in
            switch action {
            case .process(let p): ActionSheet(process: p)
            case .group: EmptyView()
            }
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
                    TextField("Search", text: $searchText)
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
            Image(systemName: systemImage).font(.system(size: 10, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(widgetMode == mode ? Color.accentColor : .secondary)
        .help(mode.helpText)
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
                sortHeader("Mem", mode: .memory, width: 60)
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
            if showProcesses || isSearching { processContent } else { appsContent }
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
        let sorted = sortedGroups(apps)
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sorted) { group in
                    groupBlock(group: group)
                }
                if !system.isEmpty {
                    systemSection(system)
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
            ForEach(top) { group in
                groupBlock(group: group)
            }
        }
    }

    // MARK: Pinned

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
                LazyVStack(spacing: 0) {
                    ForEach(pinned) { group in
                        groupBlock(group: group)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Dashboard (sparklines)

    private var dashboardContent: some View {
        let (apps, _) = buildApplicationGroups(snapshot: engine.snapshot)
        let sorted = apps.sorted { $0.totalMemory > $1.totalMemory }
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sorted.prefix(15)) { group in
                    HStack(spacing: 8) {
                        if let icon = group.icon {
                            Image(nsImage: icon).resizable().interpolation(.high)
                                .frame(width: 16, height: 16)
                        } else {
                            Color.clear.frame(width: 16, height: 16)
                        }
                        Text(group.displayName)
                            .font(.caption).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        let history = groupRuleEngine.groupMemHistory[group.displayName] ?? []
                        let cap = memCap(for: group, in: appState.groupRuleSpecs)
                        let severity = group.overallSeverity(cap: cap)
                        Sparkline(data: history, width: 60, height: 16, color: severity.barColor)
                        Text(group.formattedMemory)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(severity.textColor)
                            .frame(width: 60, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Shared row block

    @ViewBuilder
    private func groupBlock(group: ApplicationGroup) -> some View {
        let cap = memCap(for: group, in: appState.groupRuleSpecs)
        let isSelected = selectedGroupID == group.id
        let isExpanded = expandedGroupIDs.contains(group.id)
        let isPinned = pinnedGroupIDs.contains(group.displayName)
        ApplicationGroupRow(
            group: group,
            cap: cap,
            isSelected: isSelected,
            isExpanded: isExpanded,
            onToggle: {
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
        }
        if isSelected {
            InlineActionBar(
                group: group,
                onKill: {
                    selectedGroupID = nil
                    let procs = group.processes
                    Task {
                        for p in procs { try? await Action(target: p, kind: .kill).execute() }
                    }
                },
                onChipAction: { kind in
                    pendingRuleGroup = nil
                    pendingChipGroup = group
                    pendingChipKind = kind
                },
                onAddRule: {
                    pendingChipGroup = nil
                    withAnimation(.easeOut(duration: 0.2)) { pendingRuleGroup = group }
                }
            )
        }
        if isExpanded && widgetMode == .expanded {
            ForEach(group.processes.sorted { $0.residentMemory > $1.residentMemory }) { process in
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
            let count = engine.snapshot.processes.count
            Text("\(count) processes")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if widgetMode == .expanded && !showProcesses && !isSearching {
                Picker("Sort", selection: $sortMode) {
                    ForEach(SortMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 110)
            }
            Spacer()
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
