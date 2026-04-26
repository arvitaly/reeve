import SwiftUI
import ReeveKit

/// Desktop widget — full-featured copy of the popover, sits at desktop level top-right.
struct OverlayView: View {
    @ObservedObject var engine: MonitoringEngine
    let onClose: () -> Void

    @State private var sortMode: SortMode = .memory
    @State private var treeMode: Bool = true
    @State private var searchText: String = ""
    @State private var expandedPIDs: Set<pid_t> = []
    @State private var selectedProcess: ProcessRecord?

    private var isSearching: Bool { !searchText.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if treeMode && !isSearching {
                treeContent
            } else {
                listContent
            }
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(item: $selectedProcess) { ActionSheet(process: $0) }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Reeve")
                    .font(.headline)
                Spacer()
                Text(engine.snapshot.sampledAt, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                TextField("Search processes", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Button {
                    treeMode.toggle()
                } label: {
                    Label(treeMode ? "Tree" : "Flat",
                          systemImage: treeMode ? "list.bullet.indent" : "list.bullet")
                        .font(.caption)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(treeMode ? Color.accentColor : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: Tree

    private var treeContent: some View {
        let roots = engine.snapshot.buildTree()
        let rows = Array(visibleNodes(from: roots).prefix(200))
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rows, id: \.id) { node in
                    TreeProcessRow(
                        node: node,
                        isExpanded: expandedPIDs.contains(node.record.pid),
                        onTap: {
                            if node.children.isEmpty {
                                selectedProcess = node.record
                            } else {
                                let pid = node.record.pid
                                if expandedPIDs.contains(pid) {
                                    collapseSubtree(node)
                                } else {
                                    expandedPIDs.insert(pid)
                                }
                            }
                        },
                        onAction: { selectedProcess = node.record }
                    )
                }
            }
        }
    }

    // MARK: Flat list

    private var listContent: some View {
        let list: [ProcessRecord] = isSearching
            ? engine.snapshot.processes
                .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
                .sorted { $0.residentMemory > $1.residentMemory }
            : sortedProcesses
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(list) { process in
                    ProcessRow(process: process, sortMode: sortMode) {
                        selectedProcess = process
                    }
                }
            }
        }
    }

    private var sortedProcesses: [ProcessRecord] {
        switch sortMode {
        case .memory: return engine.snapshot.topByMemory
        case .cpu:    return engine.snapshot.topByCPU
        case .disk:   return engine.snapshot.topByDiskWrite
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            let count = engine.snapshot.processes.count
            Text("\(count) processes")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if !treeMode {
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
