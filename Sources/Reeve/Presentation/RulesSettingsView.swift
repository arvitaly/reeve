import SwiftUI
import ReeveKit

// MARK: - Root

struct RulesSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            RulesTab()
                .environmentObject(appState)
                .tabItem { Label("Rules", systemImage: "slider.horizontal.3") }
            LogTab(engine: appState.engine)
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 720, height: 520)
    }
}

// MARK: - Rules tab

struct RulesTab: View {
    @EnvironmentObject var appState: AppState
    @State private var editing: RuleSpec?
    @State private var isAdding = false
    @State private var pendingDelete: RuleSpec?

    var body: some View {
        VStack(spacing: 0) {
            if appState.ruleSpecs.isEmpty {
                emptyState
            } else {
                ruleList
            }
            Divider()
            toolbar
        }
        .sheet(isPresented: $isAdding) {
            RuleEditSheet(spec: RuleSpec()) { appState.ruleSpecs.append($0) }
        }
        .sheet(item: $editing) { spec in
            RuleEditSheet(spec: spec) { updated in
                guard let i = appState.ruleSpecs.firstIndex(where: { $0.id == updated.id })
                else { return }
                appState.ruleSpecs[i] = updated
            }
        }
        .confirmationDialog(
            "Delete \"\(pendingDelete?.name ?? "")\"?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let spec = pendingDelete {
                    appState.ruleSpecs.removeAll { $0.id == spec.id }
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No rules yet")
                .foregroundStyle(.secondary)
            Text("Rules fire an action automatically whenever a condition holds.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Add your first rule") { isAdding = true }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var ruleList: some View {
        List {
            ForEach($appState.ruleSpecs) { $spec in
                RuleSpecRow(spec: $spec, onEdit: { editing = spec }, onDelete: {
                    pendingDelete = spec
                })
            }
            .onMove { appState.ruleSpecs.move(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.inset)
    }

    private var toolbar: some View {
        HStack {
            Button { isAdding = true } label: {
                Label("Add Rule", systemImage: "plus")
            }
            Spacer()
            let n = appState.ruleSpecs.count
            Text("\(n) rule\(n == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Log tab

struct LogTab: View {
    @ObservedObject var engine: MonitoringEngine

    private var sortedLog: [ActionLogEntry] {
        engine.actionLog.reversed()
    }

    var body: some View {
        VStack(spacing: 0) {
            if engine.actionLog.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No rules have fired yet")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sortedLog) { entry in
                    LogEntryRow(entry: entry)
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                Text("\(engine.actionLog.count) entr\(engine.actionLog.count == 1 ? "y" : "ies")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !engine.actionLog.isEmpty {
                    Button("Clear") { engine.clearLog() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

private struct LogEntryRow: View {
    let entry: ActionLogEntry

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.action.target.name)
                        .fontWeight(.medium)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(entry.ruleName)
                        .foregroundStyle(.secondary)
                }
                Text("\(entry.preflight.description)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.firedAt, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(entry.firedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Rule row

private struct RuleSpecRow: View {
    @Binding var spec: RuleSpec
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $spec.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.name.isEmpty ? "(unnamed)" : spec.name)
                    .fontWeight(.medium)
                Text("\(spec.condition.displayName)  →  \(spec.action.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit", action: onEdit)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Edit sheet

struct RuleEditSheet: View {
    @State private var spec: RuleSpec
    @State private var condTag: CondTag = .cpu
    @State private var cpuThreshold: Double = 50
    @State private var memGB: Double = 1.0
    @State private var diskMBps: Double = 10.0
    @State private var nameQuery: String = ""
    @Environment(\.dismiss) private var dismiss

    let onSave: (RuleSpec) -> Void

    enum CondTag: String, CaseIterable, Identifiable {
        case cpu = "CPU"
        case memory = "Memory"
        case disk = "Disk"
        case name = "Name"
        var id: String { rawValue }
    }

    init(spec: RuleSpec, onSave: @escaping (RuleSpec) -> Void) {
        self.onSave = onSave
        _spec = State(initialValue: spec)
        switch spec.condition {
        case .cpuAbove(let v):             _condTag = State(initialValue: .cpu);    _cpuThreshold = State(initialValue: v)
        case .memoryAboveGB(let v):        _condTag = State(initialValue: .memory); _memGB = State(initialValue: v)
        case .diskWriteAboveMBps(let v):   _condTag = State(initialValue: .disk);   _diskMBps = State(initialValue: v)
        case .nameContains(let s):         _condTag = State(initialValue: .name);   _nameQuery = State(initialValue: s)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(spec.name.isEmpty ? "New Rule" : spec.name)
                .font(.headline)

            Form {
                TextField("Name", text: $spec.name)
                Divider()

                Picker("Condition", selection: $condTag) {
                    ForEach(CondTag.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                conditionValueField

                Picker("Action", selection: $spec.action) {
                    ForEach(RuleSpec.ActionKind.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }

                HStack {
                    Text("Cooldown")
                    Spacer()
                    TextField("", value: $spec.cooldownSeconds, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Text("s")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    spec.condition = assembledCondition
                    onSave(spec)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(spec.name.isEmpty || !conditionIsValid)
            }
        }
        .padding(20)
        .frame(width: 380, height: 310)
    }

    @ViewBuilder
    private var conditionValueField: some View {
        switch condTag {
        case .cpu:
            HStack {
                Text("CPU above")
                Slider(value: $cpuThreshold, in: 1...100, step: 1)
                Text("\(Int(cpuThreshold))%")
                    .frame(width: 36)
                    .monospacedDigit()
            }
        case .memory:
            HStack {
                Text("Memory above")
                TextField("", value: $memGB, format: .number)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                Text("GB")
                    .foregroundStyle(.secondary)
            }
        case .disk:
            HStack {
                Text("Disk write above")
                TextField("", value: $diskMBps, format: .number)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                Text("MB/s")
                    .foregroundStyle(.secondary)
            }
        case .name:
            HStack {
                Text("Name contains")
                TextField("process name", text: $nameQuery)
            }
        }
    }

    private var assembledCondition: RuleSpec.ConditionKind {
        switch condTag {
        case .cpu:    return .cpuAbove(cpuThreshold)
        case .memory: return .memoryAboveGB(memGB)
        case .disk:   return .diskWriteAboveMBps(diskMBps)
        case .name:   return .nameContains(nameQuery)
        }
    }

    private var conditionIsValid: Bool {
        switch condTag {
        case .cpu:    return cpuThreshold > 0
        case .memory: return memGB > 0
        case .disk:   return diskMBps > 0
        case .name:   return !nameQuery.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}
