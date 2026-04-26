import SwiftUI
import ReeveKit

// MARK: - Root (Settings window)

struct RulesSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            RulesTab()
                .environmentObject(appState)
                .tabItem { Label("Rules", systemImage: "slider.horizontal.3") }
            LogTab(groupRuleEngine: appState.groupRuleEngine)
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
    @State private var editing: GroupRuleSpec?
    @State private var isAdding = false
    @State private var pendingDelete: GroupRuleSpec?

    var body: some View {
        VStack(spacing: 0) {
            if appState.groupRuleSpecs.isEmpty {
                emptyState
            } else {
                ruleList
            }
            Divider()
            toolbar
        }
        .sheet(isPresented: $isAdding) {
            GroupRuleEditSheet(spec: GroupRuleSpec()) { appState.groupRuleSpecs.append($0) }
        }
        .sheet(item: $editing) { spec in
            GroupRuleEditSheet(spec: spec) { updated in
                guard let i = appState.groupRuleSpecs.firstIndex(where: { $0.id == updated.id })
                else { return }
                appState.groupRuleSpecs[i] = updated
            }
        }
        .confirmationDialog(
            "Delete \"\(pendingDelete?.appNamePattern ?? "")\"?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let spec = pendingDelete { appState.groupRuleSpecs.removeAll { $0.id == spec.id } }
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
            Text("Rules automatically act on an application group when a threshold is crossed.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Add rule") { isAdding = true }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var ruleList: some View {
        List {
            ForEach($appState.groupRuleSpecs) { $spec in
                GroupRuleSpecRow(spec: $spec, onEdit: { editing = spec }, onDelete: { pendingDelete = spec })
            }
            .onMove { appState.groupRuleSpecs.move(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.inset)
    }

    private var toolbar: some View {
        HStack {
            Button { isAdding = true } label: {
                Label("Add Rule", systemImage: "plus")
            }
            Spacer()
            let n = appState.groupRuleSpecs.count
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
    @ObservedObject var groupRuleEngine: GroupRuleEngine

    var body: some View {
        VStack(spacing: 0) {
            if groupRuleEngine.actionLog.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No rules have fired yet")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(groupRuleEngine.actionLog.reversed()) { entry in
                    GroupLogEntryRow(entry: entry)
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                let n = groupRuleEngine.actionLog.count
                Text("\(n) entr\(n == 1 ? "y" : "ies")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !groupRuleEngine.actionLog.isEmpty {
                    Button("Clear") { groupRuleEngine.clearLog() }
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

private struct GroupLogEntryRow: View {
    let entry: GroupActionLogEntry

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.appName).fontWeight(.medium)
                    Text("·").foregroundStyle(.tertiary)
                    Text(entry.actionName).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(entry.processCount) proc.").font(.caption).foregroundStyle(.tertiary)
                }
                Text(entry.conditionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

private struct GroupRuleSpecRow: View {
    @Binding var spec: GroupRuleSpec
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $spec.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.appNamePattern.isEmpty ? "(unnamed)" : spec.appNamePattern)
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
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Edit sheet

struct GroupRuleEditSheet: View {
    @State private var spec: GroupRuleSpec
    @State private var condTag: CondTag = .memory
    @State private var memGB: Double = 2.0
    @State private var cpuPct: Double = 80.0
    @Environment(\.dismiss) private var dismiss
    let onSave: (GroupRuleSpec) -> Void

    enum CondTag: String, CaseIterable, Identifiable {
        case memory = "Memory"
        case cpu = "CPU"
        var id: String { rawValue }
    }

    init(spec: GroupRuleSpec, onSave: @escaping (GroupRuleSpec) -> Void) {
        self.onSave = onSave
        _spec = State(initialValue: spec)
        switch spec.condition {
        case .totalMemoryAboveGB(let v): _condTag = State(initialValue: .memory); _memGB = State(initialValue: v)
        case .totalCPUAbove(let v):      _condTag = State(initialValue: .cpu);    _cpuPct = State(initialValue: v)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(spec.appNamePattern.isEmpty ? "New Rule" : spec.appNamePattern)
                .font(.headline)

            Form {
                TextField("App name", text: $spec.appNamePattern)
                    .help("Case-insensitive substring match on the application name shown in the app list (e.g. \"Google Chrome\", \"Chrome\").")
                Divider()

                Picker("Condition", selection: $condTag) {
                    ForEach(CondTag.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                conditionField

                Picker("Action", selection: $spec.action) {
                    ForEach(GroupRuleSpec.ActionKind.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }

                HStack {
                    Text("Cooldown")
                    Spacer()
                    TextField("", value: $spec.cooldownSeconds, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Text("s").foregroundStyle(.secondary)
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
                .disabled(spec.appNamePattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380, height: 280)
    }

    @ViewBuilder
    private var conditionField: some View {
        switch condTag {
        case .memory:
            HStack {
                Text("Total memory above")
                TextField("", value: $memGB, format: .number)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                Text("GB").foregroundStyle(.secondary)
            }
        case .cpu:
            HStack {
                Text("Total CPU above")
                Slider(value: $cpuPct, in: 1...400, step: 1)
                Text("\(Int(cpuPct))%")
                    .frame(width: 44)
                    .monospacedDigit()
            }
        }
    }

    private var assembledCondition: GroupRuleSpec.ConditionKind {
        switch condTag {
        case .memory: return .totalMemoryAboveGB(memGB)
        case .cpu:    return .totalCPUAbove(cpuPct)
        }
    }
}
