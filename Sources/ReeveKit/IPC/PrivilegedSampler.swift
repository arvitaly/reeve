import Foundation
import OSLog

/// App-side XPC client. Opens an `NSXPCConnection` to the privileged helper
/// (`com.reeve.helper` Mach service) and exchanges JSON-encoded
/// `HelperRequest` / `HelperResponse` payloads via the single
/// `HelperWire.handle(_:reply:)` method.
///
/// All calls are off-actor (helper round-trip can take tens of milliseconds
/// for region walks across 300+ processes, and we never want to block the
/// 1Hz polling loop). The actor caches results with a TTL so successive
/// snapshots within the cache window reuse the last response.
public actor PrivilegedSampler {
    public static let shared = PrivilegedSampler()

    private let log = Logger(subsystem: "com.reeve.app", category: "privileged-sampler")
    private var connection: NSXPCConnection?

    private var lastZonesAt: ContinuousClock.Instant = .now - .seconds(120)
    private var cachedZones: KernelZoneSnapshot?
    private var lastRegionsAt: ContinuousClock.Instant = .now - .seconds(120)
    private var cachedRegions: [pid_t: PIDRegionSummary] = [:]
    private let cacheTTL: Duration = .seconds(10)

    private var helperVersion: UInt32?

    public init() {}

    // MARK: - Public surface

    /// Returns the helper's reported version, or nil if unreachable.
    /// Round-trips a `.ping` and caches the version for the connection's
    /// lifetime; reconnect after an invalidation re-pings.
    public func ping() async throws -> UInt32 {
        let resp = try await send(.ping)
        switch resp {
        case .pong(let version, _):
            helperVersion = version
            return version
        case .error(let err):
            throw err
        default:
            throw HelperError.macError(message: "ping: unexpected response")
        }
    }

    public func kernelZones() async throws -> KernelZoneSnapshot {
        if let cached = cachedZones, .now - lastZonesAt < cacheTTL {
            return cached
        }
        let resp = try await send(.kernelZones)
        switch resp {
        case .kernelZones(let snap):
            cachedZones = snap
            lastZonesAt = .now
            return snap
        case .error(let err):
            throw err
        default:
            throw HelperError.macError(message: "kernelZones: unexpected response")
        }
    }

    public func regions(for pids: [pid_t]) async throws -> [pid_t: PIDRegionSummary] {
        if !pids.isEmpty,
           pids.allSatisfy({ cachedRegions[$0] != nil }),
           .now - lastRegionsAt < cacheTTL {
            return cachedRegions.filter { pids.contains($0.key) }
        }
        let resp = try await send(.regionsForPIDs(pids))
        switch resp {
        case .regions(let summaries):
            var map: [pid_t: PIDRegionSummary] = [:]
            for s in summaries { map[s.pid] = s }
            cachedRegions = map
            lastRegionsAt = .now
            return map
        case .error(let err):
            throw err
        default:
            throw HelperError.macError(message: "regions: unexpected response")
        }
    }

    /// Tear down the connection. Subsequent calls reopen lazily.
    public func disconnect() {
        connection?.invalidate()
        connection = nil
        cachedZones = nil
        cachedRegions = [:]
        helperVersion = nil
    }

    // MARK: - Wire

    private func send(_ request: HelperRequest) async throws -> HelperResponse {
        let conn = ensureConnection()
        let proxy = conn.remoteObjectProxyWithErrorHandler { [log] err in
            log.error("XPC error: \(err.localizedDescription)")
        } as? HelperWire

        guard let proxy else {
            throw HelperError.macError(message: "remoteObjectProxy nil")
        }

        let payload = try HelperEnvelope.encode(request)

        return try await withCheckedThrowingContinuation { continuation in
            proxy.handle(payload) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data else {
                    continuation.resume(throwing: HelperError.macError(message: "empty XPC reply"))
                    return
                }
                do {
                    let resp = try HelperEnvelope.decodeResponse(data)
                    continuation.resume(returning: resp)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func ensureConnection() -> NSXPCConnection {
        if let conn = connection { return conn }
        let conn = NSXPCConnection(machServiceName: HelperConstants.machServiceName,
                                   options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: HelperWire.self)
        conn.invalidationHandler = { [weak self] in
            Task { await self?.handleInvalidation() }
        }
        conn.interruptionHandler = { [weak self] in
            Task { await self?.handleInterruption() }
        }
        conn.resume()
        connection = conn
        return conn
    }

    private func handleInvalidation() {
        log.info("XPC connection invalidated")
        connection = nil
        cachedZones = nil
        cachedRegions = [:]
        helperVersion = nil
    }

    private func handleInterruption() {
        log.info("XPC connection interrupted; will reconnect on next call")
        // Don't tear down — the OS will reopen for us.
    }
}

extension HelperError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Helper rejected the connection — code-signing requirement not met."
        case .taskForPIDFailed(let pid, let kr):
            return "task_for_pid(\(pid)) failed (kr=\(kr))."
        case .macError(let message):
            return message
        case .versionMismatch(let helperVersion, let clientVersion):
            return "Helper version \(helperVersion) does not match client version \(clientVersion)."
        case .sipProtected(let pid):
            return "PID \(pid) is SIP-protected; even root cannot probe it."
        }
    }
}
