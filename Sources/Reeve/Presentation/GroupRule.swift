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

    var specs: [GroupRuleSpec] = []
    private var cooldowns: [String: ContinuousClock.Instant] = [:]
    private var cancellable: AnyCancellable?

    func clearLog() { actionLog = [] }

    func connect(to engine: MonitoringEngine) {
        cancellable = engine.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in self?.evaluate(snapshot: snapshot) }
    }

    private func evaluate(snapshot: SystemSnapshot) {
        let (groups, _) = buildApplicationGroups(snapshot: snapshot)
        let now = ContinuousClock.now
        for spec in specs where spec.isEnabled {
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
}
