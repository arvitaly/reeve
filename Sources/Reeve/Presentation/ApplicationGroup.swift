import AppKit
import Darwin
import SwiftUI
import ReeveKit

// MARK: - Sort mode

enum SortMode: String, CaseIterable {
    case memory = "Footprint"
    case rss = "RSS"
    case cpu = "CPU"
    case disk = "Disk"
}

// MARK: - Model

struct ApplicationGroup: Identifiable {
    let id: pid_t  // root process PID (NSRunningApplication.processIdentifier)
    let displayName: String
    let icon: NSImage?
    let processes: [ProcessRecord]

    /// Footprint-based total (compressed + resident + IOKit). Falls back to RSS per-process
    /// when rusage returned EPERM.
    var totalMemory: UInt64 {
        processes.reduce(0) { $0 + ($1.physFootprint ?? $1.residentMemory) }
    }
    var totalRSS: UInt64 { processes.reduce(0) { $0 + $1.residentMemory } }
    var totalCPU: Double { processes.reduce(0) { $0 + $1.cpuPercent } }
    var totalDiskWrite: UInt64 { processes.reduce(0) { $0 + $1.diskWriteRate } }
    var isReeve: Bool { processes.contains { $0.isReeve } }
    var isSuspended: Bool { !processes.isEmpty && processes.allSatisfy { $0.isSuspended } }
    var maxNiceValue: Int32 { processes.map { $0.niceValue }.max() ?? 0 }

    var formattedMemory: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalMemory), countStyle: .memory)
    }
    var formattedRSS: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalRSS), countStyle: .memory)
    }
    var formattedCPU: String { String(format: "%.1f%%", totalCPU) }
}

// Terminal apps are split per-tab. Terminal.app spawns shells via root-owned `login`
// processes that are invisible to the sampler (PROC_PIDTASKINFO fails with EPERM).
// We recover the link by calling PROC_PIDT_SHORTBSDINFO on the phantom parent —
// that flavor is readable without elevated privileges.
private let terminalBundleIDs: Set<String> = [
    "com.apple.Terminal",
    "com.googlecode.iterm2",
    "dev.warp.Warp-Stable",
    "dev.warp.Warp",
    "io.alacritty",
    "net.kovidgoyal.kitty",
    "com.github.wez.wezterm",
    "co.zeit.hyper",
]

private let shellNames: Set<String> = ["zsh", "bash", "fish", "sh", "dash", "tcsh", "csh"]

// Returns the parent PID of `pid` using PROC_PIDT_SHORTBSDINFO (no root required).
// Returns 0 on failure.
private func parentPIDOf(_ pid: pid_t) -> pid_t {
    var info = proc_bsdshortinfo()
    let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return 0 }
    return pid_t(info.pbsi_ppid)
}

private func tabGroupName(terminalName: String, shell: ProcessTreeNode) -> String {
    let top = shell.flattened()
        .filter { !shellNames.contains($0.record.name.lowercased()) }
        .max(by: { $0.record.residentMemory < $1.record.residentMemory })
    return "\(terminalName): \(top?.record.name ?? shell.record.name)"
}

// Finds tab groups for a terminal app by resolving phantom parent chains.
// Each root-owned intermediary (login) is a phantom: we look up its parent PID to
// confirm it belongs to this terminal, then group by that phantom PID (= one tab).
private func resolveTerminalTabs(
    terminalPID: pid_t,
    appName: String,
    icon: NSImage?,
    snapshot: SystemSnapshot,
    nodeByPID: [pid_t: ProcessTreeNode],
    claimed: inout Set<pid_t>
) -> [ApplicationGroup] {
    var phantomToGrandparent: [pid_t: pid_t] = [:]
    var tabsByPhantom: [pid_t: [ProcessTreeNode]] = [:]

    for process in snapshot.processes {
        guard let node = nodeByPID[process.pid],
              nodeByPID[process.parentPID] == nil,  // parent absent from snapshot
              process.parentPID > 1 else { continue }
        let phantom = process.parentPID
        if phantomToGrandparent[phantom] == nil {
            phantomToGrandparent[phantom] = parentPIDOf(phantom)
        }
        guard phantomToGrandparent[phantom] == terminalPID else { continue }
        tabsByPhantom[phantom, default: []].append(node)
    }

    var groups: [ApplicationGroup] = []
    for (_, nodes) in tabsByPhantom.sorted(by: { $0.key < $1.key }) {
        let combined = nodes.flatMap { $0.flattened().map { $0.record } }
        let pids = Set(combined.map { $0.pid })
        guard claimed.isDisjoint(with: pids) else { continue }
        claimed.formUnion(pids)
        let mainNode = nodes.max(by: { $0.record.residentMemory < $1.record.residentMemory }) ?? nodes[0]
        groups.append(ApplicationGroup(
            id: mainNode.record.pid,
            displayName: tabGroupName(terminalName: appName, shell: mainNode),
            icon: icon,
            processes: combined
        ))
    }
    return groups
}

/// Groups snapshot processes by NSRunningApplication ownership.
///
/// Each NSRunningApplication anchors a subtree in the process tree — all descendants
/// belong to that application group. Terminal emulators are split per-tab via phantom
/// parent resolution (root-owned intermediary processes like `login` are resolved
/// through PROC_PIDT_SHORTBSDINFO). Processes not claimed by any running application
/// are returned separately as system processes.
func buildApplicationGroups(snapshot: SystemSnapshot) -> (apps: [ApplicationGroup], system: [ProcessRecord]) {
    let tree = snapshot.buildTree()
    var nodeByPID: [pid_t: ProcessTreeNode] = [:]
    for root in tree {
        for node in root.flattened() { nodeByPID[node.record.pid] = node }
    }

    var claimed: Set<pid_t> = []
    var apps: [ApplicationGroup] = []

    for app in NSWorkspace.shared.runningApplications {
        let pid = app.processIdentifier
        guard pid > 0, let rootNode = nodeByPID[pid] else { continue }

        if terminalBundleIDs.contains(app.bundleIdentifier ?? "") {
            let appName = app.localizedName ?? rootNode.record.name
            let tabs = resolveTerminalTabs(
                terminalPID: pid, appName: appName, icon: app.icon,
                snapshot: snapshot, nodeByPID: nodeByPID, claimed: &claimed
            )
            if !tabs.isEmpty {
                apps.append(contentsOf: tabs)
                continue  // terminal app process itself stays unclaimed → system
            }
        }

        let procs = rootNode.flattened().map { $0.record }
        let pids = Set(procs.map { $0.pid })
        guard claimed.isDisjoint(with: pids) else { continue }
        claimed.formUnion(pids)
        apps.append(ApplicationGroup(
            id: pid,
            displayName: app.localizedName ?? rootNode.record.name,
            icon: app.icon,
            processes: procs
        ))
    }

    apps.sort { $0.totalMemory > $1.totalMemory }
    let system = snapshot.processes
        .filter { !claimed.contains($0.pid) }
        .sorted { $0.residentMemory > $1.residentMemory }
    return (apps, system)
}

// MARK: - Severity computation (ADR-2)

extension ApplicationGroup {
    func memSeverity(cap: UInt64?) -> Severity {
        if let cap, cap > 0 {
            let pct = Double(totalMemory) / Double(cap)
            if pct >= 1.0 { return .over }
            if pct >= 0.7 { return .warn }
            return .normal
        }
        let gb = Double(totalMemory) / (1024 * 1024 * 1024)
        if gb >= 10.0 { return .over }
        if gb >= 6.0 { return .warn }
        return .normal
    }

    func cpuSeverity() -> Severity {
        if totalCPU >= 80 { return .over }
        if totalCPU >= 50 { return .warn }
        return .normal
    }

    func overallSeverity(cap: UInt64?) -> Severity {
        max(memSeverity(cap: cap), cpuSeverity())
    }
}

/// Returns the tightest (lowest) memory cap from enabled rules matching the group.
/// Tightest wins when multiple specs match — see ADR-2.
func memCap(for group: ApplicationGroup, in specs: [GroupRuleSpec]) -> UInt64? {
    specs
        .filter {
            $0.isEnabled &&
            !$0.appNamePattern.isEmpty &&
            group.displayName.localizedCaseInsensitiveContains($0.appNamePattern)
        }
        .compactMap { spec -> UInt64? in
            guard case .totalMemoryAboveGB(let gb) = spec.condition else { return nil }
            return UInt64(gb * 1_073_741_824)
        }
        .min()
}

// MARK: - Shared sheet item type

enum AppAction: Identifiable {
    case process(ProcessRecord)

    var id: String {
        if case .process(let p) = self { return "p-\(p.id)" }
        return ""
    }
}

// MARK: - App group row

// Column grid: [chevron 14] [icon 20] [name flex] [count 18] [cpu 44] [rss 52] [foot 60] [bar+dot 90]
struct ApplicationGroupRow: View {
    let group: ApplicationGroup
    let cap: UInt64?
    let isSelected: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let onSelect: () -> Void
    @State private var isHovered = false

    private var severity: Severity { group.overallSeverity(cap: cap) }

    var body: some View {
        HStack(spacing: 6) {
            // Chevron is its own tap target — does not propagate to the row's onTapGesture.
            Button(action: onToggle) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(group.processes.count > 1 ? Color.secondary : .clear)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
            if let icon = group.icon {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 20, height: 20)
                    .opacity(group.isSuspended ? 0.4 : 1.0)
            } else {
                Color.clear.frame(width: 20, height: 20)
            }
            HStack(spacing: 4) {
                Text(group.displayName)
                    .lineLimit(1)
                    .foregroundStyle(group.isReeve ? Color.accentColor : .primary)
                if group.isSuspended {
                    statusBadge("paused", color: .secondary)
                } else if group.maxNiceValue > 0 {
                    statusBadge("nice +\(group.maxNiceValue)", color: Color.rvAccent)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(group.processes.count > 1 ? "\(group.processes.count)" : "")
                .font(.caption2)
                .foregroundStyle(Color.rvTextFaint)
                .frame(width: 18, alignment: .trailing)
            Text(group.formattedCPU)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.rvTextDim)
                .frame(width: 44, alignment: .trailing)
            Text(group.formattedRSS)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.rvTextFaint)
                .frame(width: 52, alignment: .trailing)
            Text(group.formattedMemory)
                .font(.caption.monospacedDigit())
                .foregroundStyle(severity.textColor)
                .frame(width: 60, alignment: .trailing)
            HStack(spacing: 4) {
                MiniBar(value: Double(group.totalMemory), cap: cap.map(Double.init), width: 80, severity: severity)
                SeverityDot(severity: severity)
            }
            .frame(width: 90)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(severity.stripeColor)
                .frame(width: 3)
                .opacity(isSelected ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.rvRowSelected }
        if isHovered { return Color.primary.opacity(0.06) }
        return .clear
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Application group action sheet

struct ApplicationGroupSheet: View {
    let group: ApplicationGroup
    @Environment(\.dismiss) private var dismiss
    @State private var pending: (kind: Action.Kind, preflight: PreflightResult)?
    @State private var isExecuting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            groupHeader
            Divider()
            if let (_, preflight) = pending {
                PreflightView(result: preflight)
                Divider()
                confirmButtons(preflight: preflight)
            } else {
                actionMenu
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var groupHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let icon = group.icon {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 22, height: 22)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(group.displayName).font(.headline)
                        if group.isReeve {
                            Text("(this app)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("\(group.processes.count) processes  ·  \(group.formattedMemory)  ·  \(group.formattedCPU)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            // Enumerate every PID upfront — mutation semantics require "which process, what will change"
            Text(group.processes.map { "\($0.name) (\($0.pid))" }.joined(separator: "  ·  "))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionMenu: some View {
        VStack(spacing: 8) {
            groupButton("Force Kill All", kind: .kill)
            groupButton("Suspend All", kind: .suspend)
            groupButton("Resume All", kind: .resume)
            groupButton("Lower Priority", kind: .renice(10))
            Button("Cancel") { dismiss() }.buttonStyle(.plain).font(.caption)
        }
    }

    private func groupButton(_ label: String, kind: Action.Kind) -> some View {
        Button(label) {
            pending = (kind, makePreflight(kind: kind))
            error = nil
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
        .help(kind.helpText)
    }

    private func makePreflight(kind: Action.Kind) -> PreflightResult {
        let count = group.processes.count
        let pidList = group.processes.map { "\($0.name) (PID \($0.pid))" }.joined(separator: ", ")
        let isReversible: Bool
        let effectDesc: String
        switch kind {
        case .kill:
            isReversible = false
            effectDesc = "Immediately terminates all \(count) processes — cannot be undone"
        case .terminate:
            isReversible = false
            effectDesc = "Sends SIGTERM to all \(count) processes; escalates to SIGKILL after 3s"
        case .terminateGracefully(let grace):
            isReversible = false
            effectDesc = "Sends SIGTERM to all \(count) processes; escalates to SIGKILL after \(Int(grace))s"
        case .suspend:
            isReversible = true
            effectDesc = "Pauses all \(count) processes; memory remains reserved"
        case .resume:
            isReversible = true
            effectDesc = "Resumes all \(count) paused processes; re-suspend at any time"
        case .renice(let v):
            isReversible = true
            effectDesc = "Lowers scheduling priority (nice +\(v)) for all \(count) processes"
        }
        return PreflightResult(
            description: "\(kind.shortName) → \(group.displayName) (\(count) processes):\n\(pidList)",
            isReversible: isReversible,
            effect: .known(effectDesc),
            warnings: group.isReeve ? ["This will affect Reeve itself"] : []
        )
    }

    private func confirmButtons(preflight: PreflightResult) -> some View {
        HStack {
            Button("Back") { pending = nil }
            Spacer()
            Button(preflight.isReversible ? "Proceed" : "Proceed — cannot undo") {
                guard let (kind, _) = pending else { return }
                isExecuting = true
                Task {
                    for process in group.processes {
                        try? await Action(target: process, kind: kind).execute()
                    }
                    isExecuting = false
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(preflight.isReversible ? .accentColor : .red)
            .disabled(isExecuting)
        }
    }
}
