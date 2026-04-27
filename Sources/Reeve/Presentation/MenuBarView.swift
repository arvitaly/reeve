import SwiftUI
import ReeveKit

struct MenuBarView: View {
    @ObservedObject var engine: MonitoringEngine
    @ObservedObject var overlay: OverlayController
    @ObservedObject var hotkey: GlobalHotkeyMonitor
    @EnvironmentObject var appState: AppState
    let mainWindow: MainWindowController

    @State private var pendingAction: AppAction?
    @State private var searchText: String = ""
    @State private var showProcesses: Bool = false
    @State private var expandedPIDs: Set<pid_t> = []

    private var isSearching: Bool { !searchText.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.fixedSize(horizontal: false, vertical: true)
            Divider()
            if showProcesses {
                columnHeaders.fixedSize(horizontal: false, vertical: true)
                Divider()
                processContent
            } else {
                AppsListView(engine: engine, searchText: searchText, maxHeight: 500)
            }
            Divider()
            footer.fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 460)
        .onAppear {
            engine.showWindow(id: "menuBar")
            hotkey.tryActivate()
        }
        .onDisappear {
            engine.hideWindow(id: "menuBar")
            searchText = ""
        }
        .sheet(item: $pendingAction) { action in
            if case .process(let p) = action { ActionSheet(process: p) }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Reeve").font(.headline)
                Spacer()
                Button("Open Reeve") { mainWindow.show(appState: appState) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text(engine.snapshot.sampledAt, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            PressureBar(snapshot: engine.snapshot)
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
                .help(showProcesses ? "Switch to application view" : "Switch to process tree")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: Column headers (process view only)

    private var columnHeaders: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: 18)
            Text("Process")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Mem").frame(width: 68, alignment: .trailing)
            Text("CPU").frame(width: 44, alignment: .trailing)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.04))
    }

    // MARK: Process view

    private static let treeDisplayLimit = 50
    private static let searchLimit = 25

    private var processContent: some View {
        let list: [ProcessRecord]
        if isSearching {
            list = Array(engine.snapshot.processes
                .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
                .sorted { $0.residentMemory > $1.residentMemory }
                .prefix(Self.searchLimit))
        } else {
            list = []
        }

        return ScrollView {
            LazyVStack(spacing: 0) {
                if isSearching {
                    ForEach(list) { process in
                        ProcessRow(process: process, sortMode: .memory) {
                            pendingAction = .process(process)
                        }
                    }
                    if list.isEmpty {
                        Text("No matches").font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                } else {
                    treeRows
                }
            }
        }
        .frame(minHeight: 200, maxHeight: 500)
    }

    @ViewBuilder
    private var treeRows: some View {
        let roots = engine.snapshot.buildTree()
        let rows = Array(visibleNodes(from: roots).prefix(Self.treeDisplayLimit))
        if rows.isEmpty {
            Text("Sampling…").font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
        } else {
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
    }

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

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            let procs = engine.snapshot.processes.count
            let (apps, _) = buildApplicationGroups(snapshot: engine.snapshot)
            Text("\(apps.count) apps · \(procs) procs")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("v\(version)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Divider().frame(height: 14)
            HStack(spacing: 3) {
                Button(overlay.isVisible ? "Hide Widget" : "Widget") {
                    overlay.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(overlay.isVisible ? .primary : .secondary)
                Text(GlobalHotkeyMonitor.shortcutLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .opacity(hotkey.isActive ? 1 : 0.4)
                    .help(hotkey.isActive ? "" : "Click to enable global shortcut (requires Accessibility access)")
                    .onTapGesture {
                        guard !hotkey.isActive else { return }
                        hotkey.requestPermission()
                    }
            }
            Divider().frame(height: 14)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Apps list view (popup + main window)

struct AppsListView: View {
    @ObservedObject var engine: MonitoringEngine
    let searchText: String
    var maxHeight: CGFloat = .infinity

    @EnvironmentObject var appState: AppState

    @State private var sortMode: SortMode = .memory
    @State private var expandedGroupIDs: Set<pid_t> = []
    @State private var selectedGroupID: pid_t?
    @State private var pendingChipGroup: ApplicationGroup?
    @State private var pendingChipKind: Action.Kind = .suspend
    @State private var pendingRuleGroup: ApplicationGroup?
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var pendingAction: AppAction?

    private static let systemLimit = 5

    var body: some View {
        VStack(spacing: 0) {
            columnHeaders.fixedSize(horizontal: false, vertical: true)
            Divider()
            scrollContent
        }
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
            if case .process(let p) = action { ActionSheet(process: p) }
        }
        .onDisappear {
            selectedGroupID = nil
            pendingChipGroup = nil
            pendingRuleGroup = nil
            toastTask?.cancel()
            toastMessage = nil
        }
    }

    // MARK: Column headers

    private var columnHeaders: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: 40)
            Text("Application")
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 18)
            sortHeader("CPU", mode: .cpu, width: 44)
            sortHeader("Mem", mode: .memory, width: 60)
            Color.clear.frame(width: 90)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
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

    // MARK: Scroll content

    private var scrollContent: some View {
        let (apps, system) = buildApplicationGroups(snapshot: engine.snapshot)
        let sorted = sortedGroups(apps).filter {
            searchText.isEmpty || $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
        return ScrollView {
            LazyVStack(spacing: 0) {
                if sorted.isEmpty && !searchText.isEmpty {
                    Text("No apps matching \u{201C}\(searchText)\u{201D}")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                } else if sorted.isEmpty {
                    Text("Sampling…")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                } else {
                    ForEach(sorted) { group in
                        appGroupContent(group)
                    }
                    if !system.isEmpty && searchText.isEmpty {
                        systemSection(system)
                    }
                }
            }
        }
        .frame(minHeight: 200, maxHeight: maxHeight)
    }

    @ViewBuilder
    private func appGroupContent(_ group: ApplicationGroup) -> some View {
        let cap = memCap(for: group, in: appState.groupRuleSpecs)
        let isSelected = selectedGroupID == group.id
        let expanded = expandedGroupIDs.contains(group.id)
        ApplicationGroupRow(
            group: group,
            cap: cap,
            isSelected: isSelected,
            isExpanded: expanded,
            onToggle: {
                if expandedGroupIDs.contains(group.id) {
                    expandedGroupIDs.remove(group.id)
                } else {
                    expandedGroupIDs.insert(group.id)
                }
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
        if expanded {
            ForEach(group.processes.sorted { $0.residentMemory > $1.residentMemory }) { process in
                ProcessRow(process: process, sortMode: sortMode) {
                    pendingAction = .process(process)
                }
                .padding(.leading, 22)
            }
        }
    }

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
            ForEach(Array(procs.prefix(Self.systemLimit))) { proc in
                ProcessRow(process: proc, sortMode: .memory) {
                    pendingAction = .process(proc)
                }
            }
        }
    }
}

// MARK: - Tree row

struct TreeProcessRow: View {
    let node: ProcessTreeNode
    let isExpanded: Bool
    let onTap: () -> Void
    let onAction: () -> Void
    @Environment(\.iconCache) private var iconCache
    @State private var isHovered = false

    private static let maxIndentDepth = 4
    private var indent: CGFloat { CGFloat(min(node.depth, Self.maxIndentDepth)) * 12 }
    private var hasChildren: Bool { !node.children.isEmpty }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                if node.depth > 0 {
                    Color.clear.frame(width: indent)
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                }
                if hasChildren {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                } else {
                    Color.clear.frame(width: 14)
                }
                HStack(spacing: 6) {
                    processIcon
                    Text(iconCache.displayName(for: node.record))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(node.depth == 0 ? .primary : .secondary)
                    if let w = node.record.formattedDiskWrite {
                        Text(w).font(.caption2.monospacedDigit()).foregroundStyle(.orange)
                    } else if let r = node.record.formattedDiskRead {
                        Text(r).font(.caption2.monospacedDigit()).foregroundStyle(.blue)
                    }
                    Text(node.record.formattedMemory)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 68, alignment: .trailing)
                    Text(node.record.formattedCPU)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
            .padding(.leading, node.depth == 0 ? 8 : 2)
            .padding(.trailing, 12)
            .padding(.vertical, node.depth == 0 ? 5 : 3)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Action…") { onAction() }
        }
    }

    private var rowBackground: Color {
        if isHovered { return Color.primary.opacity(0.06) }
        if node.record.isReeve { return Color.accentColor.opacity(0.08) }
        return .clear
    }

    @ViewBuilder
    private var processIcon: some View {
        let size: CGFloat = node.depth == 0 ? 16 : 12
        if let icon = iconCache.icon(for: node.record) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

// MARK: - Flat row

struct ProcessRow: View {
    let process: ProcessRecord
    let sortMode: SortMode
    let onTap: () -> Void
    @Environment(\.iconCache) private var iconCache
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                processIcon
                Text(iconCache.displayName(for: process))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                metrics
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var metrics: some View {
        diskBadge
        switch sortMode {
        case .memory, .disk:
            Text(process.formattedMemory)
                .font(.caption.monospacedDigit())
                .frame(width: 68, alignment: .trailing)
            Text(process.formattedCPU)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        case .cpu:
            Text(process.formattedCPU)
                .font(.caption.monospacedDigit())
                .foregroundStyle(cpuColor)
                .frame(width: 44, alignment: .trailing)
            Text(process.formattedMemory)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var diskBadge: some View {
        if let w = process.formattedDiskWrite {
            Text(w).font(.caption2.monospacedDigit()).foregroundStyle(.orange).lineLimit(1)
        } else if let r = process.formattedDiskRead {
            Text(r).font(.caption2.monospacedDigit()).foregroundStyle(.blue).lineLimit(1)
        }
    }

    private var cpuColor: Color {
        if process.cpuPercent > 80 { return .red }
        if process.cpuPercent > 40 { return .orange }
        return .primary
    }

    private var rowBackground: Color {
        if isHovered { return Color.primary.opacity(0.06) }
        if process.isReeve { return Color.accentColor.opacity(0.08) }
        return .clear
    }

    @ViewBuilder
    private var processIcon: some View {
        if let icon = iconCache.icon(for: process) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
        } else {
            Color.clear.frame(width: 16, height: 16)
        }
    }
}
