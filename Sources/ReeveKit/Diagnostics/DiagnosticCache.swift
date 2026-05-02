import Foundation

public actor DiagnosticCache {
    private struct Entry {
        let findings: [Finding]
        let sampledAt: ContinuousClock.Instant
    }

    private var store: [String: Entry] = [:]
    private let ttl: Duration

    public init(ttl: Duration = .seconds(30)) {
        self.ttl = ttl
    }

    public func get(key: String, probeID: String) -> [Finding]? {
        let k = "\(key):\(probeID)"
        guard let entry = store[k] else { return nil }
        let age = entry.sampledAt.duration(to: .now)
        guard age < ttl else {
            return nil
        }
        return entry.findings
    }

    public func set(key: String, probeID: String, findings: [Finding]) {
        store["\(key):\(probeID)"] = Entry(findings: findings, sampledAt: .now)
    }

    public func evictStale() {
        let now = ContinuousClock.now
        store = store.filter { now - $0.value.sampledAt < ttl }
    }
}
