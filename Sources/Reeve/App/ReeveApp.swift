import SwiftUI
import ReeveKit

@MainActor
final class AppState: ObservableObject {
    let engine: MonitoringEngine
    let overlay: OverlayController
    let iconCache: ProcessIconCache

    init() {
        let engine = MonitoringEngine()
        let iconCache = ProcessIconCache()
        self.engine = engine
        self.iconCache = iconCache
        self.overlay = OverlayController(engine: engine, iconCache: iconCache)
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
    }
}
