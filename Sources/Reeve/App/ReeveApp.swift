import SwiftUI
import ReeveKit

@main
struct ReeveApp: App {
    @StateObject private var engine = MonitoringEngine()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: engine)
        } label: {
            Label("Reeve", systemImage: "memorychip")
        }
        .menuBarExtraStyle(.window)
    }
}
