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
    @State private var selectedProcess: ProcessRecord?
    @State private var sortMode: SortMode = .memory

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            processList
            Divider()
            footer
        }
        .frame(width: 300)
        .onAppear { engine.showWindow(id: "menuBar") }
        .onDisappear { engine.hideWindow(id: "menuBar") }
        .sheet(item: $selectedProcess) { process in
            ActionSheet(process: process)
        }
    }

    private var header: some View {
        HStack {
            Text("Reeve")
                .font(.headline)
            Spacer()
            Text(engine.snapshot.sampledAt, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var processList: some View {
        VStack(spacing: 0) {
            ForEach(sortedProcesses.prefix(8)) { process in
                ProcessRow(process: process) {
                    selectedProcess = process
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

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(engine.snapshot.processes.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Picker("Sort", selection: $sortMode) {
                ForEach(SortMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 100)
            Spacer()
            Button(overlay.isVisible ? "Hide Overlay" : "Overlay") {
                overlay.toggle()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(overlay.isVisible ? .primary : .secondary)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

struct ProcessRow: View {
    let process: ProcessRecord
    let onTap: () -> Void
    @Environment(\.iconCache) private var iconCache

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                processIcon
                Text(process.name)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(process.formattedMemory)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 68, alignment: .trailing)
                Text(process.formattedCPU)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(process.isReeve ? Color.accentColor.opacity(0.08) : .clear)
        }
        .buttonStyle(.plain)
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
