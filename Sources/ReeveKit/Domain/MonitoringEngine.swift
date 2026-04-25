import Combine
import Foundation

/// The central coordinator: polls the process list, evaluates rules, and publishes state.
///
/// The engine starts polling automatically on `init`. The presentation layer adjusts the
/// poll interval by setting `windowVisible`: 1 second when the window is open, 5 seconds
/// when it is closed. This keeps the menu responsive when visible without burning CPU
/// while the user is doing other work.
///
/// Rules run after every snapshot. Preflight is always logged; the action fires in a
/// detached task so rule evaluation never blocks the poll loop.
@MainActor
public final class MonitoringEngine: ObservableObject {
    /// The most recently collected process snapshot.
    @Published public private(set) var snapshot: SystemSnapshot = .empty
    /// An append-only log of every rule that fired, in order.
    @Published public private(set) var actionLog: [ActionLogEntry] = []

    /// Rules evaluated against every snapshot. Set before calling `start()`.
    public var rules: [Rule] = []
    // Presentation layer sets this to adjust poll frequency.
    public var windowVisible = false

    private let sampler = ProcessSampler()
    private var pollingTask: Task<Void, Never>?
    private var isStarted = false
    // Cooldown tracking: rule.id → [pid → last fired time]
    private var cooldowns: [UUID: [pid_t: ContinuousClock.Instant]] = [:]

    /// Creates the engine and, by default, starts polling immediately.
    /// - Parameter autoStart: Pass `false` in tests to drive polling manually.
    public init(autoStart: Bool = true) {
        if autoStart { self.start() }
    }

    /// Begins the polling loop if it is not already running. Safe to call multiple times.
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

    /// Cancels the polling loop. After `stop()`, call `start()` to resume.
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
