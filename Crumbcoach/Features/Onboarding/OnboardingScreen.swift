import SwiftUI

// First-launch onboarding tour. Three pages: pitch, how-it-works, name +
// notifications. Presented as a fullScreenCover from the app scene until
// `state.hasOnboarded` flips true.
//
// The pages share a single chrome (brand + page indicator + nav row) so the
// reader's eye doesn't have to relearn where the buttons live. Page 3 is
// where we ask for the user's name and trigger the system notification
// prompt — gating both behind a couple of cards of context makes "why do
// they need this?" obvious to the user without a tooltip.

struct OnboardingScreen: View {
    var state: AppState
    @FocusState private var nameFocused: Bool
    @State private var name: String = ""
    @State private var page: Int = 0
    @State private var notificationsRequested: Bool = false

    private let totalPages = 3

    var body: some View {
        ZStack {
            Theme.surface1.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 28) {
                    brand
                    pageContent
                    Spacer().frame(height: 4)
                    navRow
                }
                .padding(44)
                .frame(maxWidth: 620, minHeight: 520)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Theme.border1, lineWidth: 1)
                )
                .shadow(color: Theme.shadowPanel, radius: 30, y: 12)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: Shared chrome

    private var brand: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.primary)
                .frame(width: 52, height: 52)
                .overlay(
                    Text("cc")
                        .font(Typography.display(22, weight: .bold))
                        .foregroundStyle(.white)
                        .kerning(-0.8)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("CrumbCoach")
                    .font(Typography.display(22, weight: .semibold))
                    .foregroundStyle(Theme.slate900)
                Text("Bread, on your schedule.")
                    .font(Typography.ui(13))
                    .foregroundStyle(Theme.slate500)
            }
            Spacer()
            pageDots
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalPages, id: \.self) { i in
                Circle()
                    .fill(i == page ? Theme.primary : Theme.slate300)
                    .frame(width: 6, height: 6)
                    .animation(state.reduceMotion ? nil : .easeOut(duration: 0.18),
                                value: page)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page + 1) of \(totalPages)")
    }

    // MARK: Page content

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case 0:  pitchPage
        case 1:  howPage
        default: namePage
        }
    }

    private var pitchPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("One app for every bread you bake.")
                .font(Typography.display(34, weight: .medium))
                .foregroundStyle(Theme.slate900)
                .fixedSize(horizontal: false, vertical: true)
            Text("Sourdough, enriched doughs, baguettes, focaccia, ciabatta — CrumbCoach scales recipes to your kitchen, weighs ingredients in your units, and tracks every fold so you don't have to.")
                .font(Typography.ui(15))
                .foregroundStyle(Theme.slate700)
                .fixedSize(horizontal: false, vertical: true)
            featureRow(icon: .book, text: "Curated recipe library across every major bread style.")
            featureRow(icon: .clock, text: "Reverse-schedule from when you want bread out of the oven.")
            featureRow(icon: .starter, text: "Track every starter and feeding without a spreadsheet.")
        }
    }

    private var howPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bake with the timer.")
                .font(Typography.display(34, weight: .medium))
                .foregroundStyle(Theme.slate900)
                .fixedSize(horizontal: false, vertical: true)
            Text("Each bake walks you stage by stage. CrumbCoach pings you for folds, reflows the schedule when you run late, and remembers what worked so the next bake is better.")
                .font(Typography.ui(15))
                .foregroundStyle(Theme.slate700)
                .fixedSize(horizontal: false, vertical: true)
            featureRow(icon: .bell,    text: "Folds, shaping, retard, bake-out — reminders fire only at action points.")
            featureRow(icon: .thermo,  text: "Schedules adjust to your kitchen temperature on the fly.")
            featureRow(icon: .graph,   text: "Your journal surfaces patterns across your last bakes.")
        }
    }

    private var namePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Let's set up your kitchen.")
                .font(Typography.display(34, weight: .medium))
                .foregroundStyle(Theme.slate900)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Kicker("Your name")
                TextField("Baker", text: $name)
                    .focused($nameFocused)
                    .font(Typography.display(20, weight: .medium))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Theme.surface1,
                                 in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.border1, lineWidth: 1)
                    )
                    .submitLabel(.go)
                    .onSubmit { finish() }
                Text("Used to greet you on the home screen — change it any time in Settings.")
                    .font(Typography.ui(11.5))
                    .foregroundStyle(Theme.slate500)
            }

            notificationsCallout
        }
        .onAppear { nameFocused = true }
    }

    private var notificationsCallout: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.primaryTint)
                    .frame(width: 36, height: 36)
                CCIconView(icon: .bell, size: 16, color: Theme.primary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(notificationsRequested ? "Reminders set up" : "Turn on bake reminders")
                    .font(Typography.ui(13.5, weight: .semibold))
                    .foregroundStyle(Theme.slate900)
                Text(notificationsRequested
                     ? "We'll only ping at action points — folds, shape, bake-out."
                     : "We only ping at action points. You can flip this off any time in Settings.")
                    .font(Typography.ui(12))
                    .foregroundStyle(Theme.slate600)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !notificationsRequested {
                Button("Allow") {
                    Task {
                        await state.requestNotificationPermission()
                        notificationsRequested = true
                    }
                }
                .ccSecondary(compact: true)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.success700)
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
        .background(Theme.primaryTint.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.primaryTint2, lineWidth: 1)
        )
    }

    private func featureRow(icon: CCIcon, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.primaryTint)
                    .frame(width: 32, height: 32)
                CCIconView(icon: icon, size: 14, color: Theme.primary)
            }
            Text(text)
                .font(Typography.ui(13.5))
                .foregroundStyle(Theme.slate700)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
    }

    // MARK: Nav row

    private var navRow: some View {
        HStack(spacing: 12) {
            secondaryRow
            Spacer()
            if page > 0 {
                Button("Back") { page -= 1 }
                    .ccGhost(compact: true)
            }
            if page < totalPages - 1 {
                Button(action: { page += 1 }) {
                    Label("Next", systemImage: "arrow.right")
                }
                .ccPrimary()
            } else {
                Button(action: finish) {
                    Label("Get started", systemImage: "arrow.right")
                }
                .ccPrimary()
            }
        }
    }

    private var secondaryRow: some View {
        Button("Load demo data") {
            state.loadDemoData()
        }
        .font(Typography.ui(12, weight: .semibold))
        .foregroundStyle(Theme.primary)
        .buttonStyle(.plain)
    }

    private func finish() {
        state.completeOnboarding(name: name)
    }
}

#Preview("Onboarding") {
    OnboardingScreen(state: AppState(persistence: PersistenceController(filename: "preview-onboarding.json")))
}
