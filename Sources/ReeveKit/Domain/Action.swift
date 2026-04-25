import Darwin
import Foundation

public enum EstimatedEffect: Sendable {
    case known(String)
    // Every unknown effect must name the reason.
    // "unknown" without explanation is not a valid state.
    case unknown(reason: String)
}

public struct PreflightResult: Sendable {
    public let description: String
    public let isReversible: Bool
    public let effect: EstimatedEffect
    public let warnings: [String]
}

public enum ActionError: Error, Sendable {
    case processGone
    case permissionDenied
    case systemError(Int32)
}

public struct Action: Sendable {
    public let target: ProcessRecord
    public let kind: Kind

    public enum Kind: Sendable {
        case terminate          // SIGTERM → SIGKILL after 3s, irreversible
        case kill               // SIGKILL immediately, irreversible
        case renice(Int32)      // change nice value, reversible
        case suspend            // SIGSTOP, reversible
        case resume             // SIGCONT, one-directional
    }

    public init(target: ProcessRecord, kind: Kind) {
        self.target = target
        self.kind = kind
    }

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
                isReversible: false,
                effect: .known("Process resumes from point of suspension"),
                warnings: []
            )
        }
    }

    public func execute() async throws {
        guard kill(target.pid, 0) == 0 else {
            throw ActionError.processGone
        }
        switch kind {
        case .terminate:
            kill(target.pid, SIGTERM)
            try await Task.sleep(for: .seconds(3))
            if kill(target.pid, 0) == 0 {
                kill(target.pid, SIGKILL)
            }

        case .kill:
            guard kill(target.pid, SIGKILL) == 0 else {
                throw Darwin.errno == EPERM ? ActionError.permissionDenied : ActionError.systemError(Darwin.errno)
            }

        case .renice(let priority):
            guard setpriority(PRIO_PROCESS, UInt32(target.pid), priority) == 0 else {
                throw Darwin.errno == EPERM ? ActionError.permissionDenied : ActionError.systemError(Darwin.errno)
            }

        case .suspend:
            kill(target.pid, SIGSTOP)

        case .resume:
            kill(target.pid, SIGCONT)
        }
    }
}
