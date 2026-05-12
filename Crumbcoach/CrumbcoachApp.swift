import SwiftUI

@main
struct CrumbcoachApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            AppShell(state: appState)
                .preferredColorScheme(.light)
                .tint(Theme.primary)
        }
    }
}
