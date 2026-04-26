import AppKit
import Combine
import Foundation
import ReeveKit

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
    private var cooldowns: [String: ContinuousClock.Instant] = [:]
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
