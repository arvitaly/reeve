import Foundation

/// An automatic rule that fires an `Action` whenever its condition holds in a snapshot.
///
/// Rules are evaluated after every poll. A cooldown prevents thrashing when a condition
/// persists across multiple consecutive snapshots.
public struct Rule: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    /// Returns `true` for every `ProcessRecord` this rule should act on.
    public let condition: @Sendable (ProcessRecord) -> Bool
    /// Produces the `Action` to run when the condition is met.
    public let makeAction: @Sendable (ProcessRecord) -> Action
    /// Minimum time between firings for the same PID.
    public let cooldown: Duration

    public init(
        id: UUID = UUID(),
        name: String,
        cooldown: Duration = .seconds(60),
        condition: @Sendable @escaping (ProcessRecord) -> Bool,
        makeAction: @Sendable @escaping (ProcessRecord) -> Action
    ) {
        self.id = id
        self.name = name
        self.cooldown = cooldown
        self.condition = condition
        self.makeAction = makeAction
    }
}

/// A record of a rule firing: which rule, which action, and the preflight analysis at that moment.
public struct ActionLogEntry: Identifiable, Sendable {
    public let id: UUID
    public let ruleName: String
    public let action: Action
    public let preflight: PreflightResult
    /// Wall-clock time when the rule fired and this entry was created.
    public let firedAt: Date

    public init(ruleName: String, action: Action, preflight: PreflightResult) {
        self.id = UUID()
        self.ruleName = ruleName
        self.action = action
        self.preflight = preflight
        self.firedAt = .now
    }
}
