import SwiftUI

// "Today" home screen.  Active bake banner + 3-col cards (starter / up-next /
// diagnose) + insights strip.  Mirrors screen-home.jsx.

struct HomeScreen: View {
    var state: AppState
    @State private var photoPickerOpen = false

    var body: some View {
        VStack(spacing: 20) {
            if let bake = state.activeBake, let recipe = state.recipe(bake.recipeId) {
                ActiveBakeBanner(state: state, bake: bake, recipe: recipe,
                                  photoPickerOpen: $photoPickerOpen)
            }

            // 3-col grid
            HStack(alignment: .top, spacing: 20) {
                StarterCard(state: state)
                UpNextCard(state: state)
                DiagnosePromptCard(state: state, photoPickerOpen: $photoPickerOpen)
            }

            // Patterns only make sense once the user has actually baked. The
            // strip stays hidden until the journal has something to summarize
            // — otherwise the synthetic placeholders make the home feel
            // generic rather than personal.
            if !state.insights.isEmpty {
                InsightsStrip(state: state)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .photoPicker(isPresented: $photoPickerOpen) { image in
            state.queueDiagnosticPhoto(image)
            state.goTo(.diagnose)
        }
    }
}

// MARK: - Active bake banner

private struct ActiveBakeBanner: View {
    var state: AppState
    let bake: ActiveBake
    let recipe: Recipe
    @Binding var photoPickerOpen: Bool

    var stage: Stage? {
        recipe.stages.indices.contains(bake.currentStageIndex)
            ? recipe.stages[bake.currentStageIndex] : nil
    }

    /// Banner copy for "Next action." Mid-bulk-folds we count the next fold;
    /// otherwise we surface the upcoming stage by name. Falls back to a
    /// finish-the-current-stage prompt when we're already on the last stage.
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

    var body: some View {
        Button(action: { state.goTo(.activeBake) }) {
            HStack(alignment: .center, spacing: 0) {
                BreadPhoto(assetName: recipe.photo, kind: .crumb, height: 200)
                    .frame(width: 260, height: 200)
                    .clipped()

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        StatusPill(kind: .good, text: "Active bake", dot: true)
                        Text("Started \(bake.startedAt, formatter: CCFormat.clockShort)")
                            .font(Typography.ui(12))
                            .foregroundStyle(Theme.slate500)
                    }
                    Text(recipe.title)
                        .font(Typography.display(28, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                        .padding(.top, 6)

                    HStack(spacing: 24) {
                        bannerStat(title: "Current stage", value: stage?.kind.rawValue ?? "—")
                        Rectangle().fill(Theme.border1).frame(width: 1).frame(maxHeight: 36)
                        bannerStat(title: "Next action", value: nextActionText)
                        Rectangle().fill(Theme.border1).frame(width: 1).frame(maxHeight: 36)
                        bannerStat(title: "Bake out", value: CCFormat.clockShort.string(from: bake.bakeOutAt), mono: true)
                    }
                    .padding(.top, 14)

                    BarView(value: progressValue, height: 6)
                        .padding(.top, 16)
                    Text("\(bake.currentStageIndex + 1) of \(recipe.stages.count) stages · \(Int(progressValue * 100))% complete")
                        .font(Typography.ui(11))
                        .foregroundStyle(Theme.slate500)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 10) {
                    Button(action: { state.goTo(.activeBake) }) {
                        Label("Open bake", systemImage: "arrow.right")
                    }.ccPrimary()
                    Button(action: { photoPickerOpen = true }) {
                        Label("Photo", systemImage: "camera")
                    }.ccSecondary()
                }
                .padding(24)
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.border1, lineWidth: 1)
            )
            .shadow(color: Theme.shadowPanel, radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var progressValue: Double {
        let total = Double(recipe.stages.count)
        guard total > 0 else { return 0 }
        return (Double(bake.currentStageIndex) + bake.stageProgress) / total
    }

    private func bannerStat(title: String, value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Kicker(title)
            Text(value)
                .font(mono ? Typography.mono(13, weight: .semibold) : Typography.ui(13, weight: .semibold))
                .foregroundStyle(Theme.slate900)
        }
    }
}

// MARK: - Starter card

private struct StarterCard: View {
    var state: AppState

    var body: some View {
        Button(action: { state.goTo(.starter) }) {
            if let s = state.starters.first {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Kicker("Starter")
                            HStack(spacing: 6) {
                                Text(s.name)
                                    .font(Typography.display(20, weight: .medium))
                                    .foregroundStyle(Theme.slate900)
                                Text("· \(s.flourType)")
                                    .font(Typography.ui(13))
                                    .foregroundStyle(Theme.slate400)
                            }
                        }
                        Spacer()
                        StatusPill(kind: .warn, text: "Peaked −2h", dot: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                    Sparkline(values: s.riseHistory, color: Theme.warm)
                        .frame(height: 48)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    HStack {
                        Text("−12h"); Spacer(); Text("−6h"); Spacer(); Text("peak"); Spacer(); Text("now")
                    }
                    .font(Typography.ui(11))
                    .foregroundStyle(Theme.slate500)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    SoftDivider()
                        .padding(.top, 12)

                    HStack {
                        Text("Use it now or refrigerate")
                            .font(Typography.ui(12))
                            .foregroundStyle(Theme.slate600)
                        Spacer()
                        Text("Feed at 8:14 PM →")
                            .font(Typography.ui(12, weight: .medium))
                            .foregroundStyle(Theme.primary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border1, lineWidth: 1))
                .shadow(color: Theme.shadowCard, radius: 1, y: 1)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Kicker("Starter")
                    Text("No starter yet")
                        .font(Typography.display(20, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                        .padding(.top, 4)
                    Text("Add your sourdough starter to track feedings, peak times, and bake-readiness.")
                        .font(Typography.ui(13))
                        .foregroundStyle(Theme.slate600)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 8)
                    Spacer(minLength: 12)
                    HStack(spacing: 6) {
                        Text("Add a starter →")
                            .font(Typography.ui(12, weight: .medium))
                            .foregroundStyle(Theme.primary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.border1, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                )
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Up next card

private struct UpNextCard: View {
    var state: AppState
    @State private var selectedTime = "10:00 AM"
    private let options = ["10:00 AM", "Noon", "Custom"]

    var body: some View {
        Button(action: { state.goTo(.scheduler) }) {
            VStack(alignment: .leading, spacing: 0) {
                Kicker("Up next")
                Text("Plan tomorrow's bake")
                    .font(Typography.display(20, weight: .medium))
                    .foregroundStyle(Theme.slate900)
                    .padding(.top, 4)
                Text("You usually bake Sunday morning. Set a target time and the scheduler will build the timeline.")
                    .font(Typography.ui(13))
                    .foregroundStyle(Theme.slate600)
                    .padding(.top, 10)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { t in
                        TagPill(label: t, active: t == selectedTime) { selectedTime = t }
                    }
                }
                .padding(.top, 14)
                Text("For ").font(Typography.ui(12)).foregroundStyle(Theme.slate500)
                +
                Text("Country Sourdough").font(Typography.ui(12, weight: .semibold)).foregroundStyle(Theme.slate700)
                +
                Text(" at 10 AM Sun → start levain build today ").font(Typography.ui(12)).foregroundStyle(Theme.slate500)
                +
                Text("at 4:14 PM").font(Typography.mono(12, weight: .semibold)).foregroundStyle(Theme.slate700)
                +
                Text(".").font(Typography.ui(12)).foregroundStyle(Theme.slate500)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border1, lineWidth: 1))
            .shadow(color: Theme.shadowCard, radius: 1, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Diagnose prompt card

private struct DiagnosePromptCard: View {
    var state: AppState
    @Binding var photoPickerOpen: Bool

    var body: some View {
        Button(action: { state.goTo(.diagnose) }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Kicker("Diagnose", color: Theme.primary)
                    Spacer()
                    CCIconView(icon: .camera, size: 18, color: Theme.primary)
                }
                Text("Slice tomorrow? Run a crumb check.")
                    .font(Typography.display(20, weight: .medium))
                    .foregroundStyle(Theme.slate900)
                    .padding(.top, 6)
                Text("On-device AI · 1.8 s · Compares against your last 6 Country Sourdoughs.")
                    .font(Typography.ui(12.5))
                    .foregroundStyle(Theme.slate600)
                    .padding(.top, 8)
                Button(action: { photoPickerOpen = true }) {
                    Label("Take photo", systemImage: "camera")
                }
                .ccPrimary()
                .padding(.top, 14)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.primaryTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border1, lineWidth: 1))
            .shadow(color: Theme.shadowCard, radius: 1, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Insights strip

private struct InsightsStrip: View {
    var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker("Patterns this week")
                    Text("What your last \(min(6, state.journal.count)) bakes are telling us")
                        .font(Typography.display(18, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                }
                Spacer()
                Button("See journal →") { state.goTo(.journal) }
                    .ccGhost(compact: true)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)

            HStack(spacing: 1) {
                ForEach(Array(state.insights.enumerated()), id: \.offset) { _, ins in
                    InsightTile(insight: ins)
                }
            }
            .background(Theme.border1)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border1, lineWidth: 1))
        .shadow(color: Theme.shadowCard, radius: 1, y: 1)
    }
}

private struct InsightTile: View {
    let insight: Insight
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                CCIconView(icon: iconFor(insight.kind), size: 14, color: Theme.primary)
                Kicker(insight.kind.rawValue)
            }
            Text(insight.headline)
                .font(Typography.ui(13.5, weight: .medium))
                .foregroundStyle(Theme.slate900)
                .multilineTextAlignment(.leading)
            Text(insight.detail)
                .font(Typography.ui(11.5))
                .foregroundStyle(Theme.slate500)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }

    private func iconFor(_ kind: InsightKind) -> CCIcon {
        switch kind {
        case .trend: return .graph
        case .flour: return .book
        case .temp:  return .thermo
        }
    }
}

#Preview("Home") {
    HomeScreen(state: AppState(persistence: PersistenceController(filename: "preview-home.json")))
        .padding()
        .background(Theme.surface1)
        .frame(width: 1100, height: 800)
}
