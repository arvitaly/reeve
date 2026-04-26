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

    @Published var ruleSpecs: [RuleSpec] = [] {
        didSet {
            persistSpecs()
            engine.rules = ruleSpecs.filter(\.isEnabled).map { $0.toRule() }
        }
    }

    private var logCount = 0
    private var cancellables = Set<AnyCancellable>()

    init() {
        let engine = MonitoringEngine()
        let iconCache = ProcessIconCache()
        let overlay = OverlayController(engine: engine, iconCache: iconCache)
        self.engine = engine
        self.iconCache = iconCache
        self.overlay = overlay
        let specs = Self.loadSpecs()
        self.ruleSpecs = specs
        engine.rules = specs.filter(\.isEnabled).map { $0.toRule() }
        requestNotificationAuthorization()
        observeActionLog()
        hotkey.register { [weak overlay] in overlay?.toggle() }
    }

    // MARK: - Notifications

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func observeActionLog() {
        engine.$actionLog
            .receive(on: RunLoop.main)
            .sink { [weak self] log in
                guard let self else { return }
                let newEntries = log.dropFirst(self.logCount)
                for entry in newEntries { self.postNotification(for: entry) }
                self.logCount = log.count
            }
            .store(in: &cancellables)
    }

    private func postNotification(for entry: ActionLogEntry) {
        let content = UNMutableNotificationContent()
        content.title = "Rule fired: \(entry.ruleName)"
        content.body = "\(entry.action.target.name) (PID \(entry.action.target.pid))  ·  \(entry.action.kind.shortName)"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: entry.id.uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Persistence

    private func persistSpecs() {
        guard let data = try? JSONEncoder().encode(ruleSpecs) else { return }
        UserDefaults.standard.set(data, forKey: "ruleSpecs")
    }

    private static func loadSpecs() -> [ReeveKit.RuleSpec] {
        guard
            let data = UserDefaults.standard.data(forKey: "ruleSpecs"),
            let specs = try? JSONDecoder().decode([RuleSpec].self, from: data)
        else { return [] }
        return specs
    }
}

@main
struct ReeveApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: state.engine, overlay: state.overlay, hotkey: state.hotkey)
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
