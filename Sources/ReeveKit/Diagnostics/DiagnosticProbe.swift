import Foundation

public protocol DiagnosticProbe: Sendable {
    var probeID: String { get }
    var displayName: String { get }
    func run(context: ProbeContext) async -> [Finding]
}
