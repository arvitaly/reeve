import Combine
import Foundation

@MainActor
public final class MonitoringEngine: ObservableObject {
    @Published public private(set) var snapshot: SystemSnapshot = .empty
    @Published public private(set) var actionLog: [ActionLogEntry] = []

    public var rules: [Rule] = []
    // Presentation layer sets this to adjust poll frequency.
    public var windowVisible = false

    private let sampler = ProcessSampler()
    private var pollingTask: Task<Void, Never>?
    private var isStarted = false
    // Cooldown tracking: rule.id → [pid → last fired time]
    private var cooldowns: [UUID: [pid_t: ContinuousClock.Instant]] = [:]

    public init() {}

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let s = await self.sampler.sample()
                self.snapshot = s
                self.evaluateRules(s)
                let interval: Duration = self.windowVisible ? .seconds(1) : .seconds(5)
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        isStarted = false
    }

    private func evaluateRules(_ snapshot: SystemSnapshot) {
        let now = ContinuousClock.now
        for rule in rules {
            for process in snapshot.processes where rule.condition(process) {
                if let lastFired = cooldowns[rule.id]?[process.pid],
                   lastFired.duration(to: now) < rule.cooldown {
                    continue
                }
                let action = rule.makeAction(process)
                let result = action.preflight()
                // Preflight always runs and is logged.
                // Warnings do not block auto-rule execution — the user who
                // created the rule accepted its consequences.
                actionLog.append(ActionLogEntry(ruleName: rule.name, action: action, preflight: result))
                Task.detached { try? await action.execute() }
                cooldowns[rule.id, default: [:]][process.pid] = now
            }
        }
    }
}
