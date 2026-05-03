import Darwin
import Foundation

/// Wire protocol shared between Reeve.app and com.reeve.helper.
///
/// Codable across an NSXPC connection. The helper uses one method —
/// `handle(_ payload: Data, reply:)` — and JSON-encodes both directions.
/// One method is intentional: smaller audit surface than a typed
/// `NSXPCInterface` with many selectors.
public enum HelperProtocolVersion {
    public static let current: UInt32 = 1
}

/// Mach service name used by both sides. Matches the LaunchDaemon plist Label.
public enum HelperConstants {
    public static let machServiceName = "com.reeve.helper"
    public static let plistName = "com.reeve.helper.plist"
}

/// Requests sent from Reeve.app to the helper.
public enum HelperRequest: Codable, Sendable {
    case ping
    case kernelZones
    case regionsForPID(pid_t)
    case regionsForPIDs([pid_t])
}

/// Responses sent from the helper to Reeve.app.
public enum HelperResponse: Codable, Sendable {
    case pong(version: UInt32, pidOfHelper: pid_t)
    case kernelZones(KernelZoneSnapshot)
    case regions([PIDRegionSummary])
    case error(HelperError)
}

/// Snapshot of mach_memory_info kernel zones.
public struct KernelZoneSnapshot: Codable, Sendable {
    public let totalAllocatedBytes: UInt64
    public let totalFreeBytes: UInt64
    public let topZones: [ZoneEntry]
    public let sampledAt: Date

    public init(totalAllocatedBytes: UInt64, totalFreeBytes: UInt64,
                topZones: [ZoneEntry], sampledAt: Date) {
        self.totalAllocatedBytes = totalAllocatedBytes
        self.totalFreeBytes = totalFreeBytes
        self.topZones = topZones
        self.sampledAt = sampledAt
    }
}

public struct ZoneEntry: Codable, Sendable {
    public let name: String
    public let allocatedBytes: UInt64
    public let elementCount: UInt64

    public init(name: String, allocatedBytes: UInt64, elementCount: UInt64) {
        self.name = name
        self.allocatedBytes = allocatedBytes
        self.elementCount = elementCount
    }
}

/// VM region breakdown for one process, walked via `mach_vm_region_recurse_64`.
public struct PIDRegionSummary: Codable, Sendable {
    public let pid: pid_t
    public let physFootprint: UInt64
    public let buckets: [RegionBucket]
    public let sharedAnonBytes: UInt64
    public let pageTableBytes: UInt64
    /// True when SIP-protected or otherwise denied even for root — honest absence.
    public let unavailable: Bool

    public init(pid: pid_t, physFootprint: UInt64, buckets: [RegionBucket],
                sharedAnonBytes: UInt64, pageTableBytes: UInt64, unavailable: Bool) {
        self.pid = pid
        self.physFootprint = physFootprint
        self.buckets = buckets
        self.sharedAnonBytes = sharedAnonBytes
        self.pageTableBytes = pageTableBytes
        self.unavailable = unavailable
    }
}

public struct RegionBucket: Codable, Sendable {
    public let tag: UInt32
    public let label: String
    public let residentBytes: UInt64
    public let dirtyBytes: UInt64
    public let swappedBytes: UInt64

    public init(tag: UInt32, label: String, residentBytes: UInt64,
                dirtyBytes: UInt64, swappedBytes: UInt64) {
        self.tag = tag
        self.label = label
        self.residentBytes = residentBytes
        self.dirtyBytes = dirtyBytes
        self.swappedBytes = swappedBytes
    }
}

public enum HelperError: Codable, Sendable, Error {
    case notAuthorized
    case taskForPIDFailed(pid: pid_t, kr: Int32)
    case macError(message: String)
    case versionMismatch(helperVersion: UInt32, clientVersion: UInt32)
    case sipProtected(pid_t)
}

/// The single Objective-C method the NSXPC listener exports.
/// One method = small audit surface; the wire body is JSON-encoded
/// `HelperRequest` / `HelperResponse`. Declared here once so both the
/// helper executable and Reeve.app see the SAME runtime ObjC class —
/// otherwise NSXPCInterface(with:) resolves to different classes on
/// each side and proxies fail at runtime.
@objc public protocol HelperWire {
    func handle(_ payload: Data, reply: @escaping (Data?, NSError?) -> Void)
}

/// JSON encode/decode helpers used on both sides of the wire.
public enum HelperEnvelope {
    public static func encode(_ request: HelperRequest) throws -> Data {
        try JSONEncoder().encode(request)
    }

    public static func decodeRequest(_ data: Data) throws -> HelperRequest {
        try JSONDecoder().decode(HelperRequest.self, from: data)
    }

    public static func encode(_ response: HelperResponse) throws -> Data {
        try JSONEncoder().encode(response)
    }

    public static func decodeResponse(_ data: Data) throws -> HelperResponse {
        try JSONDecoder().decode(HelperResponse.self, from: data)
    }
}
