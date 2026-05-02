import SwiftUI
import Combine
import UserNotifications
import ReeveKit

@MainActor
final class AppState: ObservableObject {
    let engine: MonitoringEngine
    let overlay: OverlayController
    let iconCache: ProcessIconCache
    let hotkey = GlobalHotkeyMonitor()
    let mainWindow = MainWindowController()
    let groupRuleEngine = GroupRuleEngine()
    private let notificationDelegate = NotificationDelegate()

    @Published var killFlashExpiry: Date?

    @Published var groupRuleSpecs: [GroupRuleSpec] = [] {
        didSet {
            persistGroupSpecs()
            groupRuleEngine.specs = groupRuleSpecs
        }
    }

    @Published var pressurePolicy: MemoryPressurePolicy = MemoryPressurePolicy() {
        didSet {
            persistPressurePolicy()
            groupRuleEngine.pressurePolicy = pressurePolicy
        }
    }

    private var groupLogCount = 0
    private var cancellables = Set<AnyCancellable>()

    init() {
        let engine = MonitoringEngine()
        let iconCache = ProcessIconCache()
        let overlay = OverlayController(engine: engine, iconCache: iconCache)
        self.engine = engine
        self.iconCache = iconCache
        self.overlay = overlay
        let specs = Self.loadGroupSpecs()
        self.groupRuleSpecs = specs
        groupRuleEngine.specs = specs
        let policy = Self.loadPressurePolicy()
        self.pressurePolicy = policy
        groupRuleEngine.pressurePolicy = policy
        groupRuleEngine.connect(to: engine)
        groupRuleEngine.onKill = { [weak self] in self?.triggerKillFlash() }
        overlay.configure(appState: self)  // must precede any show() call
        requestNotificationAuthorization()
        observeGroupActionLog()
        hotkey.register { [weak overlay] in overlay?.toggle() }
        if UserDefaults.standard.bool(forKey: "overlayShowOnLaunch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                overlay.show()
            }
        }
    }

    // MARK: - Notifications

    private func requestNotificationAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = notificationDelegate
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func observeGroupActionLog() {
        groupRuleEngine.$actionLog
            .receive(on: RunLoop.main)
            .sink { [weak self] log in
                guard let self else { return }
                let newEntries = log.dropFirst(self.groupLogCount)
                for entry in newEntries { self.postNotification(for: entry) }
                self.groupLogCount = log.count
            }
            .store(in: &cancellables)
    }

    private func postNotification(for entry: GroupActionLogEntry) {
        let content = UNMutableNotificationContent()
        content.title = "Rule fired: \(entry.appName)"
        content.body = "\(entry.conditionDescription)  ·  \(entry.actionName)  ·  \(entry.processCount) processes"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: entry.id.uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Kill flash

    func triggerKillFlash() {
        killFlashExpiry = Date.now.addingTimeInterval(0.6)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.6))
            if let exp = self?.killFlashExpiry, exp <= .now {
                self?.killFlashExpiry = nil
            }
        }
    }

    // MARK: - Persistence

    private func persistGroupSpecs() {
        guard let data = try? JSONEncoder().encode(groupRuleSpecs) else { return }
        UserDefaults.standard.set(data, forKey: "groupRuleSpecs")
    }

    private static func loadGroupSpecs() -> [GroupRuleSpec] {
        guard
            let data = UserDefaults.standard.data(forKey: "groupRuleSpecs"),
            let specs = try? JSONDecoder().decode([GroupRuleSpec].self, from: data)
        else { return [] }
        return specs
    }

    private func persistPressurePolicy() {
        guard let data = try? JSONEncoder().encode(pressurePolicy) else { return }
        UserDefaults.standard.set(data, forKey: "memoryPressurePolicy")
    }

    private static func loadPressurePolicy() -> MemoryPressurePolicy {
        guard
            let data = UserDefaults.standard.data(forKey: "memoryPressurePolicy"),
            let policy = try? JSONDecoder().decode(MemoryPressurePolicy.self, from: data)
        else { return MemoryPressurePolicy() }
        return policy
    }
}

// MARK: - Notification delegate

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        completionHandler()
    }
}

@main
struct ReeveApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            CalmPopover(engine: state.engine, groupRuleEngine: state.groupRuleEngine,
                        overlay: state.overlay, hotkey: state.hotkey,
                        mainWindow: state.mainWindow)
                .environmentObject(state)
                .environment(\.iconCache, state.iconCache)
        } label: {
            MenuBarLabel(engine: state.engine)
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)

        Settings {
            RulesSettingsView()
                .environmentObject(state)
        }
    }
}
