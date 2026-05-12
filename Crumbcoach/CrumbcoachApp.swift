import SwiftUI

@main
struct CrumbcoachApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppShell(state: appState)
                .preferredColorScheme(.light)
                .tint(Theme.primary)
        }
        .onChange(of: scenePhase) { _, phase in
            // Flush any pending debounced save when the user backgrounds the app.
            if phase == .background || phase == .inactive {
                appState.saveNow()
            }
        }
    }
}
