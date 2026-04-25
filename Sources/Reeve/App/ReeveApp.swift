import SwiftUI
import ReeveKit

@MainActor
final class AppState: ObservableObject {
    let engine: MonitoringEngine
    let overlay: OverlayController

    init() {
        let engine = MonitoringEngine()
        self.engine = engine
        self.overlay = OverlayController(engine: engine)
    }
}

@main
struct ReeveApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: state.engine, overlay: state.overlay)
        } label: {
            Label("Reeve", systemImage: "memorychip")
        }
        .menuBarExtraStyle(.window)
    }
}
