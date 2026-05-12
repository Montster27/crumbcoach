import SwiftUI

// Settings — name, notifications status, demo / start-over actions, about.
// Intentionally light: this is not where we hide deep configuration. Keep it
// scannable so a baker can find their own name and the reset button without
// hunting.

struct SettingsScreen: View {
    var state: AppState
    @State private var nameDraft: String = ""
    @State private var showLoadDemoConfirm: Bool = false
    @State private var showStartOverConfirm: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            profileCard
            notificationsCard
            dataCard
            aboutCard
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 720, alignment: .leading)
        .onAppear { nameDraft = state.userName }
        .alert("Replace your data with the demo state?",
                isPresented: $showLoadDemoConfirm) {
            Button("Load demo", role: .destructive) { state.loadDemoData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This swaps your journal, active bake, and starters for the Marisol-kitchen demo so you can explore the full app. Your name stays.")
        }
        .alert("Start over?", isPresented: $showStartOverConfirm) {
            Button("Start over", role: .destructive) { state.startOver() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clears your journal and any active bake, and sends you back through onboarding. The recipe library is preserved.")
        }
    }

    // MARK: Profile

    private var profileCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Kicker("Profile")
                Text("Your name")
                    .font(Typography.ui(13, weight: .medium))
                    .foregroundStyle(Theme.slate700)
                HStack(spacing: 10) {
                    TextField("Baker", text: $nameDraft)
                        .font(Typography.display(18, weight: .medium))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Color.white,
                                     in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Theme.border1, lineWidth: 1)
                        )
                    Button("Save") {
                        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        state.setUserName(trimmed.isEmpty ? "Baker" : trimmed)
                    }
                    .ccPrimary(compact: true)
                    .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) == state.userName)
                }
                Text("Used to greet you on the home screen.")
                    .font(Typography.ui(11.5))
                    .foregroundStyle(Theme.slate500)
            }
        }
    }

    // MARK: Notifications

    private var notificationsCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Kicker("Notifications")
                HStack(spacing: 10) {
                    StatusPill(kind: pillKind, text: pillText, dot: true)
                    Spacer()
                    if state.notificationAuthStatus == .denied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Open Settings", systemImage: "arrow.up.right.square")
                        }
                        .ccSecondary(compact: true)
                    }
                }
                Text("Bake reminders fire at action points — folds, shape, retard end, bake start, bake out. Set per-bake on the Scheduler.")
                    .font(Typography.ui(12))
                    .foregroundStyle(Theme.slate600)
            }
        }
    }

    private var pillKind: PillKind {
        switch state.notificationAuthStatus {
        case .authorized, .provisional, .ephemeral: return .good
        case .denied: return .bad
        case .notDetermined: return .neutral
        @unknown default: return .neutral
        }
    }

    private var pillText: String {
        switch state.notificationAuthStatus {
        case .authorized: return "On"
        case .provisional: return "Quiet"
        case .ephemeral: return "App Clip"
        case .denied: return "Off"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }

    // MARK: Data

    private var dataCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Kicker("Data")
                dataRow(
                    title: "Load demo data",
                    detail: "See the app with Marisol's full kitchen — a mid-bulk bake, journal entries, two starters.",
                    icon: .sparkle,
                    action: { showLoadDemoConfirm = true }
                )
                SoftDivider()
                dataRow(
                    title: "Start over",
                    detail: "Clear your journal and active bake; keep the recipe library; re-run onboarding.",
                    icon: .trash,
                    destructive: true,
                    action: { showStartOverConfirm = true }
                )
            }
        }
    }

    private func dataRow(title: String, detail: String, icon: CCIcon,
                         destructive: Bool = false,
                         action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(destructive ? Theme.warm50 : Theme.primaryTint)
                    .frame(width: 38, height: 38)
                CCIconView(icon: icon, size: 16,
                            color: destructive ? Theme.warm700 : Theme.primary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.ui(14, weight: .semibold))
                    .foregroundStyle(Theme.slate900)
                Text(detail)
                    .font(Typography.ui(12))
                    .foregroundStyle(Theme.slate600)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(destructive ? "Reset" : "Run", action: action)
                .buttonStyle(CCButtonStyle(variant: destructive ? .secondary : .primary,
                                            compact: true))
        }
    }

    // MARK: About

    private var aboutCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Kicker("About")
                aboutRow("Version", versionString)
                aboutRow("Build", buildString)
                aboutRow("Recipes", "\(state.recipes.count)")
                aboutRow("Journal entries", "\(state.journal.count)")
                aboutRow("Starters", "\(state.starters.count)")
            }
        }
    }

    private func aboutRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Typography.ui(13))
                .foregroundStyle(Theme.slate700)
            Spacer()
            Text(value)
                .font(Typography.mono(13, weight: .semibold))
                .foregroundStyle(Theme.slate900)
        }
    }

    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private var buildString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

#Preview("Settings") {
    SettingsScreen(state: AppState(persistence: PersistenceController(filename: "preview-settings.json")))
        .padding()
        .background(Theme.surface1)
}
