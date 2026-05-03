import Foundation
#if canImport(ServiceManagement)
import ServiceManagement
#endif

/// Wraps `SMAppService.daemon(plistName:)` with a small Reeve-shaped state
/// machine. `register()` is the only privileged operation — it triggers
/// macOS's authorization sheet and returns the new status. `unregister()`
/// removes the daemon registration; the helper is a single binary embedded
/// in the .app, so uninstalling Reeve removes the helper.
public final class HelperLifecycle: @unchecked Sendable {
    public enum State: Sendable, Equatable {
        case unsupported           // macOS too old or APIs unavailable
        case notRegistered
        case enabled               // running
        case requiresApproval      // user must allow in System Settings
        case notFound              // daemon plist invalid or removed
        case unknown
    }

    public static let shared = HelperLifecycle()

    private let plistName = HelperConstants.plistName

    public var state: State {
        #if canImport(ServiceManagement)
        guard #available(macOS 13.0, *) else { return .unsupported }
        let svc = SMAppService.daemon(plistName: plistName)
        return Self.map(svc.status)
        #else
        return .unsupported
        #endif
    }

    @discardableResult
    public func register() throws -> State {
        #if canImport(ServiceManagement)
        guard #available(macOS 13.0, *) else { throw HelperError.macError(message: "ServiceManagement requires macOS 13+") }
        let svc = SMAppService.daemon(plistName: plistName)
        try svc.register()
        return Self.map(svc.status)
        #else
        throw HelperError.macError(message: "ServiceManagement not available")
        #endif
    }

    @discardableResult
    public func unregister() async throws -> State {
        #if canImport(ServiceManagement)
        guard #available(macOS 13.0, *) else { return .unsupported }
        let svc = SMAppService.daemon(plistName: plistName)
        try await svc.unregister()
        return Self.map(svc.status)
        #else
        return .unsupported
        #endif
    }

    public func openLoginItemsSettings() {
        #if canImport(ServiceManagement)
        guard #available(macOS 13.0, *) else { return }
        SMAppService.openSystemSettingsLoginItems()
        #endif
    }

    #if canImport(ServiceManagement)
    @available(macOS 13.0, *)
    private static func map(_ status: SMAppService.Status) -> State {
        switch status {
        case .notRegistered:    return .notRegistered
        case .enabled:          return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound:         return .notFound
        @unknown default:       return .unknown
        }
    }
    #endif
}
