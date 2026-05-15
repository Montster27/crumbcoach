import SwiftUI

// Top-level app shell: 232-wide sidebar + main scroll area with sticky header.
// Mirrors app.jsx layout, scaled for iPad landscape.

struct AppShell: View {
    var state: AppState
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Sidebar width scales with Dynamic Type so Larger Text users don't get
    /// truncated nav labels.  Base 232, growing up to ~290 at .accessibility5.
    private var sidebarWidth: CGFloat {
        let base: CGFloat = 232
        let scale: CGFloat
        switch typeSize {
        case .xSmall, .small, .medium: scale = 1.0
        case .large: scale = 1.0
        case .xLarge: scale = 1.04
        case .xxLarge: scale = 1.08
        case .xxxLarge: scale = 1.12
        case .accessibility1: scale = 1.18
        case .accessibility2: scale = 1.22
        case .accessibility3, .accessibility4, .accessibility5: scale = 1.25
        @unknown default: scale = 1.0
        }
        return base * scale
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(state: state)
                .frame(width: sidebarWidth)
                .background(Color.white)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Theme.border1).frame(width: 1)
                }

            VStack(spacing: 0) {
                AppHeader(state: state)
                ScrollView {
                    Group {
                        switch state.screen {
                        case .home:          HomeScreen(state: state)
                        case .activeBake:    ActiveBakeScreen(state: state)
                        case .library:       LibraryScreen(state: state)
                        case .recipe(let id):RecipeDetailScreen(state: state, recipeId: id)
                        case .scheduler:     SchedulerScreen(state: state)
                        case .starter:       StarterScreen(state: state)
                        case .diagnose:      DiagnosticScreen(state: state)
                        case .journal:       JournalScreen(state: state)
                        case .settings:      SettingsScreen(state: state)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .padding(.bottom, 48)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
                    .id(screenId)
                }
                .background(Theme.surface1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.surface1)
        .onAppear { state.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, new in state.reduceMotion = new }
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

    private var screenId: String {
        switch state.screen {
        case .home:        return "home"
        case .activeBake:  return "bake"
        case .library:     return "library"
        case .recipe(let id): return "recipe-\(id)"
        case .scheduler:   return "scheduler"
        case .starter:     return "starter"
        case .diagnose:    return "diagnose"
        case .journal:     return "journal"
        case .settings:    return "settings"
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    var state: AppState

    struct Item: Identifiable {
        let id: String
        let label: String
        let icon: CCIcon
        let screen: AppState.Screen
        var liveBadge: Bool = false
    }

    var items: [Item] {
        [
            .init(id: "home",      label: "Today",        icon: .home,    screen: .home),
            .init(id: "bake",      label: "Active bake",  icon: .play,    screen: .activeBake,
                  liveBadge: state.activeBake != nil),
            .init(id: "library",   label: "Recipes",      icon: .book,    screen: .library),
            .init(id: "scheduler", label: "Scheduler",    icon: .clock,   screen: .scheduler),
            .init(id: "starter",   label: "Starter",      icon: .starter, screen: .starter),
            .init(id: "diagnose",  label: "Diagnose",     icon: .camera,  screen: .diagnose),
            .init(id: "journal",   label: "Journal",      icon: .graph,   screen: .journal),
            .init(id: "settings",  label: "Settings",     icon: .settings, screen: .settings),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Brand
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.primary)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text("cc")
                            .font(Typography.display(16, weight: .bold))
                            .foregroundStyle(.white)
                            .kerning(-0.6)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text("GeekBread")
                        .font(Typography.display(16, weight: .semibold))
                        .foregroundStyle(Theme.slate900)
                    Text(kitchenLabel)
                        .font(Typography.ui(10.5))
                        .foregroundStyle(Theme.slate500)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 18)

            ForEach(items) { item in
                NavButton(item: item, isActive: isActive(item),
                          action: { state.goTo(item.screen) })
            }

            Spacer()

            // Kitchen card
            KitchenCard(state: state)
                .padding(.horizontal, 4)
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 20)
    }

    private func isActive(_ item: Sidebar.Item) -> Bool {
        switch state.screen {
        case .recipe: return item.id == "library"
        default:      return item.screen == state.screen
        }
    }

    private var kitchenLabel: String {
        let trimmed = state.userName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Your kitchen" : "\(trimmed)'s kitchen"
    }
}

private struct NavButton: View {
    let item: Sidebar.Item
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                CCIconView(icon: item.icon, size: 16,
                           color: isActive ? Theme.primary : Theme.slate500)
                Text(item.label)
                    .font(Typography.ui(13.5, weight: .medium))
                    .foregroundStyle(isActive ? Theme.primaryDeep : Theme.slate700)
                Spacer()
                if item.liveBadge {
                    HStack(spacing: 3) {
                        Circle().fill(Theme.success700).frame(width: 5, height: 5)
                        Text("LIVE")
                            .font(Typography.ui(9, weight: .semibold))
                            .foregroundStyle(Theme.success700)
                            .kerning(0.4)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.success50, in: Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? Theme.primaryTint : .clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct KitchenCard: View {
    let state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker("Kitchen")
            HStack {
                Text("Temp")
                    .font(Typography.ui(12))
                    .foregroundStyle(Theme.slate700)
                Spacer()
                Text(String(format: "%.1f°C", state.kitchenTempC))
                    .font(Typography.mono(12, weight: .semibold))
                    .foregroundStyle(Theme.slate900)
            }
            HStack {
                Text("Humidity")
                    .font(Typography.ui(12))
                    .foregroundStyle(Theme.slate700)
                Spacer()
                Text("\(state.kitchenHumidityPct)%")
                    .font(Typography.mono(12, weight: .semibold))
                    .foregroundStyle(Theme.slate900)
            }
            HStack {
                Text("Oven")
                    .font(Typography.ui(12))
                    .foregroundStyle(Theme.slate700)
                Spacer()
                Text(state.ovenStatus)
                    .font(Typography.ui(11))
                    .foregroundStyle(Theme.slate500)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(12)
        .background(Theme.slate50, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Header

struct AppHeader: View {
    var state: AppState
    @State private var now: Date = .now
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var titles: (kicker: String, title: String) {
        switch state.screen {
        case .home:
            let displayName = state.userName.trimmingCharacters(in: .whitespaces)
            let greeting = state.greeting
            return ("Today", displayName.isEmpty ? greeting : "\(greeting), \(displayName)")
        case .activeBake:
            if let bake = state.activeBake, let recipe = state.recipe(bake.recipeId) {
                let suffix = bake.isComplete ? "ready to log" : "in progress"
                return ("Active bake", "\(recipe.title) · \(suffix)")
            }
            return ("Active bake", "No bake in progress")
        case .library:     return ("Library",     "Your recipes")
        case .recipe(let id):
            let r = state.recipe(id)
            return ("Recipe", r?.title ?? "Recipe")
        case .scheduler:   return ("Scheduler",   "Plan a bake")
        case .starter:     return ("Starter",     "Sourdough starters")
        case .diagnose:    return ("Diagnose",    "Crumb diagnostic")
        case .journal:     return ("Journal",     "Bake history & insights")
        case .settings:    return ("Settings",    "Your GeekBread")
        }
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Kicker(titles.kicker)
                Text(titles.title)
                    .font(Typography.display(26, weight: .medium))
                    .foregroundStyle(Theme.slate900)
            }
            Spacer()
            HStack(spacing: 12) {
                Text(now, format: Date.FormatStyle().weekday(.abbreviated).hour().minute())
                    .font(Typography.mono(12))
                    .foregroundStyle(Theme.slate500)
                Rectangle().fill(Theme.border1).frame(width: 1, height: 20)
                AvatarBadge(initial: String(state.userName.prefix(1)))
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background(Theme.surface1.opacity(0.92))
        .background(.regularMaterial.opacity(0.5))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border1).frame(height: 1)
        }
        .onReceive(timer) { now = $0 }
    }
}

private struct AvatarBadge: View {
    let initial: String
    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(hex: 0xC084FC), Color(hex: 0xF472B6)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 34, height: 34)
            .overlay(
                Text(initial.uppercased())
                    .font(Typography.ui(13, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}
