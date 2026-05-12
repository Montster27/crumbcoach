import SwiftUI
import CoreSpotlight

@main
struct CrumbcoachApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Force the notification delegate to register before the first scene
        // connects, so a tap-from-cold-launch is still delivered.
        _ = NotificationManager.shared
        // TelemetryManager subscribes inside `AppState.init` based on the
        // persisted preference — see Stage 9 notes.
    }

    var body: some Scene {
        WindowGroup {
            AppShell(state: appState)
                .preferredColorScheme(.light)
                .tint(Theme.primary)
                .task {
                    // Cold-launch tap path: the delegate may have fired before
                    // any SwiftUI observers were attached. Drain the one-shot
                    // flag here so the route still happens.
                    if NotificationManager.shared.consumePendingBakeTap() {
                        appState.goTo(.activeBake)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: NotificationManager.bakeReminderTapped
                )) { _ in
                    // Live-tap path: clear the flag too so the next
                    // `.task` run doesn't navigate again redundantly.
                    _ = NotificationManager.shared.consumePendingBakeTap()
                    appState.goTo(.activeBake)
                }
                .fullScreenCover(isPresented: Binding(
                    get: { !appState.hasOnboarded },
                    set: { _ in /* dismissal is driven by completeOnboarding */ }
                )) {
                    OnboardingScreen(state: appState)
                }
                .onOpenURL { url in
                    // crumbcoach://recipe/<id> → open the detail.
                    // crumbcoach://import?url=<encoded> → editor with URL.
                    appState.handleIncomingURL(url)
                }
                // Spotlight tap + Handoff hand-off both deliver an
                // NSUserActivity. We route both through the same handler so
                // a recipe tap from iPad search or an iPhone Handoff bubble
                // lands on the recipe detail.
                .onContinueUserActivity(SpotlightIndex.activityType) { activity in
                    if let id = SpotlightIndex.recipeId(from: activity) {
                        appState.openRecipe(id)
                    }
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let id = SpotlightIndex.recipeId(from: activity) {
                        appState.openRecipe(id)
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // System auth state may have flipped while we were backgrounded
                // (Settings → Notifications). Resync so the denied banner is
                // accurate when the user lands on the bake screen.
                Task { await appState.refreshNotificationAuthStatus() }
                // Pull any newer cloud state. Cheap no-op when disabled or
                // when iCloud isn't available.
                Task { await appState.syncWithCloud() }
            case .background, .inactive:
                // Flush any pending debounced save before iOS suspends us.
                appState.saveNow()
            @unknown default:
                break
            }
        }
    }
}
