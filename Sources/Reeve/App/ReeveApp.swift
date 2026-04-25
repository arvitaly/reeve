import SwiftUI
import ReeveKit

@MainActor
final class AppState: ObservableObject {
    let engine: MonitoringEngine
    let overlay: OverlayController
    let iconCache: ProcessIconCache

    @Published var ruleSpecs: [RuleSpec] = [] {
        didSet {
            persistSpecs()
            engine.rules = ruleSpecs.filter(\.isEnabled).map { $0.toRule() }
        }
    }

    init() {
        let engine = MonitoringEngine()
        let iconCache = ProcessIconCache()
        self.engine = engine
        self.iconCache = iconCache
        self.overlay = OverlayController(engine: engine, iconCache: iconCache)
        let specs = Self.loadSpecs()
        self.ruleSpecs = specs
        engine.rules = specs.filter(\.isEnabled).map { $0.toRule() }
    }

    private func persistSpecs() {
        guard let data = try? JSONEncoder().encode(ruleSpecs) else { return }
        UserDefaults.standard.set(data, forKey: "ruleSpecs")
    }

    private static func loadSpecs() -> [RuleSpec] {
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
            MenuBarView(engine: state.engine, overlay: state.overlay)
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
