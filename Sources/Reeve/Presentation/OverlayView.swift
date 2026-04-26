import SwiftUI
import ReeveKit

/// Desktop widget — application-group view matching the popover layout.
struct OverlayView: View {
    @ObservedObject var engine: MonitoringEngine
    @EnvironmentObject var appState: AppState
    let onClose: () -> Void

    @State private var sortMode: SortMode = .memory
    @State private var showProcesses: Bool = false   // false = apps, true = process tree
    @State private var searchText: String = ""
    @State private var expandedPIDs: Set<pid_t> = []         // process tree
    @State private var expandedGroupIDs: Set<pid_t> = []     // app groups
    @State private var pendingAction: AppAction?

    private var isSearching: Bool { !searchText.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.fixedSize(horizontal: false, vertical: true)
            Divider()
            columnHeaders.fixedSize(horizontal: false, vertical: true)
            Divider()
            content
            Divider()
            footer.fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(item: $pendingAction) { action in
            switch action {
            case .group(let g):   ApplicationGroupSheet(group: g)
            case .process(let p): ActionSheet(process: p)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Reeve").font(.headline)
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
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: Column headers

    private var columnHeaders: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: showProcesses ? 18 : 40)  // process: icon; apps: chevron+icon
            Text(showProcesses ? "Process" : "Application")
                .frame(maxWidth: .infinity, alignment: .leading)
            if showProcesses {
                Text("Mem").frame(width: 68, alignment: .trailing)
                Text("CPU").frame(width: 44, alignment: .trailing)
            } else {
                Color.clear.frame(width: 18)  // count
                sortHeader("CPU", mode: .cpu, width: 44)
                sortHeader("Mem", mode: .memory, width: 60)
                Color.clear.frame(width: 90)  // bar+dot
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
        if showProcesses || isSearching {
            processContent
        } else {
            appsContent
        }
    }

    // MARK: Apps view

    private var appsContent: some View {
        let (apps, system) = buildApplicationGroups(snapshot: engine.snapshot)
        let sorted = sortedGroups(apps)
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sorted) { group in
                    let cap = memCap(for: group, in: appState.groupRuleSpecs)
                    let expanded = expandedGroupIDs.contains(group.id)
                    ApplicationGroupRow(
                        group: group,
                        cap: cap,
                        isExpanded: expanded,
                        onToggle: {
                            if expandedGroupIDs.contains(group.id) {
                                expandedGroupIDs.remove(group.id)
                            } else {
                                expandedGroupIDs.insert(group.id)
                            }
                        },
                        onAction: { pendingAction = .group(group) }
                    )
                    if expanded {
                        ForEach(group.processes.sorted { $0.residentMemory > $1.residentMemory }) { process in
                            ProcessRow(process: process, sortMode: sortMode) {
                                pendingAction = .process(process)
                            }
                            .padding(.leading, 22)
                        }
                    }
                }
                if !system.isEmpty {
                    systemSection(system)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func sortedGroups(_ groups: [ApplicationGroup]) -> [ApplicationGroup] {
        switch sortMode {
        case .memory: return groups.sorted { $0.totalMemory > $1.totalMemory }
        case .cpu:    return groups.sorted { $0.totalCPU > $1.totalCPU }
        case .disk:   return groups.sorted { $0.totalDiskWrite > $1.totalDiskWrite }
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

    // MARK: Process view

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
            if !showProcesses && !isSearching {
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
