import Foundation
import OSLog
import ReeveKit

/// Listener delegate that validates every incoming connection's audit token
/// against a Developer-ID code requirement before exporting the wire object.
///
/// Recipe (Apple's Privileged Helpers technote): SecCodeCopyGuestWithAttributes
/// with kSecGuestAttributeAudit → SecCodeCheckValidity against a requirement
/// pinned to "anchor apple generic + Team ID + bundle identifier".
final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let log = Logger(subsystem: "com.reeve.helper", category: "listener")

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        guard AuditTokenCheck.validate(connection: conn) else {
            log.error("Rejecting connection from pid \(conn.processIdentifier) — audit token invalid")
            return false
        }

        conn.exportedInterface = NSXPCInterface(with: HelperWire.self)
        conn.exportedObject = HelperServer()
        conn.invalidationHandler = { [log] in
            log.debug("XPC connection invalidated")
        }
        conn.interruptionHandler = { [log] in
            log.debug("XPC connection interrupted")
        }
        conn.resume()
        log.info("Accepted connection from pid \(conn.processIdentifier)")
        return true
    }
}
