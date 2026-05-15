import SwiftUI

// iPhone Active Bake — single-column variant of `ActiveBakeScreen`.
// Reuses the same `AppState` mutations as the iPad surface; only the
// layout differs. Proof-oven controls move to a bottom sheet rather
// than an inline expanding panel so the primary stage card stays
// visible at all times.

struct PhoneActiveBakeScreen: View {
    var state: AppState
    @State private var photoTargetStage: Int? = nil
    @State private var completeSheetOpen: Bool = false
    @State private var proofOvenSheetOpen: Bool = false
    @State private var proofOvenActive: Bool = false
    @State private var proofOvenTempC: Double = 26

    @ViewBuilder
    var body: some View {
        Group {
            if let bake = state.activeBake, let recipe = state.recipe(bake.recipeId) {
                content(bake: bake, recipe: recipe)
            } else {
                PhoneEmptyActiveBakeView { state.goTo(.scheduler) }
            }
        }
        .task { await state.refreshNotificationAuthStatus() }
        .photoPicker(isPresented: Binding(
            get: { photoTargetStage != nil },
            set: { if !$0 { photoTargetStage = nil } }
        )) { image in
            if let stage = photoTargetStage {
                state.addPhoto(image, toStage: stage)
            }
            photoTargetStage = nil
        }
        .sheet(isPresented: $completeSheetOpen) {
            PhoneCompleteBakeSheet { rating, note in
                state.completeBake(rating: rating, note: note)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $proofOvenSheetOpen) {
            PhoneProofOvenSheet(
                state: state,
                proofOvenActive: $proofOvenActive,
                proofOvenTempC: $proofOvenTempC
            )
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private func content(bake: ActiveBake, recipe: Recipe) -> some View {
        let stage = recipe.stages[bake.currentStageIndex]
        let baseDur = stage.durationMin
        let adjustedDur = proofOvenActive
            ? max(Int(Double(baseDur) * max(0.55, 1 - (proofOvenTempC - 22) * 0.06)), 30)
            : baseDur

        ScrollView {
            VStack(spacing: PhoneTheme.cardSpacing) {
                if state.notificationAuthStatus == .denied {
                    PhoneNotificationsDeniedBanner()
                }

                stageCard(bake: bake, recipe: recipe, stage: stage,
                          baseDur: baseDur, adjustedDur: adjustedDur)

                actionsCard(bake: bake, stage: stage)

                if let kitchenLine = kitchenInsightLine(bake: bake, recipe: recipe, stage: stage) {
                    insightCard(text: kitchenLine)
                }

                recipeHeaderCard(bake: bake, recipe: recipe)

                timelineCard(bake: bake, recipe: recipe)
            }
            .padding(.horizontal, PhoneTheme.screenHPad)
            .padding(.top, PhoneTheme.screenVPad)
            .padding(.bottom, PhoneTheme.sectionSpacing)
        }
        .background(Theme.surface1)
    }

    // MARK: Stage card

    private func stageCard(bake: ActiveBake, recipe: Recipe, stage: Stage,
                           baseDur: Int, adjustedDur: Int) -> some View {
        SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Kicker("Now · stage \(bake.currentStageIndex + 1) of \(recipe.stages.count)",
                                   color: Theme.primary)
                            Text(stage.kind.rawValue)
                                .font(Typography.display(24, weight: .medium))
                                .foregroundStyle(Theme.slate900)
                            if let note = stage.note {
                                Text(note)
                                    .font(Typography.ui(13))
                                    .foregroundStyle(Theme.slate700)
                            }
                        }
                        Spacer()
                        if stage.kind == .bulkFold {
                            RingProgress(value: Double(bake.foldsDone) / Double(max(bake.totalFolds, 1)),
                                          size: 64, stroke: 5) {
                                VStack(spacing: 0) {
                                    Text("\(bake.foldsDone)/\(bake.totalFolds)")
                                        .font(Typography.mono(15, weight: .semibold))
                                        .foregroundStyle(Theme.slate900)
                                    Text("folds")
                                        .font(Typography.ui(8.5))
                                        .foregroundStyle(Theme.slate500)
                                }
                            }
                        } else {
                            RingProgress(value: bake.stageProgress,
                                          size: 64, stroke: 5) {
                                Text("\(Int(bake.stageProgress * 100))%")
                                    .font(Typography.mono(13, weight: .semibold))
                                    .foregroundStyle(Theme.slate900)
                            }
                        }
                    }

                    if stage.kind == .bulkFold {
                        HStack(spacing: 6) {
                            ForEach(0..<bake.totalFolds, id: \.self) { i in
                                PhoneFoldChip(index: i + 1,
                                               done: i < bake.foldsDone,
                                               current: i == bake.foldsDone)
                                    .onTapGesture { state.markFold(i + 1) }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityLabel("Fold \(i + 1) of \(bake.totalFolds)")
                                    .accessibilityValue(i < bake.foldsDone ? "Done"
                                                        : (i == bake.foldsDone ? "Up next" : "Pending"))
                            }
                        }
                    }

                    if proofOvenActive {
                        HStack(spacing: 8) {
                            CCIconView(icon: .sparkle, size: 13, color: Theme.primary)
                            Text("Proofing oven · \(Int(proofOvenTempC))°C → \(CCFormat.duration(adjustedDur)) (saves \(CCFormat.duration(baseDur - adjustedDur)))")
                                .font(Typography.ui(11.5))
                                .foregroundStyle(Theme.slate700)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.primaryTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(PhoneTheme.cardPad)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [Theme.primaryTint, Color.white],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
        }
    }

    // MARK: Actions card (primary + secondary buttons)

    @ViewBuilder
    private func actionsCard(bake: ActiveBake, stage: Stage) -> some View {
        VStack(spacing: 10) {
            primaryActionButton(bake: bake, stage: stage)
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Button { photoTargetStage = bake.currentStageIndex } label: {
                    Label("Photo", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .ccSecondary()

                Button { proofOvenSheetOpen = true } label: {
                    Label(proofOvenActive ? "\(Int(proofOvenTempC))°C" : "Proofing oven",
                          systemImage: "thermometer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CCButtonStyle(variant: proofOvenActive ? .primary : .secondary))

                Button { state.skipStage() } label: {
                    Label("Skip", systemImage: "forward.fill")
                        .frame(maxWidth: .infinity)
                }
                .ccGhost()
                .disabled(bake.isComplete)
            }
        }
    }

    /// Morphs through the three meaningful primary actions like the iPad
    /// version. Single label across the full width on iPhone for thumb reach.
    @ViewBuilder
    private func primaryActionButton(bake: ActiveBake, stage: Stage) -> some View {
        if bake.isComplete {
            Button { completeSheetOpen = true } label: {
                Label("Complete bake", systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity)
            }
            .ccPrimary()
        } else if stage.kind == .bulkFold && bake.foldsDone < bake.totalFolds {
            Button { state.incrementFold() } label: {
                Label("Mark fold \(bake.foldsDone + 1) done", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .ccPrimary()
        } else {
            Button { state.advanceStage() } label: {
                Label("Mark \(stage.kind.rawValue) done", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .ccPrimary()
        }
    }

    // MARK: Insight card

    private func insightCard(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            CCIconView(icon: .sparkle, size: 15, color: Theme.accent)
                .padding(.top, 2)
            Text(text)
                .font(Typography.ui(12.5))
                .foregroundStyle(Theme.slate700)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.slate50, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func kitchenInsightLine(bake: ActiveBake, recipe: Recipe, stage: Stage) -> String? {
        let timings = Analytics.kitchenTimings(for: recipe.id, in: state.journal)
        guard let timing = timings[bake.currentStageIndex] else { return nil }
        let avgLabel = CCFormat.duration(timing.averageMinutes)
        let bakesLabel = timing.bakes == 1 ? "1 bake" : "\(timing.bakes) bakes"
        let kitchenLabel = "Your kitchen at \(Int(bake.kitchenTempC))°C has averaged \(avgLabel) for \(stage.kind.rawValue.lowercased()) in your last \(bakesLabel)"
        let baseline = stage.durationMin
        guard baseline > 0 else { return kitchenLabel + "." }
        let delta = timing.averageMinutes - baseline
        if abs(delta) < 5 {
            return kitchenLabel + " — about the recipe baseline."
        }
        let sign = delta > 0 ? "longer" : "shorter"
        return kitchenLabel + " — \(CCFormat.duration(abs(delta))) \(sign) than the recipe baseline."
    }

    // MARK: Recipe header

    private func recipeHeaderCard(bake: ActiveBake, recipe: Recipe) -> some View {
        SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    BreadPhoto(assetName: recipe.photo, kind: .crumb, height: 180)
                    LinearGradient(colors: [.clear, .black.opacity(0.65)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 180)
                    VStack(alignment: .leading, spacing: 6) {
                        StatusPill(kind: .good, text: "Active", dot: true)
                        Text(recipe.title)
                            .font(Typography.display(20, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
                .frame(height: 180)
                .clipped()

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        statBlock("Hydration", "\(Int(recipe.hydrationPct))%")
                        statBlock("Total", CCFormat.weight(grams: recipe.totalDoughGrams, units: state.units))
                    }
                    HStack(spacing: 12) {
                        statBlock("Kitchen", "\(Int(bake.kitchenTempC))°C")
                        statBlock("Starter", state.starter(bake.starterId ?? "")?.name ?? "—")
                    }
                    SoftDivider()
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Kicker("Started")
                            Text(CCFormat.clockShort.string(from: bake.startedAt))
                                .font(Typography.mono(13, weight: .medium))
                                .foregroundStyle(Theme.slate900)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Kicker("Bake out")
                            Text(CCFormat.clockShort.string(from: bake.bakeOutAt))
                                .font(Typography.mono(13, weight: .medium))
                                .foregroundStyle(Theme.slate900)
                        }
                    }
                }
                .padding(PhoneTheme.cardPad)
            }
        }
    }

    private func statBlock(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Kicker(label, size: 10)
            Text(value)
                .font(Typography.mono(14, weight: .semibold))
                .foregroundStyle(Theme.slate900)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Timeline

    private func timelineCard(bake: ActiveBake, recipe: Recipe) -> some View {
        let starts = stageStartTimes(bake: bake, recipe: recipe)
        let totalPhotos = bake.stagePhotos.values.reduce(0) { $0 + $1.count }
        return SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Kicker("Timeline")
                    if totalPhotos == 0 {
                        Text("\(CCFormat.endToEndHours(recipe.stages.reduce(0) { $0 + $1.durationMin })) · tap the camera to log a photo per stage")
                            .font(Typography.ui(11))
                            .foregroundStyle(Theme.slate500)
                    } else {
                        (Text("\(CCFormat.endToEndHours(recipe.stages.reduce(0) { $0 + $1.durationMin })) · ")
                            .font(Typography.ui(11)).foregroundStyle(Theme.slate500)
                        + Text("\(totalPhotos)")
                            .font(Typography.mono(11, weight: .semibold))
                            .foregroundStyle(Theme.slate700)
                        + Text(totalPhotos == 1 ? " photo this bake" : " photos this bake")
                            .font(Typography.ui(11)).foregroundStyle(Theme.slate500))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PhoneTheme.cardPad)
                .padding(.vertical, 12)

                ForEach(Array(recipe.stages.enumerated()), id: \.offset) { idx, stage in
                    let status = bake.history.first(where: { $0.stageIndex == idx })?.status ?? .pending
                    timelineRow(idx: idx, stage: stage, status: status,
                                startTime: starts[idx], bake: bake)
                }
                .padding(.bottom, 10)
            }
        }
    }

    private func stageStartTimes(bake: ActiveBake, recipe: Recipe) -> [Date] {
        var times: [Date] = []
        var cursor = bake.startedAt
        for stage in recipe.stages {
            times.append(cursor)
            cursor = Calendar.current.date(byAdding: .minute, value: stage.durationMin, to: cursor) ?? cursor
        }
        return times
    }

    private func timelineRow(idx: Int, stage: Stage, status: StepStatus,
                             startTime: Date, bake: ActiveBake) -> some View {
        let isActive = status == .active
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(CCFormat.clockShort.string(from: startTime))
                    .font(Typography.mono(11))
                    .foregroundStyle(Theme.slate500)
                Text(CCFormat.stageDuration(stage))
                    .font(Typography.mono(10))
                    .foregroundStyle(Theme.slate400)
            }
            .frame(width: 64, alignment: .leading)
            .padding(.top, 2)

            PhoneTimelineDot(status: status).padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(stage.kind.rawValue)
                    .font(Typography.ui(13, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(status == .done ? Theme.slate500 : Theme.slate900)
                    .strikethrough(status == .done)

                if isActive, let note = bake.history.first(where: { $0.stageIndex == idx })?.note {
                    Text(note).font(Typography.ui(11)).foregroundStyle(Theme.primary)
                } else if status == .done, let note = bake.history.first(where: { $0.stageIndex == idx })?.note {
                    Text(note).font(Typography.ui(11)).foregroundStyle(Theme.slate500)
                } else if let note = stage.note, isActive {
                    Text(note).font(Typography.ui(11)).foregroundStyle(Theme.slate500)
                }

                let photos = bake.stagePhotos[idx] ?? []
                if !photos.isEmpty || status != .pending {
                    HStack(spacing: 6) {
                        ForEach(photos) { photo in
                            BreadPhoto(assetName: photo.assetName, kind: .crumb, height: 40)
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        if status != .pending {
                            Button(action: { photoTargetStage = idx }) {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(isActive ? Theme.primary : Theme.slate300,
                                            style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                    .frame(width: 40, height: 40)
                                    .overlay(CCIconView(icon: .camera, size: 13,
                                                         color: isActive ? Theme.primary : Theme.slate400))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add photo to \(stage.kind.rawValue)")
                        }
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PhoneTheme.cardPad)
        .padding(.vertical, 10)
        .background(isActive ? Theme.primaryTint : .clear)
        .overlay(alignment: .top) {
            if idx > 0 { Rectangle().fill(Theme.border1).frame(height: 1) }
        }
    }
}

// MARK: - iPhone helper subviews (compact analogs of the iPad-private structs)

private struct PhoneFoldChip: View {
    let index: Int
    let done: Bool
    let current: Bool
    var body: some View {
        VStack(spacing: 1) {
            Text("F\(index)")
                .font(Typography.ui(9, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(done ? .white.opacity(0.85) : Theme.slate500)
            Text(done ? "✓" : (current ? "now" : "—"))
                .font(Typography.mono(11, weight: .medium))
                .foregroundStyle(done ? .white : Theme.slate600)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(done ? Theme.primary : .white,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(done ? Theme.primary : (current ? Theme.primaryTint2 : Theme.border1),
                        lineWidth: current ? 1.5 : 1)
        )
    }
}

private struct PhoneTimelineDot: View {
    let status: StepStatus
    var body: some View {
        switch status {
        case .done:
            ZStack {
                Circle().fill(Theme.success50).frame(width: 20, height: 20)
                CCIconView(icon: .check, size: 11, color: Theme.success700)
            }
        case .active:
            ZStack {
                Circle().fill(Theme.primary).frame(width: 20, height: 20)
                Circle().fill(.white).frame(width: 6, height: 6)
            }
            .background(Circle().fill(Theme.primaryRing).frame(width: 28, height: 28))
        default:
            Circle()
                .strokeBorder(Theme.slate300, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .background(Circle().fill(.white))
                .frame(width: 20, height: 20)
        }
    }
}

private struct PhoneNotificationsDeniedBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.warm50)
                    .frame(width: 30, height: 30)
                CCIconView(icon: .bell, size: 14, color: Theme.warm700)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Reminders off")
                    .font(Typography.ui(13, weight: .semibold))
                    .foregroundStyle(Theme.slate900)
                Text("Turn notifications on in Settings to get pinged at each step.")
                    .font(Typography.ui(11.5))
                    .foregroundStyle(Theme.slate700)
            }
            Spacer(minLength: 0)
            Button("Open") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .ccGhost(compact: true)
        }
        .padding(12)
        .background(Theme.warm50, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.warm.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct PhoneEmptyActiveBakeView: View {
    let onScheduler: () -> Void
    var body: some View {
        ScrollView {
            SurfaceCard {
                VStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Theme.primaryTint).frame(width: 56, height: 56)
                        CCIconView(icon: .play, size: 22, color: Theme.primary)
                    }
                    VStack(spacing: 4) {
                        Text("No active bake")
                            .font(Typography.display(20, weight: .medium))
                            .foregroundStyle(Theme.slate900)
                        Text("Pick a recipe and target time on the Scheduler to kick one off.")
                            .font(Typography.ui(13))
                            .foregroundStyle(Theme.slate600)
                            .multilineTextAlignment(.center)
                    }
                    Button(action: onScheduler) {
                        Label("Open Scheduler", systemImage: "clock")
                            .frame(maxWidth: .infinity)
                    }
                    .ccPrimary()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
            .padding(.horizontal, PhoneTheme.screenHPad)
            .padding(.top, PhoneTheme.screenVPad)
        }
        .background(Theme.surface1)
    }
}

private struct PhoneCompleteBakeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onComplete: (Int, String) -> Void
    @State private var rating: Int = 5
    @State private var note: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker("Wrap up")
                    Text("Log this bake")
                        .font(Typography.display(22, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Rating")
                        .font(Typography.ui(12, weight: .medium))
                        .foregroundStyle(Theme.slate700)
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { i in
                            Button(action: { rating = i }) {
                                Image(systemName: i <= rating ? "star.fill" : "star")
                                    .font(.system(size: 24, weight: .regular))
                                    .foregroundStyle(i <= rating ? Theme.warm : Theme.slate300)
                                    .accessibilityHidden(true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(i) star\(i == 1 ? "" : "s")")
                            .accessibilityAddTraits(i == rating ? [.isSelected] : [])
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(Typography.ui(12, weight: .medium))
                        .foregroundStyle(Theme.slate700)
                    TextField("How did it go? Crumb, crust, bulk timing…",
                              text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .font(Typography.ui(13))
                        .padding(10)
                        .background(Color.white,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Theme.border1, lineWidth: 1)
                        )
                }

                HStack {
                    Button("Cancel") { dismiss() }
                        .ccGhost(compact: true)
                    Spacer()
                    Button {
                        onComplete(rating, note)
                        dismiss()
                    } label: {
                        Label("Save bake", systemImage: "checkmark.seal.fill")
                    }.ccPrimary()
                }
            }
            .padding(20)
        }
        .background(Theme.surface1)
    }
}

private struct PhoneProofOvenSheet: View {
    var state: AppState
    @Binding var proofOvenActive: Bool
    @Binding var proofOvenTempC: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker("Stage override · not in recipe", color: Theme.primaryDeep)
                    Text("Proofing oven")
                        .font(Typography.display(20, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                }
                Spacer()
                Toggle("", isOn: $proofOvenActive)
                    .labelsHidden()
                    .tint(Theme.primary)
            }

            Text("Kitchen is \(String(format: "%.1f", state.kitchenTempC))°C. Holding the dough at a steady temp shortens the active stage proportionally.")
                .font(Typography.ui(12.5))
                .foregroundStyle(Theme.slate700)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Target temperature")
                        .font(Typography.ui(12)).foregroundStyle(Theme.slate700)
                    Spacer()
                    Text("\(Int(proofOvenTempC))°C")
                        .font(Typography.mono(13, weight: .semibold))
                        .foregroundStyle(Theme.slate900)
                }
                Slider(value: $proofOvenTempC, in: 22...32, step: 1)
                    .tint(Theme.primary)
                    .onChange(of: proofOvenTempC) { _, _ in proofOvenActive = true }
                HStack {
                    Text("22° kitchen"); Spacer(); Text("26° warm"); Spacer(); Text("30° aggressive")
                }
                .font(Typography.ui(10)).foregroundStyle(Theme.slate500)
            }

            HStack(spacing: 6) {
                ForEach([(24, "Gentle"), (26, "Warm"), (28, "Fast")], id: \.0) { t, label in
                    TagPill(label: "\(label) · \(t)°", active: Int(proofOvenTempC) == t) {
                        proofOvenTempC = Double(t); proofOvenActive = true
                    }
                }
            }

            Button { dismiss() } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .ccPrimary()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Phone Active Bake") {
    NavigationStack {
        PhoneActiveBakeScreen(state: AppState(persistence: PersistenceController(filename: "preview-phone-bake.json")))
            .navigationTitle("Bake")
            .navigationBarTitleDisplayMode(.inline)
    }
}
