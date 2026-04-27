import AppKit
import Combine
import Darwin
import Foundation
import ReeveKit

// MARK: - Memory pressure policy

/// A single global policy: when system memory exceeds a threshold,
/// kill apps from the ordered list one at a time with a cooldown between kills.
struct MemoryPressurePolicy: Codable {
    var isEnabled: Bool = false
    var thresholdGB: Double = 14.0
    var killList: [String] = []      // case-insensitive app name patterns, priority order
    var cooldownSeconds: Double = 30
    var warnBeforeKill: Bool = false  // SIGTERM first, SIGKILL after graceSeconds if still alive
    var graceSeconds: Double = 10
}

// MARK: - Spec

struct GroupRuleSpec: Identifiable, Codable {
    var id: UUID
    var appNamePattern: String          // case-insensitive contains match on ApplicationGroup.displayName
    var condition: ConditionKind
    var action: ActionKind
    var cooldownSeconds: Double
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        appNamePattern: String = "",
        condition: ConditionKind = .totalMemoryAboveGB(2.0),
        action: ActionKind = .reniceDown,
        cooldownSeconds: Double = 60,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.appNamePattern = appNamePattern
        self.condition = condition
        self.action = action
        self.cooldownSeconds = cooldownSeconds
        self.isEnabled = isEnabled
    }

    enum ConditionKind: Codable, Hashable {
        case totalMemoryAboveGB(Double)
        case totalCPUAbove(Double)

        var displayName: String {
            switch self {
            case .totalMemoryAboveGB(let gb): return String(format: "Total mem > %.1f GB", gb)
            case .totalCPUAbove(let pct):     return "Total CPU > \(Int(pct))%"
            }
        }

        func matches(_ group: ApplicationGroup) -> Bool {
            switch self {
            case .totalMemoryAboveGB(let gb): return group.totalMemory > UInt64(gb * 1_073_741_824)
            case .totalCPUAbove(let pct):     return group.totalCPU > pct
            }
        }
    }

    enum ActionKind: String, Codable, CaseIterable {
        case terminate, kill, suspend, resume, reniceDown

        var displayName: String {
            switch self {
            case .terminate:  return "Terminate"
            case .kill:       return "Force Kill"
            case .suspend:    return "Suspend"
            case .resume:     return "Resume"
            case .reniceDown: return "Lower Priority"
            }
        }

        func toActionKind() -> Action.Kind {
            switch self {
            case .terminate:  return .terminate
            case .kill:       return .kill
            case .suspend:    return .suspend
            case .resume:     return .resume
            case .reniceDown: return .renice(10)
            }
        }
    }
}

// MARK: - Log entry

struct GroupActionLogEntry: Identifiable {
    let id: UUID
    let appName: String
    let conditionDescription: String
    let actionName: String
    let processCount: Int
    let firedAt: Date

    init(appName: String, conditionDescription: String, actionName: String, processCount: Int) {
        self.id = UUID()
        self.appName = appName
        self.conditionDescription = conditionDescription
        self.actionName = actionName
        self.processCount = processCount
        self.firedAt = .now
    }
}

// MARK: - Engine

@MainActor
final class GroupRuleEngine: ObservableObject {
    @Published private(set) var actionLog: [GroupActionLogEntry] = []
    @Published private(set) var groupMemHistory: [String: [Double]] = [:]   // GB, 30-sample rolling
    @Published private(set) var systemMemHistory: [Double] = []             // GB, 30-sample rolling
    @Published private(set) var systemCPUHistory: [Double] = []             // percent, 30-sample rolling

    var specs: [GroupRuleSpec] = []
    var pressurePolicy = MemoryPressurePolicy()
    private var cooldowns: [String: ContinuousClock.Instant] = [:]
    private var pressureCooldownUntil: ContinuousClock.Instant?
    // Group displayNames already killed this pressure episode; reset when memory drops.
    private var pressureKilledGroups: Set<String> = []
    private var cancellable: AnyCancellable?

    static let historyCapacity = 30

    func clearLog() { actionLog = [] }

    func connect(to engine: MonitoringEngine) {
        cancellable = engine.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in self?.evaluate(snapshot: snapshot) }
    }

    private func evaluate(snapshot: SystemSnapshot) {
        let (groups, _) = buildApplicationGroups(snapshot: snapshot)
        updateHistory(groups: groups, snapshot: snapshot)
        let now = ContinuousClock.now
        for spec in specs where spec.isEnabled && !spec.appNamePattern.trimmingCharacters(in: .whitespaces).isEmpty {
            for group in groups {
                guard group.displayName.localizedCaseInsensitiveContains(spec.appNamePattern) else { continue }
                guard spec.condition.matches(group) else { continue }
                let key = "\(spec.id)-\(group.id)"
                if let last = cooldowns[key], last.duration(to: now) < .seconds(spec.cooldownSeconds) { continue }
                cooldowns[key] = now
                let processes = group.processes
                let kind = spec.action.toActionKind()
                Task.detached { for p in processes { try? await Action(target: p, kind: kind).execute() } }
                actionLog.append(GroupActionLogEntry(
                    appName: group.displayName,
                    conditionDescription: spec.condition.displayName,
                    actionName: spec.action.displayName,
                    processCount: processes.count
                ))
            }
        }
        evaluatePressurePolicy(groups: groups, snapshot: snapshot, now: now)
    }

    private func evaluatePressurePolicy(groups: [ApplicationGroup], snapshot: SystemSnapshot, now: ContinuousClock.Instant) {
        guard pressurePolicy.isEnabled,
              !pressurePolicy.killList.isEmpty,
              let usedMemory = snapshot.usedMemory else { return }
        let usedGB = Double(usedMemory) / 1_073_741_824
        guard usedGB > pressurePolicy.thresholdGB else {
            pressureCooldownUntil = nil
            pressureKilledGroups = []
            return
        }
        if let until = pressureCooldownUntil, now < until { return }
        for pattern in pressurePolicy.killList {
            guard let group = groups.first(where: {
                $0.displayName.localizedCaseInsensitiveContains(pattern) &&
                !pressureKilledGroups.contains($0.displayName)
            }) else { continue }
            let pids = group.processes.map { $0.pid }
            let warn = pressurePolicy.warnBeforeKill
            let grace = pressurePolicy.graceSeconds
            Task.detached {
                if warn {
                    for pid in pids { Darwin.kill(pid, SIGTERM) }
                    try? await Task.sleep(for: .seconds(grace))
                    for pid in pids where Darwin.kill(pid, 0) == 0 { Darwin.kill(pid, SIGKILL) }
                } else {
                    for pid in pids { Darwin.kill(pid, SIGKILL) }
                }
            }
            pressureKilledGroups.insert(group.displayName)
            pressureCooldownUntil = now + .seconds(pressurePolicy.cooldownSeconds)
            let actionName = warn
                ? String(format: "Terminate (%.0fs grace)", grace)
                : "Force Kill"
            actionLog.append(GroupActionLogEntry(
                appName: group.displayName,
                conditionDescription: String(format: "System %.1f GB > %.1f GB", usedGB, pressurePolicy.thresholdGB),
                actionName: actionName,
                processCount: group.processes.count
            ))
            return
        }
    }

    private func updateHistory(groups: [ApplicationGroup], snapshot: SystemSnapshot) {
        var updated = groupMemHistory
        let seen = Set(groups.map { $0.displayName })
        for group in groups {
            let gb = Double(group.totalMemory) / 1_073_741_824
            var buf = updated[group.displayName, default: []]
            buf.append(gb)
            if buf.count > Self.historyCapacity { buf.removeFirst(buf.count - Self.historyCapacity) }
            updated[group.displayName] = buf
        }
        for key in updated.keys where !seen.contains(key) { updated.removeValue(forKey: key) }
        groupMemHistory = updated

        if let usedMem = snapshot.usedMemory {
            var buf = systemMemHistory
            buf.append(Double(usedMem) / 1_073_741_824)
            if buf.count > Self.historyCapacity { buf.removeFirst(buf.count - Self.historyCapacity) }
            systemMemHistory = buf
        }

        var cpuBuf = systemCPUHistory
        cpuBuf.append(snapshot.totalCPU)
        if cpuBuf.count > Self.historyCapacity { cpuBuf.removeFirst(cpuBuf.count - Self.historyCapacity) }
        systemCPUHistory = cpuBuf
    }
}
