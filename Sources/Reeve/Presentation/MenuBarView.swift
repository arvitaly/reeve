import SwiftUI
import ReeveKit

struct MenuBarView: View {
    @ObservedObject var engine: MonitoringEngine
    @State private var selectedProcess: ProcessRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            processList
            Divider()
            footer
        }
        .frame(width: 300)
        .onAppear {
            engine.windowVisible = true
            engine.start()
        }
        .onDisappear {
            engine.windowVisible = false
        }
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
            ForEach(engine.snapshot.topByMemory.prefix(8)) { process in
                ProcessRow(process: process) {
                    selectedProcess = process
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(engine.snapshot.processes.count) processes")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
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

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
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
}
