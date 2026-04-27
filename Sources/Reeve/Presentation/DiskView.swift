import AppKit
import SwiftUI
import Foundation

// MARK: - Model

enum SizeState {
    case pending, scanning, absent
    case ready(UInt64)

    var bytes: UInt64? { if case .ready(let b) = self { return b }; return nil }

    var formatted: String {
        switch self {
        case .pending:      return "—"
        case .scanning:     return "…"
        case .absent:       return ""
        case .ready(let b): return ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
        }
    }
}

struct DiskEntry: Identifiable {
    let id = UUID()
    let displayName: String
    let detail: String
    let path: URL
    let category: String
    var sizeState: SizeState = .pending
    var isSelected = true
}

// MARK: - Scanner

@MainActor
final class DiskScanner: ObservableObject {
    @Published var entries: [DiskEntry] = DiskScanner.makeEntries()
    @Published var isScanning = false

    func scan() {
        isScanning = true
        for i in entries.indices { entries[i].sizeState = .scanning }
        Task {
            await withTaskGroup(of: (UUID, SizeState).self) { group in
                for entry in entries {
                    let id = entry.id; let url = entry.path
                    group.addTask {
                        let state = await Task.detached(priority: .utility) {
                            guard FileManager.default.fileExists(atPath: url.path) else { return SizeState.absent }
                            let b = DiskScanner.measure(url)
                            return b > 0 ? .ready(b) : .absent
                        }.value
                        return (id, state)
                    }
                }
                for await (id, state) in group {
                    if let i = entries.firstIndex(where: { $0.id == id }) {
                        entries[i].sizeState = state
                    }
                }
            }
            isScanning = false
        }
    }

    func deleteSelected() {
        let urls = entries.filter { $0.isSelected && $0.sizeState.bytes != nil }.map { $0.path }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.recycle(urls) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.scan() }
        }
    }

    // Uses totalFileAllocatedSizeKey — matches "On disk" in Finder Get Info.
    // APFS clones make totalFileSizeKey (logical) misleading; allocated is honest.
    nonisolated static func measure(_ url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
            .isRegularFileKey, .isSymbolicLinkKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: UInt64 = 0
        for case let file as URL in enumerator {
            guard let v = try? file.resourceValues(forKeys: keys),
                  v.isSymbolicLink != true,
                  v.isRegularFile == true else { continue }
            total += UInt64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func makeEntries() -> [DiskEntry] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let lib  = home.appendingPathComponent("Library")

        return [
            // Developer
            .init(displayName: "Xcode Derived Data",
                  detail: "Build products — fully regenerated on next build",
                  path: lib.appendingPathComponent("Developer/Xcode/DerivedData"),
                  category: "Developer"),
            .init(displayName: "Xcode Cache",
                  detail: "SwiftPM downloads, indexing data",
                  path: lib.appendingPathComponent("Caches/com.apple.dt.Xcode"),
                  category: "Developer"),
            .init(displayName: "Xcode Device Support",
                  detail: "Debug symbols pulled from connected devices",
                  path: lib.appendingPathComponent("Developer/Xcode/iOS DeviceSupport"),
                  category: "Developer"),
            .init(displayName: "Simulator Caches",
                  detail: "Boot and dyld caches; regenerated on next launch",
                  path: lib.appendingPathComponent("Developer/CoreSimulator/Caches"),
                  category: "Developer"),
            // Package managers
            .init(displayName: "Homebrew Downloads",
                  detail: "Cached formula bottles",
                  path: lib.appendingPathComponent("Caches/Homebrew"),
                  category: "Package Managers"),
            .init(displayName: "npm Cache",
                  detail: "Node package tarballs",
                  path: home.appendingPathComponent(".npm/_cacache"),
                  category: "Package Managers"),
            .init(displayName: "Yarn Cache (classic)",
                  detail: "Yarn 1.x package cache",
                  path: lib.appendingPathComponent("Caches/Yarn"),
                  category: "Package Managers"),
            .init(displayName: "Yarn Cache (berry)",
                  detail: "Yarn 2+ package cache",
                  path: home.appendingPathComponent(".yarn/berry/cache"),
                  category: "Package Managers"),
            .init(displayName: "pip Cache",
                  detail: "Python package wheels",
                  path: lib.appendingPathComponent("Caches/pip"),
                  category: "Package Managers"),
            .init(displayName: "pip Cache (XDG)",
                  detail: "Python package wheels (alternate location)",
                  path: home.appendingPathComponent(".cache/pip"),
                  category: "Package Managers"),
            .init(displayName: "CocoaPods Cache",
                  detail: "Cached pod source downloads",
                  path: lib.appendingPathComponent("Caches/CocoaPods"),
                  category: "Package Managers"),
            .init(displayName: "Gradle Cache",
                  detail: "Java/Kotlin build dependencies",
                  path: home.appendingPathComponent(".gradle/caches"),
                  category: "Package Managers"),
            // System caches & logs
            .init(displayName: "User Caches",
                  detail: "All app caches in ~/Library/Caches",
                  path: lib.appendingPathComponent("Caches"),
                  category: "System"),
            .init(displayName: "User Logs",
                  detail: "Diagnostic logs in ~/Library/Logs",
                  path: lib.appendingPathComponent("Logs"),
                  category: "System"),
        ]
    }
}

// MARK: - View

struct DiskTab: View {
    @StateObject private var scanner = DiskScanner()
    @State private var confirmDelete = false

    private var hasScanned: Bool {
        scanner.entries.contains { if case .pending = $0.sizeState { return false }; return true }
    }

    private var visible: [DiskEntry] {
        scanner.entries.filter { if case .absent = $0.sizeState { return false }; return true }
    }

    private var selectedBytes: UInt64 {
        scanner.entries.filter { $0.isSelected }.compactMap { $0.sizeState.bytes }.reduce(0, +)
    }

    private var totalBytes: UInt64 {
        scanner.entries.compactMap { $0.sizeState.bytes }.reduce(0, +)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if !hasScanned {
                emptyState
            } else {
                entryList
            }
            Divider()
            statusBar
        }
        .confirmationDialog(
            "Move to Trash?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Move \(formatBytes(selectedBytes)) to Trash", role: .destructive) {
                scanner.deleteSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Selected items will be moved to the Trash. You can restore them from there.")
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button(scanner.isScanning ? "Scanning…" : "Scan") { scanner.scan() }
                .disabled(scanner.isScanning)
                .buttonStyle(.bordered)
            Spacer()
            if selectedBytes > 0 {
                Text(formatBytes(selectedBytes) + " selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Move to Trash") { confirmDelete = true }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selectedBytes == 0 || scanner.isScanning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "internaldrive")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Click Scan to find reclaimable disk space")
                .foregroundStyle(.secondary)
            Text("Only known-safe locations are listed. Files are moved to Trash, not permanently deleted.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var entryList: some View {
        let groups = Dictionary(grouping: visible, by: { $0.category })
        return List {
            ForEach(groups.keys.sorted(), id: \.self) { cat in
                Section(cat) {
                    ForEach(groups[cat]!) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func entryRow(_ entry: DiskEntry) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { scanner.entries.first { $0.id == entry.id }?.isSelected ?? false },
                set: { v in
                    if let i = scanner.entries.firstIndex(where: { $0.id == entry.id }) {
                        scanner.entries[i].isSelected = v
                    }
                }
            ))
            .labelsHidden()
            .disabled(entry.sizeState.bytes == nil)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName).fontWeight(.medium)
                Text(entry.detail).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if case .scanning = entry.sizeState {
                ProgressView().controlSize(.small)
            } else {
                Text(entry.sizeState.formatted)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(entry.sizeState.bytes != nil ? .primary : .tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusBar: some View {
        HStack {
            if totalBytes > 0 {
                Text("Found \(formatBytes(totalBytes)) total")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func formatBytes(_ b: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
    }
}
