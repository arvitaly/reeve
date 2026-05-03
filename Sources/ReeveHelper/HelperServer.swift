import Darwin
import Foundation
import OSLog
import ReeveKit

/// Routes JSON-encoded HelperRequest payloads to the right kernel-side handler.
/// Phase 1A handles `.ping`; `.kernelZones` and `.regionsForPID(s)` arrive in
/// the next files (KernelZones.swift, RegionWalker.swift).
final class HelperServer: NSObject, HelperWire {
    private let log = Logger(subsystem: "com.reeve.helper", category: "server")

    func handle(_ payload: Data, reply: @escaping (Data?, NSError?) -> Void) {
        do {
            let request = try HelperEnvelope.decodeRequest(payload)
            DebugLog.line("server: request \(request)")
            let response = process(request)
            DebugLog.line("server: replied with \(String(describing: response).prefix(120))")
            let encoded = try HelperEnvelope.encode(response)
            reply(encoded, nil)
        } catch {
            log.error("decode/encode failed: \(error.localizedDescription)")
            DebugLog.line("server: decode/encode error \(error.localizedDescription)")
            reply(nil, error as NSError)
        }
    }

    private func process(_ request: HelperRequest) -> HelperResponse {
        switch request {
        case .ping:
            return .pong(version: HelperProtocolVersion.current,
                         pidOfHelper: getpid())
        case .kernelZones:
            return KernelZones.snapshot()
        case .regionsForPID(let pid):
            let summaries = RegionWalker.summaries(for: [pid])
            return .regions(summaries)
        case .regionsForPIDs(let pids):
            let summaries = RegionWalker.summaries(for: pids)
            return .regions(summaries)
        }
    }
}
