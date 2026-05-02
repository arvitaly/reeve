import Foundation

public struct Remediation: Sendable {
    public let kind: Kind
    public let title: String
    public let detail: String

    public enum Kind: Sendable {
        case reveal(path: String)
        case clear(path: String, label: String)
        case move(from: String, to: String)
        case openSettings(urlString: String)
        case reduceProcesses(hint: String)
    }

    public init(kind: Kind, title: String, detail: String) {
        self.kind = kind
        self.title = title
        self.detail = detail
    }

    public func preflight() -> PreflightResult {
        switch kind {
        case .reveal(let path):
            return PreflightResult(
                description: "Open Finder at \(path)",
                isReversible: true,
                effect: .known("Opens a Finder window — no files modified"),
                warnings: []
            )
        case .clear(let path, let label):
            return PreflightResult(
                description: "Move \(label) to Trash at \(path)",
                isReversible: false,
                effect: .known("Files moved to Trash — recoverable from Trash until emptied"),
                warnings: ["Contents of \(label) will need to be rebuilt"]
            )
        case .move(let from, let to):
            return PreflightResult(
                description: "Move files from \(from) to \(to)",
                isReversible: true,
                effect: .known("Files relocated — move them back at any time"),
                warnings: []
            )
        case .openSettings(let urlString):
            return PreflightResult(
                description: "Open settings: \(urlString)",
                isReversible: true,
                effect: .known("Opens a settings pane — no changes until you act"),
                warnings: []
            )
        case .reduceProcesses(let hint):
            return PreflightResult(
                description: hint,
                isReversible: true,
                effect: .known("Advisory — no automatic action taken"),
                warnings: []
            )
        }
    }
}
