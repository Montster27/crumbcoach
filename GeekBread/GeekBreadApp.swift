import SwiftUI
import CoreSpotlight

@main
struct GeekBreadApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Force the notification delegate to register before the first scene
        // connects, so a tap-from-cold-launch is still delivered.
        _ = NotificationManager.shared
        // TelemetryManager subscribes inside `AppState.init` based on the
        // persisted preference — see Stage 9 notes.
    }

    /// iPhone runs a parallel shell (`iPhoneShell`) with its own tab-based UI;
    /// iPad and Mac Catalyst keep the original `AppShell` (sidebar + 1440-wide
    /// landscape canvas). The split happens here so every other system-level
    /// modifier — deep links, Spotlight, notification taps, onboarding — wraps
    /// both surfaces identically.
    @ViewBuilder
    private var rootShell: some View {
        #if targetEnvironment(macCatalyst)
        AppShell(state: appState)
        #else
        if UIDevice.current.userInterfaceIdiom == .phone {
            PhoneShell(state: appState)
        } else {
            AppShell(state: appState)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            rootShell
                .preferredColorScheme(.light)
                .tint(Theme.primary)
                .task {
                    // Cold-launch tap path: the delegate may have fired before
                    // any SwiftUI observers were attached. Drain the one-shot
                    // flag here so the route still happens.
                    if NotificationManager.shared.consumePendingBakeTap() {
                        appState.goTo(.activeBake)
                    }
                    // Recipes-only iCloud sync (May 2026). Pull any newer
                    // cloud copy and push local edits so a device that's
                    // been offline catches up to its siblings on launch.
                    await appState.syncRecipesWithCloud()
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
                    // geekbread://recipe/<id> → open the detail.
                    // geekbread://import?url=<encoded> → editor with URL.
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
                // Pull any newer cloud recipes. Cheap no-op when iCloud
                // isn't available.
                Task { await appState.syncRecipesWithCloud() }
            case .background, .inactive:
                // Flush any pending debounced save before iOS suspends us.
                appState.saveNow()
            @unknown default:
                break
            }
        }
    }
}
