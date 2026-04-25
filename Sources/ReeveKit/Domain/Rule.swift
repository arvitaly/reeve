import Foundation

public struct Rule: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let condition: @Sendable (ProcessRecord) -> Bool
    public let makeAction: @Sendable (ProcessRecord) -> Action
    // Minimum time between firings for the same PID.
    // Prevents thrashing when a rule fires on consecutive snapshots.
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

public struct ActionLogEntry: Identifiable, Sendable {
    public let id: UUID
    public let ruleName: String
    public let action: Action
    public let preflight: PreflightResult
    public let firedAt: Date

    public init(ruleName: String, action: Action, preflight: PreflightResult) {
        self.id = UUID()
        self.ruleName = ruleName
        self.action = action
        self.preflight = preflight
        self.firedAt = .now
    }
}
