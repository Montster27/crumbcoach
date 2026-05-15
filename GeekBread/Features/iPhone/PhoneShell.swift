import SwiftUI

// Top-level iPhone shell. Tab bar with 5 destinations + a persistent
// "now baking" mini-bar above the tab bar when a bake is active.
//
// Routing rule: `AppState.screen` is the canonical destination across iPad
// and iPhone. `PhoneShell` derives the active tab from it and writes back
// through `state.goTo(...)` when the user taps a tab — so a notification
// tap that calls `state.goTo(.activeBake)` switches to the Bake tab on
// iPhone the same way it slides to the active-bake screen on iPad.
//
// More tab hosts the four lower-traffic destinations (Scheduler, Starter,
// Diagnose, Settings). Inner navigation goes through state.screen too —
// when the user taps "Settings" inside More, state.screen becomes
// .settings, which still maps to the More tab, and PhoneMoreScreen reads
// state.screen to push the actual settings view onto the stack.

struct PhoneShell: View {
    var state: AppState

    enum Tab: Hashable {
        case home, library, bake, journal, more

        init(screen: AppState.Screen) {
            switch screen {
            case .home:                      self = .home
            case .library, .recipe:          self = .library
            case .activeBake:                self = .bake
            case .journal:                   self = .journal
            case .scheduler, .starter,
                 .diagnose, .settings:       self = .more
            }
        }

        /// Where to land when the user taps this tab from elsewhere. The
        /// More tab's "default" matches whatever sub-destination is
        /// currently active; the shell falls back to .settings if none.
        fileprivate func defaultScreen(currentScreen: AppState.Screen) -> AppState.Screen {
            switch self {
            case .home:    return .home
            case .library: return .library
            case .bake:    return .activeBake
            case .journal: return .journal
            case .more:
                // Stay on the current sub-destination if we're already in
                // the More tab; otherwise land on Settings.
                switch currentScreen {
                case .scheduler, .starter, .diagnose, .settings:
                    return currentScreen
                default:
                    return .settings
                }
            }
        }
    }

    private var tab: Binding<Tab> {
        Binding(
            get: { Tab(screen: state.screen) },
            set: { newTab in
                state.goTo(newTab.defaultScreen(currentScreen: state.screen))
            }
        )
    }

    private var showMiniBar: Bool {
        state.activeBake != nil && Tab(screen: state.screen) != .bake
    }

    var body: some View {
        TabView(selection: tab) {
            NavigationStack {
                PhoneHomeScreen(state: state)
                    .navigationTitle("Today")
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(Tab.home)

            NavigationStack {
                PhoneLibraryScreen(state: state)
                    .navigationTitle("Library")
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem { Label("Library", systemImage: "book.fill") }
            .tag(Tab.library)

            NavigationStack {
                PhoneActiveBakeScreen(state: state)
                    .navigationTitle("Bake")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Bake", systemImage: "flame.fill") }
            .tag(Tab.bake)
            .badge(state.activeBake != nil ? "•" : nil)

            NavigationStack {
                PhoneJournalScreen(state: state)
                    .navigationTitle("Journal")
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem { Label("Journal", systemImage: "chart.bar.fill") }
            .tag(Tab.journal)

            NavigationStack {
                PhoneMoreScreen(state: state)
                    .navigationTitle("More")
                    .navigationBarTitleDisplayMode(.large)
            }
            .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
            .tag(Tab.more)
        }
        .tint(Theme.primary)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showMiniBar,
               let bake = state.activeBake,
               let recipe = state.recipe(bake.recipeId) {
                NowBakingMiniBar(bake: bake, recipe: recipe) {
                    state.goTo(.activeBake)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showMiniBar)
        .alert(
            "Couldn't save photo",
            isPresented: Binding(
                get: { state.photoErrorMessage != nil },
                set: { if !$0 { state.clearPhotoError() } }
            ),
            actions: { Button("OK", role: .cancel) { state.clearPhotoError() } },
            message: { Text(state.photoErrorMessage ?? "") }
        )
    }
}

// MARK: - Mini bar

private struct NowBakingMiniBar: View {
    let bake: ActiveBake
    let recipe: Recipe
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.primary)
                        .frame(width: 36, height: 36)
                    Text("cc")
                        .font(Typography.display(13, weight: .bold))
                        .foregroundStyle(.white)
                        .kerning(-0.4)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(recipe.title)
                        .font(Typography.ui(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(Typography.ui(11))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                RingProgress(value: bake.stageProgress, size: 32, stroke: 3,
                             color: .white, trackColor: .white.opacity(0.18)) {
                    Text("\(Int(bake.stageProgress * 100))%")
                        .font(Typography.ui(8.5, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Theme.slate950, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open active bake")
        .accessibilityValue("\(recipe.title), \(subtitle)")
    }

    private var subtitle: String {
        if bake.isComplete { return "ready to log" }
        let stage = recipe.stages[bake.currentStageIndex]
        if stage.kind == .bulkFold {
            return "\(stage.kind.rawValue) · \(bake.foldsDone)/\(bake.totalFolds) folds"
        }
        return "\(stage.kind.rawValue) · stage \(bake.currentStageIndex + 1) of \(recipe.stages.count)"
    }
}

#Preview("Phone Shell") {
    PhoneShell(state: AppState(persistence: PersistenceController(filename: "preview-phone.json")))
}
