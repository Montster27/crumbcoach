import SwiftUI

// First-launch onboarding. One screen: brand mark, short pitch, name field,
// "Get started" button. Presented as a fullScreenCover from the app scene
// until `state.hasOnboarded` flips true.

struct OnboardingScreen: View {
    var state: AppState
    @FocusState private var nameFocused: Bool
    @State private var name: String = ""

    var body: some View {
        ZStack {
            Theme.surface1.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 32) {
                    brand
                    headline
                    nameField
                    Spacer().frame(height: 8)
                    primaryButton
                    secondaryRow
                }
                .padding(48)
                .frame(maxWidth: 560)
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
        .onAppear { nameFocused = true }
    }

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
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Welcome.")
                .font(Typography.display(34, weight: .medium))
                .foregroundStyle(Theme.slate900)
            Text("Schedule your bakes, track folds and bake-out times, and see what works across your kitchen — all on this iPad.")
                .font(Typography.ui(14))
                .foregroundStyle(Theme.slate700)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
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
    }

    private var primaryButton: some View {
        Button(action: finish) {
            Label("Get started", systemImage: "arrow.right")
                .frame(maxWidth: .infinity)
        }
        .ccPrimary()
    }

    private var secondaryRow: some View {
        HStack(spacing: 6) {
            Text("Want to explore first?")
                .font(Typography.ui(12))
                .foregroundStyle(Theme.slate500)
            Button("Load demo data") {
                state.loadDemoData()
            }
            .font(Typography.ui(12, weight: .semibold))
            .foregroundStyle(Theme.primary)
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private func finish() {
        state.completeOnboarding(name: name)
    }
}

#Preview("Onboarding") {
    OnboardingScreen(state: AppState(persistence: PersistenceController(filename: "preview-onboarding.json")))
}
