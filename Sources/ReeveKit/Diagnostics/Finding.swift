import Foundation

public struct Finding: Sendable, Identifiable {
    public let id: UUID
    public let cause: String
    public let evidence: String
    public let severity: Confidence
    public let suggestedRemediation: Remediation?

    public enum Confidence: Comparable, Sendable {
        case info
        case advisory
        case actionable
    }

    public init(
        id: UUID = UUID(),
        cause: String, evidence: String,
        severity: Confidence,
        suggestedRemediation: Remediation? = nil
    ) {
        self.id = id
        self.cause = cause
        self.evidence = evidence
        self.severity = severity
        self.suggestedRemediation = suggestedRemediation
    }
}
