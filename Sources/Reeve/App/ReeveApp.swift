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

    @Published var groupRuleSpecs: [GroupRuleSpec] = [] {
        didSet {
            persistGroupSpecs()
            groupRuleEngine.specs = groupRuleSpecs
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
        groupRuleEngine.connect(to: engine)
        overlay.configure(appState: self)  // must precede any show() call
        requestNotificationAuthorization()
        observeGroupActionLog()
        hotkey.register { [weak overlay] in overlay?.toggle() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            overlay.show()
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
            MenuBarView(engine: state.engine, overlay: state.overlay, hotkey: state.hotkey,
                        mainWindow: state.mainWindow)
                .environmentObject(state)
                .environment(\.iconCache, state.iconCache)
        } label: {
            MenuBarLabel(engine: state.engine)
        }
        .menuBarExtraStyle(.window)

        Settings {
            RulesSettingsView()
                .environmentObject(state)
        }
    }
}
