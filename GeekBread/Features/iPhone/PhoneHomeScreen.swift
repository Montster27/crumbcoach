import SwiftUI

// iPhone "Today" home — single-column stack of the same content the iPad
// Home renders as a 3-column grid + banner + horizontal insights strip.
// Reuses the same AppState reads; just rearranges for portrait.
//
// The bottom mini-bar (PhoneShell) still surfaces an active bake while the
// user is on Home — the in-content banner here gives the at-a-glance
// numbers (current stage, next action, bake-out time) the mini-bar can't.

struct PhoneHomeScreen: View {
    var state: AppState
    @State private var photoPickerOpen = false

    var body: some View {
        ScrollView {
            VStack(spacing: PhoneTheme.cardSpacing) {
                if let bake = state.activeBake, let recipe = state.recipe(bake.recipeId) {
                    ActiveBakeBannerPhone(state: state, bake: bake, recipe: recipe,
                                          photoPickerOpen: $photoPickerOpen)
                }

                DiagnosePromptCardPhone(state: state, photoPickerOpen: $photoPickerOpen)
                StarterCardPhone(state: state)
                UpNextCardPhone(state: state)

                if !state.insights.isEmpty {
                    InsightsListPhone(state: state)
                }
            }
            .padding(.horizontal, PhoneTheme.screenHPad)
            .padding(.top, PhoneTheme.screenVPad)
            .padding(.bottom, PhoneTheme.sectionSpacing)
        }
        .background(Theme.surface1)
        .photoPicker(isPresented: $photoPickerOpen) { image in
            state.queueDiagnosticPhoto(image)
            state.goTo(.diagnose)
        }
    }
}

// MARK: - Active bake banner (compact)

private struct ActiveBakeBannerPhone: View {
    var state: AppState
    let bake: ActiveBake
    let recipe: Recipe
    @Binding var photoPickerOpen: Bool

    private var stage: Stage? {
        recipe.stages.indices.contains(bake.currentStageIndex)
            ? recipe.stages[bake.currentStageIndex] : nil
    }

    private var nextActionText: String {
        if bake.isComplete { return "Log this bake" }
        guard let stage else { return "—" }
        if stage.kind == .bulkFold && bake.foldsDone < bake.totalFolds {
            return "Fold \(bake.foldsDone + 1) of \(bake.totalFolds)"
        }
        let nextIdx = bake.currentStageIndex + 1
        if recipe.stages.indices.contains(nextIdx) {
            return recipe.stages[nextIdx].kind.rawValue
        }
        return "Finish \(stage.kind.rawValue.lowercased())"
    }

    private var progressValue: Double {
        let total = Double(recipe.stages.count)
        guard total > 0 else { return 0 }
        return (Double(bake.currentStageIndex) + bake.stageProgress) / total
    }

    var body: some View {
        Button(action: { state.goTo(.activeBake) }) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    BreadPhoto(assetName: recipe.photo, kind: .crumb, height: 140)
                    LinearGradient(colors: [.clear, .black.opacity(0.6)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 140)
                    HStack(spacing: 8) {
                        StatusPill(kind: .good, text: "Active bake", dot: true)
                        Text("Started \(bake.startedAt, formatter: CCFormat.clockShort)")
                            .font(Typography.ui(11))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
                .frame(height: 140)
                .clipped()

                VStack(alignment: .leading, spacing: 12) {
                    Text(recipe.title)
                        .font(Typography.display(22, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                        .lineLimit(2)

                    HStack(alignment: .top, spacing: 14) {
                        bannerStat(title: "Stage", value: stage?.kind.rawValue ?? "—")
                        Rectangle().fill(Theme.border1).frame(width: 1, height: 30)
                        bannerStat(title: "Next", value: nextActionText)
                        Rectangle().fill(Theme.border1).frame(width: 1, height: 30)
                        bannerStat(title: "Out", value: CCFormat.clockShort.string(from: bake.bakeOutAt), mono: true)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        BarView(value: progressValue, height: 5)
                        Text("\(bake.currentStageIndex + 1) of \(recipe.stages.count) stages · \(Int(progressValue * 100))%")
                            .font(Typography.ui(10.5))
                            .foregroundStyle(Theme.slate500)
                    }

                    HStack(spacing: 8) {
                        Button { state.goTo(.activeBake) } label: {
                            Label("Open bake", systemImage: "arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .ccPrimary()

                        Button { photoPickerOpen = true } label: {
                            Label("Photo", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .ccSecondary()
                    }
                }
                .padding(PhoneTheme.cardPad)
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: PhoneTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PhoneTheme.cardRadius, style: .continuous)
                    .stroke(Theme.border1, lineWidth: 1)
            )
            .shadow(color: Theme.shadowPanel, radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func bannerStat(title: String, value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(title, size: 9)
            Text(value)
                .font(mono ? Typography.mono(12, weight: .semibold)
                            : Typography.ui(12, weight: .semibold))
                .foregroundStyle(Theme.slate900)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Diagnose prompt (promoted to first action card — iPhone is the camera)

private struct DiagnosePromptCardPhone: View {
    var state: AppState
    @Binding var photoPickerOpen: Bool

    private var diagnoseSubtitle: String {
        let counts = Dictionary(grouping: state.journal, by: \.recipeId)
            .mapValues(\.count)
        if let top = counts.max(by: { $0.value < $1.value }),
           top.value >= 2,
           let recipe = state.recipe(top.key) {
            return "On-device AI · Compares against your last \(top.value) \(recipe.title) bakes."
        }
        return "On-device AI · No upload."
    }

    var body: some View {
        Button { state.goTo(.diagnose) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Kicker("Diagnose", color: Theme.primary)
                    Spacer()
                    CCIconView(icon: .camera, size: 18, color: Theme.primary)
                }
                Text("Slice tomorrow? Run a crumb check.")
                    .font(Typography.display(18, weight: .medium))
                    .foregroundStyle(Theme.slate900)
                    .multilineTextAlignment(.leading)
                Text(diagnoseSubtitle)
                    .font(Typography.ui(12))
                    .foregroundStyle(Theme.slate600)
                    .multilineTextAlignment(.leading)
                Button { photoPickerOpen = true } label: {
                    Label("Take photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .ccPrimary()
            }
            .padding(PhoneTheme.cardPad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.primaryTint,
                        in: RoundedRectangle(cornerRadius: PhoneTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PhoneTheme.cardRadius, style: .continuous)
                    .stroke(Theme.border1, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Starter card (compact)

private struct StarterCardPhone: View {
    var state: AppState

    var body: some View {
        Button { state.goTo(.starter) } label: {
            if let s = state.starters.first {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Kicker("Starter")
                            HStack(spacing: 6) {
                                Text(s.name)
                                    .font(Typography.display(18, weight: .medium))
                                    .foregroundStyle(Theme.slate900)
                                Text("· \(s.flourType)")
                                    .font(Typography.ui(12))
                                    .foregroundStyle(Theme.slate400)
                            }
                        }
                        Spacer()
                        StatusPill(kind: .warn, text: "Peaked −2h", dot: true)
                    }
                    .padding(.horizontal, PhoneTheme.cardPad)
                    .padding(.top, PhoneTheme.cardPad)

                    Sparkline(values: s.riseHistory, color: Theme.warm)
                        .frame(height: 44)
                        .padding(.horizontal, PhoneTheme.cardPad)
                        .padding(.top, 8)

                    HStack {
                        Text("−12h"); Spacer(); Text("−6h"); Spacer(); Text("peak"); Spacer(); Text("now")
                    }
                    .font(Typography.ui(10))
                    .foregroundStyle(Theme.slate500)
                    .padding(.horizontal, PhoneTheme.cardPad)
                    .padding(.top, 4)

                    SoftDivider().padding(.top, 10)

                    HStack {
                        Text("Use it now or refrigerate")
                            .font(Typography.ui(12))
                            .foregroundStyle(Theme.slate600)
                        Spacer()
                        Text("Feed \(s.nextFeed) →")
                            .font(Typography.ui(12, weight: .medium))
                            .foregroundStyle(Theme.primary)
                    }
                    .padding(.horizontal, PhoneTheme.cardPad)
                    .padding(.vertical, 10)
                }
                .background(Color.white,
                            in: RoundedRectangle(cornerRadius: PhoneTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PhoneTheme.cardRadius, style: .continuous)
                        .stroke(Theme.border1, lineWidth: 1)
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker("Starter")
                    Text("No starter yet")
                        .font(Typography.display(18, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                    Text("Add your sourdough starter to track feedings, peak times, and bake-readiness.")
                        .font(Typography.ui(12.5))
                        .foregroundStyle(Theme.slate600)
                        .multilineTextAlignment(.leading)
                    Text("Add a starter →")
                        .font(Typography.ui(12, weight: .medium))
                        .foregroundStyle(Theme.primary)
                        .padding(.top, 4)
                }
                .padding(PhoneTheme.cardPad)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white,
                            in: RoundedRectangle(cornerRadius: PhoneTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PhoneTheme.cardRadius, style: .continuous)
                        .strokeBorder(Theme.border1, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                )
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Up next card

private struct UpNextCardPhone: View {
    var state: AppState
    @State private var selectedTime = "10:00 AM"
    private let options = ["10:00 AM", "Noon", "Custom"]

    private var featuredRecipe: Recipe? {
        let counts = Dictionary(grouping: state.journal, by: \.recipeId)
            .mapValues(\.count)
        if let topId = counts.max(by: { $0.value < $1.value })?.key,
           let recipe = state.recipe(topId) {
            return recipe
        }
        return state.recipes.first
    }

    var body: some View {
        Button { state.goTo(.scheduler) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Kicker("Up next")
                Text("Plan tomorrow's bake")
                    .font(Typography.display(18, weight: .medium))
                    .foregroundStyle(Theme.slate900)
                Text("Set a target time and the scheduler will build the timeline backward from there.")
                    .font(Typography.ui(12.5))
                    .foregroundStyle(Theme.slate600)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { t in
                        TagPill(label: t, active: t == selectedTime) { selectedTime = t }
                    }
                }
                .padding(.top, 4)
                summary
                    .padding(.top, 4)
            }
            .padding(PhoneTheme.cardPad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white,
                        in: RoundedRectangle(cornerRadius: PhoneTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PhoneTheme.cardRadius, style: .continuous)
                    .stroke(Theme.border1, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var summary: some View {
        let recipeTitle = featuredRecipe?.title ?? "your bake"
        let displayTime = selectedTime == "Custom" ? "your target" : "\(selectedTime) Sun"
        (Text("For ").font(Typography.ui(11.5)).foregroundStyle(Theme.slate500)
        + Text(recipeTitle).font(Typography.ui(11.5, weight: .semibold)).foregroundStyle(Theme.slate700)
        + Text(" at ").font(Typography.ui(11.5)).foregroundStyle(Theme.slate500)
        + Text(displayTime).font(Typography.mono(11.5, weight: .semibold)).foregroundStyle(Theme.slate700))
        .multilineTextAlignment(.leading)
    }
}

// MARK: - Insights — vertical list on iPhone

private struct InsightsListPhone: View {
    var state: AppState

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Kicker("Patterns this week")
                    Text("From your last \(min(6, state.journal.count)) bakes")
                        .font(Typography.display(16, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                }
                Spacer()
                Button("Journal →") { state.goTo(.journal) }
                    .ccGhost(compact: true)
            }
            .padding(.horizontal, 2)
            .padding(.top, 6)

            VStack(spacing: 8) {
                ForEach(Array(state.insights.enumerated()), id: \.offset) { _, ins in
                    InsightTilePhone(insight: ins)
                }
            }
        }
    }
}

private struct InsightTilePhone: View {
    let insight: Insight
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.primaryTint)
                    .frame(width: 32, height: 32)
                CCIconView(icon: iconFor(insight.kind), size: 14, color: Theme.primary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Kicker(insight.kind.rawValue)
                Text(insight.headline)
                    .font(Typography.ui(13, weight: .medium))
                    .foregroundStyle(Theme.slate900)
                    .multilineTextAlignment(.leading)
                Text(insight.detail)
                    .font(Typography.ui(11.5))
                    .foregroundStyle(Theme.slate500)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(PhoneTheme.cardPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white,
                    in: RoundedRectangle(cornerRadius: PhoneTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PhoneTheme.cardRadius, style: .continuous)
                .stroke(Theme.border1, lineWidth: 1)
        )
    }

    private func iconFor(_ kind: InsightKind) -> CCIcon {
        switch kind {
        case .trend: return .graph
        case .flour: return .book
        case .temp:  return .thermo
        }
    }
}

#Preview("Phone Home") {
    NavigationStack {
        PhoneHomeScreen(state: AppState(persistence: PersistenceController(filename: "preview-phone-home.json")))
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
    }
}
