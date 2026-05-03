import SwiftUI
import ReeveKit

/// Settings → Memory tab. Houses the opt-in privileged helper toggle.
///
/// Default state is OFF. Enabling installs a LaunchDaemon (com.reeve.helper)
/// via SMAppService — the user authorizes once in System Settings → Login
/// Items. The helper runs as root, exposes a Mach service, and gives Reeve
/// access to mach_zone_info + per-process VM region walks for processes
/// that are otherwise opaque.
///
/// Honest copy: the toggle says "Install privileged helper" — not "Enable
/// detailed attribution". The four bullets describe exactly what runs as
/// root. The default stays the default.
struct MemoryAttributionTab: View {
    @AppStorage("memoryHelperEnabled") private var enabledPreference: Bool = false
    @State private var actualState: HelperLifecycle.State = HelperLifecycle.shared.state
    @State private var lastError: String?
    @State private var showInstallSheet = false
    @State private var showUninstallSheet = false
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                titleBlock
                helperCard
                helpLink
                Spacer(minLength: 12)
            }
            .padding(20)
        }
        .frame(minWidth: 560, minHeight: 420)
        .onAppear { refreshState() }
        .sheet(isPresented: $showInstallSheet) { installSheet }
        .sheet(isPresented: $showUninstallSheet) { uninstallSheet }
    }

    // MARK: - Top

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Memory")
                .font(.system(size: 16, weight: .semibold))
            Text("How Reeve attributes RAM and what to enable.")
                .font(.system(size: 12))
                .foregroundStyle(Color.rvTextDim)
            Rectangle().fill(Color.rvHairline).frame(height: 0.5)
                .padding(.top, 6)
        }
    }

    private var helpLink: some View {
        Text("How memory accounting works — see the popover’s memory detail panel.")
            .font(.system(size: 11))
            .foregroundStyle(Color.rvTextFaint)
    }

    // MARK: - Helper card

    private var helperCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DETAILED ATTRIBUTION")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.rvTextFaint)

            VStack(alignment: .leading, spacing: 14) {
                Text(headlineForState)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.rvText)

                Text(bodyCopy)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.rvTextDim)
                    .fixedSize(horizontal: false, vertical: true)

                toggleRow

                bulletList
                Text(disclosureLine)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.rvTextFaint)
                    .padding(.top, 4)

                if let err = lastError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.rvOver)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.rvBgElev)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.rvHairline, lineWidth: 0.5)
                    )
            )
        }
    }

    private var headlineForState: String {
        switch actualState {
        case .enabled:           return "Running as root"
        case .requiresApproval:  return "Awaiting approval in System Settings"
        case .notRegistered:     return "Off"
        case .notFound:          return "Not found — reinstall Reeve"
        case .unknown:           return "Unknown"
        case .unsupported:       return "Requires macOS 13 or later"
        }
    }

    private var bodyCopy: String {
        switch actualState {
        case .enabled:
            return "The helper is loaded and providing kernel zone totals plus per-process VM region maps for root-owned processes. Reeve still runs as a single unprivileged binary; the helper is a separate Mach-O signed by us."
        case .requiresApproval:
            return "macOS opened System Settings → Login Items. Find the “Reeve Helper” entry and turn it on. Reeve is waiting — recheck below or click Open Settings."
        default:
            return "Reeve runs as a single unprivileged binary by default. Some memory cannot be attributed without root — we mark it as Other (unmeasured) and tell you what's likely inside.\n\nThis is the default and stays the default."
        }
    }

    private var toggleRow: some View {
        HStack(spacing: 12) {
            Toggle(isOn: bindingForToggle) {
                Text("Install privileged helper")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.rvText)
            }
            .toggleStyle(.switch)
            .disabled(actualState == .unsupported || working)

            Spacer()
            statusBadge
            if actualState == .requiresApproval {
                Button("Open Settings") {
                    HelperLifecycle.shared.openLoginItemsSettings()
                }
                .buttonStyle(.bordered)
            }
            Button("Recheck") { refreshState() }
                .buttonStyle(.bordered)
        }
    }

    private var bindingForToggle: Binding<Bool> {
        Binding(
            get: { actualState == .enabled || actualState == .requiresApproval },
            set: { newValue in
                if newValue { showInstallSheet = true }
                else { showUninstallSheet = true }
            }
        )
    }

    private var statusBadge: some View {
        let (text, color) = badgeFor(actualState)
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
        }
    }

    private func badgeFor(_ s: HelperLifecycle.State) -> (String, Color) {
        switch s {
        case .enabled:          return ("Running",         Color.rvAccent.opacity(0.85))
        case .requiresApproval: return ("Pending approval", Color.rvWarn)
        case .notRegistered:    return ("Off",              Color.rvTextFaint)
        case .notFound:         return ("Not found",        Color.rvOver)
        case .unknown:          return ("Unknown",          Color.rvTextFaint)
        case .unsupported:      return ("Unsupported",      Color.rvTextFaint)
        }
    }

    private var bulletList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(bullets, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Text("·")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.rvTextFaint)
                    Text(line)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.rvTextDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private let bullets: [String] = [
        "installs a helper LaunchDaemon (com.reeve.helper) as root",
        "grants Reeve read-only access to mach_zone_info and per-process VM regions",
        "expands Reeve past its single-binary scope (Phase 1 is read-only — no kill, no signal)",
        "can be uninstalled at any time, no residue"
    ]

    private let disclosureLine = "Reeve will not write, mutate or escalate beyond reading memory accounting."

    // MARK: - Sheets

    private var installSheet: some View {
        ConfirmSheet(
            title: "Install privileged helper?",
            message: "macOS will ask you to authorize a background item from Reeve. The helper runs as root and exposes a Mach service used only by Reeve. You can uninstall it any time from this tab.",
            warning: "Reeve will require an admin password.",
            confirmTitle: "Install",
            confirmKind: .warn,
            onCancel: { showInstallSheet = false },
            onConfirm: {
                showInstallSheet = false
                install()
            }
        )
    }

    private var uninstallSheet: some View {
        ConfirmSheet(
            title: "Uninstall helper?",
            message: "Reeve will go back to its default unprivileged behaviour. The detail panel’s “Other (unmeasured)” bucket will reappear. The helper plist and binary stay inside the app bundle but will not be loaded.",
            warning: nil,
            confirmTitle: "Uninstall",
            confirmKind: .neutral,
            onCancel: { showUninstallSheet = false },
            onConfirm: {
                showUninstallSheet = false
                uninstall()
            }
        )
    }

    // MARK: - Actions

    private func refreshState() {
        actualState = HelperLifecycle.shared.state
        enabledPreference = (actualState == .enabled)
    }

    private func install() {
        working = true
        lastError = nil
        Task {
            do {
                let new = try HelperLifecycle.shared.register()
                await MainActor.run {
                    actualState = new
                    enabledPreference = (new == .enabled)
                    working = false
                }
            } catch {
                await MainActor.run {
                    lastError = "Install failed: \(error.localizedDescription)"
                    working = false
                    refreshState()
                }
            }
        }
    }

    private func uninstall() {
        working = true
        lastError = nil
        Task {
            do {
                let new = try await HelperLifecycle.shared.unregister()
                await MainActor.run {
                    actualState = new
                    enabledPreference = false
                    working = false
                }
            } catch {
                await MainActor.run {
                    lastError = "Uninstall failed: \(error.localizedDescription)"
                    working = false
                    refreshState()
                }
            }
        }
    }
}

private struct ConfirmSheet: View {
    enum Kind { case neutral, warn, danger }
    let title: String
    let message: String
    let warning: String?
    let confirmTitle: String
    let confirmKind: Kind
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Color.rvTextDim)
                .fixedSize(horizontal: false, vertical: true)
            if let warning {
                Text(warning)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.rvWarn)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(confirmKind == .warn ? Color.rvWarn :
                          confirmKind == .danger ? Color.rvOver : Color.rvAccent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
