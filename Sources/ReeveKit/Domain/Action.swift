import Darwin
import Foundation

/// The expected outcome of an action, from the perspective of observable system state.
///
/// `unknown` is a first-class value, not an error. If the effect cannot be determined
/// in advance, that fact must be stated explicitly with a reason.
public enum EstimatedEffect: Sendable {
    case known(String)
    // Every unknown effect must name the reason.
    // "unknown" without explanation is not a valid state.
    case unknown(reason: String)
}

/// The result of running preflight analysis on an `Action` before execution.
public struct PreflightResult: Sendable {
    /// Human-readable description of exactly what will happen to which process.
    public let description: String
    /// Whether the original state can be fully restored after the action.
    public let isReversible: Bool
    /// The predicted effect on system resources.
    public let effect: EstimatedEffect
    /// Non-fatal conditions the user should be aware of before confirming.
    public let warnings: [String]

    public init(description: String, isReversible: Bool, effect: EstimatedEffect, warnings: [String]) {
        self.description = description
        self.isReversible = isReversible
        self.effect = effect
        self.warnings = warnings
    }
}

/// Errors that can occur during `Action.execute()`.
public enum ActionError: Error, Sendable {
    /// The target process exited before or during execution.
    case processGone
    /// The calling process lacks privilege to perform this action.
    case permissionDenied
    /// An unexpected kernel error (errno value attached).
    case systemError(Int32)
}

/// A single, typed operation on a specific process.
///
/// Preflight is always safe to call; it reads current process state and returns
/// a `PreflightResult` without modifying anything. Call `execute()` only after
/// the user has reviewed and confirmed the preflight.
public struct Action: Sendable {
    public let target: ProcessRecord
    public let kind: Kind

    /// The set of mutations Reeve can perform on a process.
    ///
    /// Reversible actions (``renice(_:)``, ``suspend``) can be undone.
    /// Irreversible actions (``terminate``, ``kill``) cannot.
    public enum Kind: Sendable {
        case terminate          // SIGTERM → SIGKILL after 3s, irreversible
        case kill               // SIGKILL immediately, irreversible
        case renice(Int32)      // change nice value, reversible
        case suspend            // SIGSTOP, reversible
        case resume             // SIGCONT, one-directional

        public var shortName: String {
            switch self {
            case .terminate:      return "Terminate"
            case .kill:           return "Force Kill"
            case .renice(let v):  return v < 0 ? "Raise Priority" : "Lower Priority"
            case .suspend:        return "Suspend"
            case .resume:         return "Resume"
            }
        }

        /// One-sentence tooltip explaining the action and its key consequence.
        public var helpText: String {
            switch self {
            case .terminate:
                return "Sends SIGTERM; escalates to SIGKILL after 3 seconds if the process hasn't quit."
            case .kill:
                return "Sends SIGKILL immediately — cannot be ignored. Use when Terminate fails."
            case .renice(let v) where v < 0:
                return "Raises scheduling priority (nice \(v)). Requires root; may be rejected."
            case .renice(let v):
                return "Lowers scheduling priority (nice +\(v)). Process runs slower when competing for CPU."
            case .suspend:
                return "Pauses the process with SIGSTOP. CPU drops to 0%. Resumable at any time."
            case .resume:
                return "Resumes a paused process with SIGCONT. Safe to send even if already running."
            }
        }
    }

    public init(target: ProcessRecord, kind: Kind) {
        self.target = target
        self.kind = kind
    }

    /// Analyzes what this action will do without performing it.
    ///
    /// Always safe to call. Reads current priority via `getpriority()` for renice;
    /// all other cases use only the information already in `target`.
    public func preflight() -> PreflightResult {
        switch kind {
        case .terminate:
            return PreflightResult(
                description: "Send SIGTERM to \(target.name) (PID \(target.pid)); escalate to SIGKILL after 3s if still running",
                isReversible: false,
                effect: .unknown(reason: "Memory freed depends on OS reclaim decisions after process exits"),
                warnings: target.isReeve ? ["This will terminate Reeve"] : []
            )

        case .kill:
            return PreflightResult(
                description: "Send SIGKILL to \(target.name) (PID \(target.pid))",
                isReversible: false,
                effect: .unknown(reason: "Memory freed depends on OS reclaim decisions after process exits"),
                warnings: target.isReeve ? ["This will terminate Reeve"] : []
            )

        case .renice(let priority):
            let current = getpriority(PRIO_PROCESS, UInt32(target.pid))
            return PreflightResult(
                description: "Change scheduling priority of \(target.name) (PID \(target.pid)) from \(current) to \(priority)",
                isReversible: true,
                effect: .known("Takes effect immediately; revert anytime via renice"),
                warnings: priority < 0 ? ["Negative priority requires elevated permissions"] : []
            )

        case .suspend:
            return PreflightResult(
                description: "Suspend \(target.name) (PID \(target.pid)) with SIGSTOP",
                isReversible: true,
                effect: .known("Process pauses immediately; allocated memory remains reserved"),
                warnings: []
            )

        case .resume:
            return PreflightResult(
                description: "Resume \(target.name) (PID \(target.pid)) with SIGCONT",
                isReversible: true,
                effect: .known("Process resumes from point of suspension; re-suspend at any time"),
                warnings: []
            )
        }
    }

    /// Executes the action against the live process.
    ///
    /// Throws `ActionError.processGone` immediately if the target no longer exists.
    /// For `.terminate`, waits up to 3 seconds after SIGTERM before escalating to SIGKILL.
    public func execute() async throws {
        guard kill(target.pid, 0) == 0 else {
            throw ActionError.processGone
        }
        switch kind {
        case .terminate:
            kill(target.pid, SIGTERM)
            try await Task.sleep(for: .seconds(3))
            // SIGKILL escalation: intentionally untested. Any process that truly ignores SIGTERM
            // at the kernel level (via SIG_IGN) and has no child processes destabilises NSTask's
            // waitpid reaping in the same xctest process, causing subsequent tests to hang.
            // The branch is structurally sound; the gap is a test-harness constraint, not a logic gap.
            if kill(target.pid, 0) == 0 {
                kill(target.pid, SIGKILL)
            }

        case .kill:
            // EPERM path: unreachable without root. kill(root_pid, 0) itself returns EPERM,
            // which the guard above converts to processGone before reaching here.
            guard kill(target.pid, SIGKILL) == 0 else {
                throw Darwin.errno == EPERM ? ActionError.permissionDenied : ActionError.systemError(Darwin.errno)
            }

        case .renice(let priority):
            guard setpriority(PRIO_PROCESS, UInt32(target.pid), priority) == 0 else {
                // setpriority returns EACCES (not EPERM) when non-root tries to lower below 0
                let err = Darwin.errno
                throw (err == EPERM || err == EACCES) ? ActionError.permissionDenied : ActionError.systemError(err)
            }

        case .suspend:
            kill(target.pid, SIGSTOP)

        case .resume:
            kill(target.pid, SIGCONT)
        }
    }
}
