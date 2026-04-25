import Foundation

/// A serialisable description of a user-configured rule.
///
/// `RuleSpec` is the persistent form; call `toRule()` to produce the live `Rule`
/// that the engine evaluates. Storing specs separately from closures lets us
/// save/load rules without going through `NSKeyedArchiver` or similar machinery.
public struct RuleSpec: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var condition: ConditionKind
    public var action: ActionKind
    public var cooldownSeconds: Double
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String = "",
        condition: ConditionKind = .cpuAbove(50),
        action: ActionKind = .suspend,
        cooldownSeconds: Double = 60,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.condition = condition
        self.action = action
        self.cooldownSeconds = cooldownSeconds
        self.isEnabled = isEnabled
    }

    // MARK: - Condition

    public enum ConditionKind: Codable, Sendable, Hashable {
        case cpuAbove(Double)             // percent 0–100
        case memoryAboveGB(Double)        // gigabytes
        case diskWriteAboveMBps(Double)   // megabytes per second
        case nameContains(String)

        public func matches(_ record: ProcessRecord) -> Bool {
            switch self {
            case .cpuAbove(let pct):
                return record.cpuPercent > pct
            case .memoryAboveGB(let gb):
                return record.residentMemory > UInt64(gb * 1_073_741_824)
            case .diskWriteAboveMBps(let mbps):
                return record.diskWriteRate > UInt64(mbps * 1_048_576)
            case .nameContains(let query):
                return record.name.localizedCaseInsensitiveContains(query)
            }
        }

        public var displayName: String {
            switch self {
            case .cpuAbove(let pct):
                return "CPU > \(Int(pct))%"
            case .memoryAboveGB(let gb):
                return String(format: "Memory > %.1f GB", gb)
            case .diskWriteAboveMBps(let mbps):
                return String(format: "Disk write > %.1f MB/s", mbps)
            case .nameContains(let s):
                return "Name contains \"\(s)\""
            }
        }
    }

    // MARK: - Action

    public enum ActionKind: String, Codable, Sendable, Hashable, CaseIterable {
        case terminate
        case kill
        case suspend
        case reniceDown

        public var displayName: String {
            switch self {
            case .terminate:  return "Terminate"
            case .kill:       return "Force Kill"
            case .suspend:    return "Suspend"
            case .reniceDown: return "Lower Priority"
            }
        }

        public func toActionKind() -> Action.Kind {
            switch self {
            case .terminate:  return .terminate
            case .kill:       return .kill
            case .suspend:    return .suspend
            case .reniceDown: return .renice(10)
            }
        }
    }

    // MARK: -

    public func toRule() -> Rule {
        let cond = condition
        let act = action
        return Rule(
            id: id,
            name: name,
            cooldown: .seconds(cooldownSeconds),
            condition: { @Sendable record in cond.matches(record) },
            makeAction: { @Sendable rec in Action(target: rec, kind: act.toActionKind()) }
        )
    }
}
