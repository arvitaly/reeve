import SwiftUI
import ReeveKit

enum SortMode: String, CaseIterable {
    case memory = "Mem"
    case cpu = "CPU"
    case disk = "Disk"
}

struct MenuBarView: View {
    @ObservedObject var engine: MonitoringEngine
    @ObservedObject var overlay: OverlayController
    @ObservedObject var hotkey: GlobalHotkeyMonitor
    @EnvironmentObject var appState: AppState
    let mainWindow: MainWindowController

    @State private var selectedProcess: ProcessRecord?
    @State private var sortMode: SortMode = .memory
    @State private var searchText: String = ""
    @State private var treeMode: Bool = false

    private var isSearching: Bool { !searchText.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if treeMode && !isSearching {
                treeList
            } else {
                processList
            }
            Divider()
            footer
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
        .sheet(item: $selectedProcess) { process in
            ActionSheet(process: process)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Reeve")
                    .font(.headline)
                Spacer()
                Button("Open Reeve") {
                    mainWindow.show(appState: appState)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                Text(engine.snapshot.sampledAt, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            TextField("Search processes", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: Flat list

    private static let flatLimit = 15
    private static let searchLimit = 25

    private var processList: some View {
        VStack(spacing: 0) {
            let list = isSearching ? filteredProcesses : Array(sortedProcesses.prefix(Self.flatLimit))
            if list.isEmpty {
                Text("No matches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                ForEach(list) { process in
                    ProcessRow(process: process) { selectedProcess = process }
                }
            }
        }
    }

    // MARK: Tree list

    private static let treeDisplayLimit = 30

    private var treeList: some View {
        VStack(spacing: 0) {
            let rows = engine.snapshot.buildTree()
                .flatMap { $0.flattened() }
                .prefix(Self.treeDisplayLimit)
            if rows.isEmpty {
                Text("Sampling…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                ForEach(Array(rows), id: \.id) { node in
                    TreeProcessRow(node: node) { selectedProcess = node.record }
                }
            }
        }
    }

    // MARK: Computed data

    private var filteredProcesses: [ProcessRecord] {
        Array(engine.snapshot.processes
            .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.residentMemory > $1.residentMemory }
            .prefix(Self.searchLimit))
    }

    private var sortedProcesses: [ProcessRecord] {
        switch sortMode {
        case .memory: return engine.snapshot.topByMemory
        case .cpu:    return engine.snapshot.topByCPU
        case .disk:   return engine.snapshot.topByDiskWrite
        }
    }

    private var processCountLabel: String {
        if isSearching {
            let total = engine.snapshot.processes.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }.count
            let shown = min(total, Self.searchLimit)
            return total > Self.searchLimit ? "\(shown) of \(total)" : "\(total)"
        }
        return "\(engine.snapshot.processes.count)"
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Text(processCountLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if !treeMode {
                Picker("Sort", selection: $sortMode) {
                    ForEach(SortMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 100)
            }
            Button {
                treeMode.toggle()
            } label: {
                Image(systemName: treeMode ? "list.bullet.indent" : "list.bullet")
                    .foregroundStyle(treeMode ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(treeMode ? "Switch to flat list" : "Switch to process tree")
            Spacer()
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
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Tree row

struct TreeProcessRow: View {
    let node: ProcessTreeNode
    let onTap: () -> Void
    @Environment(\.iconCache) private var iconCache
    @State private var isHovered = false

    private static let maxIndentDepth = 4
    private var indent: CGFloat { CGFloat(min(node.depth, Self.maxIndentDepth)) * 10 }

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
                HStack(spacing: 6) {
                    processIcon
                    Text(node.record.name)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(node.depth == 0 ? .primary : .secondary)
                    diskIndicators
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
            .padding(.leading, node.depth == 0 ? 12 : 4)
            .padding(.trailing, 12)
            .padding(.vertical, node.depth == 0 ? 5 : 3)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var diskIndicators: some View {
        if let w = node.record.formattedDiskWrite {
            Text(w)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else if let r = node.record.formattedDiskRead {
            Text(r)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.blue)
                .lineLimit(1)
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
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

// MARK: - Flat row

struct ProcessRow: View {
    let process: ProcessRecord
    let onTap: () -> Void
    @Environment(\.iconCache) private var iconCache
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                processIcon
                Text(process.name)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                diskIndicators
                Text(process.formattedMemory)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 68, alignment: .trailing)
                Text(process.formattedCPU)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var diskIndicators: some View {
        if let w = process.formattedDiskWrite {
            Text(w)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else if let r = process.formattedDiskRead {
            Text(r)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.blue)
                .lineLimit(1)
        }
    }

    private var rowBackground: Color {
        if isHovered { return Color.primary.opacity(0.06) }
        if process.isReeve { return Color.accentColor.opacity(0.08) }
        return .clear
    }

    @ViewBuilder
    private var processIcon: some View {
        if let icon = iconCache.icon(for: process) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
        } else {
            Color.clear.frame(width: 16, height: 16)
        }
    }
}
