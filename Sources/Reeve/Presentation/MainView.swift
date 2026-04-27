import AppKit
import SwiftUI
import ServiceManagement
import ReeveKit

// MARK: - Root

struct MainView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            ProcessesTab(engine: appState.engine)
                .tabItem { Label("Processes", systemImage: "cpu") }
            RulesTab()
                .environmentObject(appState)
                .tabItem { Label("Rules", systemImage: "slider.horizontal.3") }
            LogTab(groupRuleEngine: appState.groupRuleEngine)
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(minWidth: 760, minHeight: 500)
    }
}

// MARK: - Processes tab

struct ProcessesTab: View {
    @ObservedObject var engine: MonitoringEngine
    @Environment(\.iconCache) private var iconCache

    @State private var sortOrder: [KeyPathComparator<ProcessRecord>] = [
        KeyPathComparator(\ProcessRecord.residentMemory, order: .reverse)
    ]
    @State private var searchText = ""
    @State private var treeMode = false
    @State private var selectedPID: ProcessRecord.ID?
    @State private var actionProcess: ProcessRecord?

    private var filteredSorted: [ProcessRecord] {
        var list = searchText.isEmpty
            ? engine.snapshot.processes
            : engine.snapshot.processes.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        list.sort(using: sortOrder)
        return list
    }

    private var selectedRecord: ProcessRecord? {
        guard let pid = selectedPID else { return nil }
        return engine.snapshot.processes.first { $0.pid == pid }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if treeMode && searchText.isEmpty {
                treeContent
            } else {
                tableContent
            }
            Divider()
            statusBar
        }
        .sheet(item: $actionProcess) { ActionSheet(process: $0) }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            TextField("Search processes", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            Spacer()
            if let rec = selectedRecord {
                Button("Action…") { actionProcess = rec }
                    .buttonStyle(.bordered)
            }
            Divider().frame(height: 18)
            Button {
                treeMode.toggle()
                if treeMode { selectedPID = nil }
            } label: {
                Image(systemName: treeMode ? "list.bullet.indent" : "list.bullet")
            }
            .buttonStyle(.bordered)
            .help(treeMode ? "Switch to flat table" : "Switch to process tree")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Table

    private var tableContent: some View {
        Table(filteredSorted, selection: $selectedPID, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { proc in
                HStack(spacing: 6) {
                    procIcon(proc, size: 16)
                    Text(iconCache.displayName(for: proc))
                        .lineLimit(1)
                        .foregroundStyle(proc.isReeve ? Color.accentColor : .primary)
                }
            }
            .width(min: 140, ideal: 220)

            TableColumn("PID", value: \.pid) { proc in
                Text("\(proc.pid)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .width(58)

            TableColumn("CPU %", value: \.cpuPercent) { proc in
                Text(proc.formattedCPU)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(cpuColor(proc.cpuPercent))
            }
            .width(66)

            TableColumn("Memory", value: \.residentMemory) { proc in
                Text(proc.formattedMemory)
                    .font(.body.monospacedDigit())
            }
            .width(86)

            TableColumn("Disk Read", value: \.diskReadRate) { proc in
                Text(proc.formattedDiskRead ?? "—")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(proc.diskReadRate >= 1024 ? .primary : .tertiary)
            }
            .width(96)

            TableColumn("Disk Write", value: \.diskWriteRate) { proc in
                Text(proc.formattedDiskWrite ?? "—")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(proc.diskWriteRate >= 1024 ? .primary : .tertiary)
            }
            .width(96)
        }
        .contextMenu(forSelectionType: ProcessRecord.ID.self) { selection in
            if let pid = selection.first,
               let proc = engine.snapshot.processes.first(where: { $0.pid == pid }) {
                Button("Action…") { actionProcess = proc }
            }
        } primaryAction: { selection in
            if let pid = selection.first,
               let proc = engine.snapshot.processes.first(where: { $0.pid == pid }) {
                actionProcess = proc
            }
        }
    }

    // MARK: Tree

    private var treeContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(engine.snapshot.buildTree().flatMap { $0.flattened() }) { node in
                    treeRow(node)
                }
            }
        }
    }

    private func treeRow(_ node: ProcessTreeNode) -> some View {
        let maxDepth = 6
        let indent = CGFloat(min(node.depth, maxDepth)) * 14
        return Button { actionProcess = node.record } label: {
            HStack(spacing: 0) {
                if node.depth > 0 {
                    Color.clear.frame(width: indent)
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14)
                }
                HStack(spacing: 6) {
                    procIcon(node.record, size: node.depth == 0 ? 16 : 13)
                    Text(iconCache.displayName(for: node.record))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(node.depth == 0 ? .primary : .secondary)
                    if let w = node.record.formattedDiskWrite {
                        Text(w)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                    Text(node.record.formattedCPU)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(cpuColor(node.record.cpuPercent))
                        .frame(width: 52, alignment: .trailing)
                    Text(node.record.formattedMemory)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
            }
            .padding(.leading, node.depth == 0 ? 12 : 4)
            .padding(.trailing, 12)
            .padding(.vertical, node.depth == 0 ? 5 : 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack {
            let count = engine.snapshot.processes.count
            Text("\(count) process\(count == 1 ? "" : "es")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if !searchText.isEmpty {
                Text("· \(filteredSorted.count) matching")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(engine.snapshot.sampledAt, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: Helpers

    @ViewBuilder
    private func procIcon(_ proc: ProcessRecord, size: CGFloat) -> some View {
        if let icon = iconCache.icon(for: proc) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }

    private func cpuColor(_ pct: Double) -> Color {
        if pct > 80 { return .red }
        if pct > 40 { return .orange }
        return .primary
    }
}

// MARK: - General tab

struct GeneralTab: View {
    @AppStorage("overlayShowOnLaunch") private var overlayShowOnLaunch = false
    @AppStorage("menuBarMetric") private var menuBarMetric: MenuBarMetric = .cpu
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        if enabled {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                Toggle("Show overlay widget on launch", isOn: $overlayShowOnLaunch)
            }

            Section("Menu Bar") {
                Picker("Show metric", selection: $menuBarMetric) {
                    ForEach(MenuBarMetric.allCases, id: \.self) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Monitoring") {
                LabeledContent("Active poll rate", value: "1 second")
                LabeledContent("Idle poll rate", value: "5 seconds")
                Text("Active means the popover, main window, or overlay widget is open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Overlay Widget") {
                LabeledContent("Toggle shortcut", value: GlobalHotkeyMonitor.shortcutLabel)
                Text("The overlay widget sits on the desktop, below all application windows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
