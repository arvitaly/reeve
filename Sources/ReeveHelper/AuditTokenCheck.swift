import Foundation
import Security

/// Validates that an incoming `NSXPCConnection` was opened by a binary
/// matching a fixed code-signing requirement: Apple-issued cert chain,
/// pinned to our Team ID and the Reeve.app bundle identifier.
///
/// In debug builds (`#if DEBUG`) the check is bypassed so the helper can be
/// run unsigned during development. Release builds always enforce.
enum AuditTokenCheck {
    /// Bundle identifier the connecting client must present.
    private static let clientBundleIdentifier = "com.reeve.app"

    /// Apple Team ID. Substituted at release sign time. The empty default
    /// causes release builds to fail the requirement and reject everyone —
    /// intentional. Set via `-Xswiftc -DREEVE_TEAM_ID=...` in the Makefile
    /// or by editing this constant before signing.
    #if REEVE_TEAM_ID
    private static let teamID = String(describing: REEVE_TEAM_ID)
    #else
    private static let teamID = ""
    #endif

    static func validate(connection: NSXPCConnection) -> Bool {
        #if DEBUG
        return true
        #else
        guard !teamID.isEmpty else { return false }

        // The audit token is exposed via KVC on macOS 13+; the Swift property
        // is unavailable in some SDKs.
        guard let token = (connection.value(forKey: "auditToken") as? NSData)?.auditToken else {
            return false
        }

        let attrs: [CFString: Any] = [
            kSecGuestAttributeAudit: token as Any
        ]

        var guestCode: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attrs as CFDictionary, [], &guestCode) == errSecSuccess,
              let code = guestCode else {
            return false
        }

        let requirement = """
        anchor apple generic \
        and certificate leaf[subject.OU] = "\(teamID)" \
        and identifier "\(clientBundleIdentifier)"
        """

        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess,
              let requirementValue = req else {
            return false
        }

        let result = SecCodeCheckValidity(code, [], requirementValue)
        return result == errSecSuccess
        #endif
    }
}

private extension NSData {
    /// Reinterprets the first sizeof(audit_token_t) bytes as audit_token_t.
    /// Apple's macOS 13/14 KVC path returns the token as NSData; on newer SDKs
    /// the same accessor returns the typed `audit_token_t` directly.
    var auditToken: audit_token_t? {
        guard length >= MemoryLayout<audit_token_t>.size else { return nil }
        var token = audit_token_t()
        getBytes(&token, length: MemoryLayout<audit_token_t>.size)
        return token
    }
}
