import AppKit
import ReeveKit

@MainActor
enum RemediationExecutor {
    static func execute(_ remediation: Remediation) {
        switch remediation.kind {
        case .reveal(let path):
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.activateFileViewerSelecting([url])

        case .clear(let path, _):
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.recycle([url]) { _, _ in }

        case .move(let from, let to):
            let src = URL(fileURLWithPath: from)
            let dst = URL(fileURLWithPath: to)
            try? FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
            if let items = try? FileManager.default.contentsOfDirectory(at: src, includingPropertiesForKeys: nil) {
                for item in items {
                    try? FileManager.default.moveItem(at: item, to: dst.appendingPathComponent(item.lastPathComponent))
                }
            }

        case .openSettings(let urlString):
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }

        case .reduceProcesses:
            break
        }
    }
}
