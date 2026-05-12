import SwiftUI

// Active bake screen — recipe card + Live Activity preview on the left,
// current stage + timeline on the right. Stage clock times are computed from
// `bake.startedAt` plus cumulative durations, not hardcoded.

struct ActiveBakeScreen: View {
    var state: AppState
    @State private var proofOvenOpen: Bool = false
    @State private var proofOvenActive: Bool = false
    @State private var proofOvenTempC: Double = 26

    // Photo-picker state: when non-nil, the user wants to add a photo to that
    // stage index. We back the .photoPicker modifier with a derived Bool
    // binding so it follows our enum nicely.
    @State private var photoTargetStage: Int? = nil

    @State private var completeSheetOpen: Bool = false

    @ViewBuilder
    var body: some View {
        VStack(spacing: 16) {
            if state.notificationAuthStatus == .denied {
                NotificationsDeniedBanner()
            }
            Group {
                if let bake = state.activeBake, let recipe = state.recipe(bake.recipeId) {
                    content(bake: bake, recipe: recipe)
                } else {
                    EmptyActiveBakeView { state.goTo(.scheduler) }
                }
            }
        }
        .task {
            // Re-query on appear in case the user toggled the system permission
            // while we weren't looking (e.g. Settings → Notifications).
            await state.refreshNotificationAuthStatus()
        }
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
            CompleteBakeSheet { rating, note in
                state.completeBake(rating: rating, note: note)
            }
        }
    }

    @ViewBuilder
    private func content(bake: ActiveBake, recipe: Recipe) -> some View {
        let stage = recipe.stages[bake.currentStageIndex]
        let baseDur = stage.durationMin
        let adjustedDur = proofOvenActive
            ? max(Int(Double(baseDur) * max(0.55, 1 - (proofOvenTempC - 22) * 0.06)), 30)
            : baseDur
        let saved = baseDur - adjustedDur

        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 16) {
                recipeHeaderCard(bake: bake, recipe: recipe)
                liveActivityCard(bake: bake, recipe: recipe, stage: stage)
            }
            .frame(width: 360)

            VStack(spacing: 16) {
                currentStageCard(bake: bake, recipe: recipe, stage: stage,
                                  adjustedDur: adjustedDur, baseDur: baseDur, saved: saved)
                timelineCard(bake: bake, recipe: recipe)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Recipe header card

    private func recipeHeaderCard(bake: ActiveBake, recipe: Recipe) -> some View {
        SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    BreadPhoto(assetName: recipe.photo, kind: .crumb, height: 160)
                    LinearGradient(colors: [.clear, .black.opacity(0.65)],
                                   startPoint: .top, endPoint: .bottom)
                    .frame(height: 160)
                    VStack(alignment: .leading, spacing: 6) {
                        StatusPill(kind: .good, text: "Active", dot: true)
                        Text(recipe.title)
                            .font(Typography.display(22, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
                .frame(height: 160)
                .clipped()
                // Stage 27 — drag a photo from Photos / Files / Safari
                // onto the header to attach it to the current stage.
                // Goes through the same AppState.addPhoto path the picker
                // uses, so photo-error handling + persistence stay
                // single-source.
                .dropDestination(for: Data.self) { items, _ in
                    guard let data = items.first,
                          let image = UIImage(data: data) else { return false }
                    return state.addPhoto(image, toStage: bake.currentStageIndex) != nil
                }

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        statBlock("Hydration", "\(Int(recipe.hydrationPct))%")
                        statBlock("Total weight", CCFormat.weight(grams: recipe.totalDoughGrams, units: state.units))
                    }
                    HStack(spacing: 12) {
                        statBlock("Kitchen", "\(Int(bake.kitchenTempC))°C")
                        statBlock("Starter", state.starter(bake.starterId ?? "")?.name ?? "—")
                    }
                    SoftDivider()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Kicker("Started")
                            Text(CCFormat.clockShort.string(from: bake.startedAt))
                                .font(Typography.mono(13, weight: .medium))
                                .foregroundStyle(Theme.slate900)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Kicker("Bake out")
                            Text(CCFormat.clockShort.string(from: bake.bakeOutAt))
                                .font(Typography.mono(13, weight: .medium))
                                .foregroundStyle(Theme.slate900)
                        }
                    }
                }
                .padding(18)
            }
        }
    }

    private func statBlock(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Kicker(label, size: 10)
            Text(value)
                .font(Typography.mono(16, weight: .semibold))
                .foregroundStyle(Theme.slate900)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Live activity preview

    private func liveActivityCard(bake: ActiveBake, recipe: Recipe, stage: Stage) -> some View {
        SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker("Live activity")
                    Text("Lock screen · Dynamic Island")
                        .font(Typography.ui(12)).foregroundStyle(Theme.slate500)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 10)

                HStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.primary)
                        .frame(width: 36, height: 36)
                        .overlay(Text("cc").font(Typography.display(13, weight: .bold)).foregroundStyle(.white).kerning(-0.4))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(recipe.title)
                            .font(Typography.ui(13, weight: .semibold)).foregroundStyle(.white)
                        Text("\(stage.kind.rawValue) · \(liveActivityDetail(bake: bake, recipe: recipe, stage: stage))")
                            .font(Typography.ui(11)).foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    RingProgress(value: bake.stageProgress, size: 36, stroke: 3,
                                  color: .white, trackColor: .white.opacity(0.18)) {
                        Text("\(Int(bake.stageProgress * 100))%")
                            .font(Typography.ui(9, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(14)
                .background(Theme.slate950, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: Current stage card

    private func currentStageCard(bake: ActiveBake, recipe: Recipe, stage: Stage,
                                  adjustedDur: Int, baseDur: Int, saved: Int) -> some View {
        SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Kicker("Now · stage \(bake.currentStageIndex + 1) of \(recipe.stages.count)",
                                   color: Theme.primary)
                            Text(stage.kind.rawValue)
                                .font(Typography.display(32, weight: .medium))
                                .foregroundStyle(Theme.slate900)
                            if let note = stage.note {
                                Text(note).font(Typography.ui(13)).foregroundStyle(Theme.slate700)
                            }
                        }
                        // Micro-fade when the stage swaps so the title doesn't
                        // pop between stages. Honors reduce-motion via the
                        // shell's environment value.
                        .id(bake.currentStageIndex)
                        .transition(.opacity)
                        .animation(state.reduceMotion ? nil : .easeInOut(duration: 0.18),
                                    value: bake.currentStageIndex)
                        Spacer()
                        RingProgress(value: Double(bake.foldsDone) / Double(bake.totalFolds),
                                      size: 84, stroke: 6) {
                            VStack(spacing: 0) {
                                Text("\(bake.foldsDone)/\(bake.totalFolds)")
                                    .font(Typography.mono(22, weight: .semibold))
                                    .foregroundStyle(Theme.slate900)
                                Text("folds").font(Typography.ui(10)).foregroundStyle(Theme.slate500)
                            }
                        }
                        .animation(state.reduceMotion ? nil : .easeOut(duration: 0.25),
                                    value: bake.foldsDone)
                    }
                    HStack(spacing: 8) {
                        ForEach(0..<bake.totalFolds, id: \.self) { i in
                            FoldChip(index: i + 1, done: i < bake.foldsDone, current: i == bake.foldsDone)
                                .onTapGesture { state.markFold(i + 1) }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel("Fold \(i + 1) of \(bake.totalFolds)")
                                .accessibilityValue(i < bake.foldsDone ? "Done" : (i == bake.foldsDone ? "Up next" : "Pending"))
                        }
                    }
                    .padding(.top, 18)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(
                    LinearGradient(colors: [Theme.primaryTint, Color.white],
                                   startPoint: .top, endPoint: .bottom)
                )

                HStack(spacing: 10) {
                    primaryActionButton(bake: bake, stage: stage)

                    Button { photoTargetStage = bake.currentStageIndex } label: {
                        Label("Add photo", systemImage: "camera")
                    }.ccSecondary()

                    Button {
                        proofOvenOpen.toggle()
                        if !proofOvenActive { proofOvenActive = proofOvenOpen }
                    } label: {
                        Label(proofOvenActive ? "Proofing oven · \(Int(proofOvenTempC))°C" : "Use proofing oven",
                              systemImage: "thermometer")
                    }
                    .buttonStyle(CCButtonStyle(variant: proofOvenActive ? .primary : .secondary))

                    Spacer()
                    Button("Skip stage") { state.skipStage() }
                        .ccGhost(compact: true)
                        .disabled(bake.isComplete)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.border1).frame(height: 1) }

                if proofOvenOpen {
                    proofOvenPanel(bake: bake, stage: stage,
                                    adjustedDur: adjustedDur, baseDur: baseDur, saved: saved)
                }

                HStack(spacing: 10) {
                    CCIconView(icon: .sparkle, size: 15, color: Theme.accent)
                    Text("In your kitchen at \(Int(bake.kitchenTempC))°C, this dough has averaged 4h 45m bulk in your last 5 bakes — 30 min longer than the recipe baseline.")
                        .font(Typography.ui(12.5))
                        .foregroundStyle(Theme.slate700)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Theme.slate50)
            }
        }
    }

    private func proofOvenPanel(bake: ActiveBake, stage: Stage,
                                 adjustedDur: Int, baseDur: Int, saved: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker("Stage override · not in recipe", color: Theme.primaryDeep)
                    Text("Proofing oven · hold \(stage.kind.rawValue) at a steady temp")
                        .font(Typography.display(18, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                    Text("Kitchen is \(String(format: "%.1f", state.kitchenTempC))°C. Holding at \(Int(proofOvenTempC))°C shortens this stage to \(CCFormat.duration(adjustedDur)) (saves \(CCFormat.duration(saved))). Recipe baseline \(CCFormat.duration(baseDur)).")
                        .font(Typography.ui(12.5))
                        .foregroundStyle(Theme.slate700)
                }
                Spacer()
                Toggle("", isOn: $proofOvenActive).labelsHidden().tint(Theme.primary)
            }

            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Target temperature")
                            .font(Typography.ui(12)).foregroundStyle(Theme.slate700)
                        Spacer()
                        Text("\(Int(proofOvenTempC))°C")
                            .font(Typography.mono(12, weight: .semibold))
                            .foregroundStyle(Theme.slate900)
                    }
                    Slider(value: $proofOvenTempC, in: 22...32, step: 1)
                        .tint(Theme.primary)
                        .onChange(of: proofOvenTempC) { _, _ in proofOvenActive = true }
                    HStack {
                        Text("22° kitchen"); Spacer(); Text("26° warm"); Spacer(); Text("30° aggressive")
                    }
                    .font(Typography.ui(10.5)).foregroundStyle(Theme.slate500)
                }
                HStack(spacing: 6) {
                    ForEach([(24, "Gentle"), (26, "Warm"), (28, "Fast")], id: \.0) { t, label in
                        TagPill(label: "\(label) · \(t)°", active: Int(proofOvenTempC) == t) {
                            proofOvenTempC = Double(t); proofOvenActive = true
                        }
                    }
                }
                .frame(width: 220)
            }

            HStack(spacing: 8) {
                CCIconView(icon: .sparkle, size: 14, color: Theme.primary)
                Text(reflowLine(bake: bake, saved: saved, adjustedDur: adjustedDur))
                    .font(Typography.ui(12)).foregroundStyle(Theme.slate700)
                Spacer()
            }
            .padding(8)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.primaryTint2, lineWidth: 1))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Theme.primaryTint)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.primaryTint2).frame(height: 1) }
    }

    /// Build the proof-oven "schedule reflowed" line from the actual
    /// bake state. Previously a static demo string; now derives from the
    /// current bake-out (pulled forward by `saved` minutes) and the
    /// shortened stage duration.
    private func reflowLine(bake: ActiveBake, saved: Int, adjustedDur: Int) -> String {
        let pulled = Calendar.current.date(byAdding: .minute,
                                            value: -saved,
                                            to: bake.bakeOutAt) ?? bake.bakeOutAt
        let stageLabel = CCFormat.duration(adjustedDur)
        let saveLabel = CCFormat.duration(saved)
        let newTime = CCFormat.clockShort.string(from: pulled)
        let oldTime = CCFormat.clockShort.string(from: bake.bakeOutAt)
        return "Stage shortens to \(stageLabel) (saves \(saveLabel)). Bake out \(newTime) (was \(oldTime))."
    }

    // MARK: Timeline card

    private func timelineCard(bake: ActiveBake, recipe: Recipe) -> some View {
        let starts = stageStartTimes(bake: bake, recipe: recipe)
        let totalPhotos = bake.stagePhotos.values.reduce(0) { $0 + $1.count }
        return SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Kicker("Timeline")
                    if totalPhotos == 0 {
                        Text("\(CCFormat.endToEndHours(recipe.stages.reduce(0) { $0 + $1.durationMin })) · tap the camera in each stage to log a photo")
                            .font(Typography.ui(11))
                            .foregroundStyle(Theme.slate500)
                    } else {
                        Text("\(CCFormat.endToEndHours(recipe.stages.reduce(0) { $0 + $1.durationMin })) · ")
                            .font(Typography.ui(11)).foregroundStyle(Theme.slate500)
                        + Text("\(totalPhotos)")
                            .font(Typography.mono(11, weight: .semibold))
                            .foregroundStyle(Theme.slate700)
                        + Text(totalPhotos == 1 ? " photo this bake" : " photos this bake")
                            .font(Typography.ui(11)).foregroundStyle(Theme.slate500)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)

                ForEach(Array(recipe.stages.enumerated()), id: \.offset) { idx, stage in
                    let status = bake.history.first(where: { $0.stageIndex == idx })?.status ?? .pending
                    timelineRow(idx: idx, stage: stage, status: status,
                                startTime: starts[idx], bake: bake)
                }
                .padding(.bottom, 12)
            }
        }
    }

    /// Each stage's start time is `bake.startedAt + sum(durations of earlier stages)`.
    /// No more hardcoded 4:12 PM baseline — derives entirely from `bake.startedAt`.
    private func stageStartTimes(bake: ActiveBake, recipe: Recipe) -> [Date] {
        var times: [Date] = []
        var cursor = bake.startedAt
        for stage in recipe.stages {
            times.append(cursor)
            cursor = Calendar.current.date(byAdding: .minute, value: stage.durationMin, to: cursor) ?? cursor
        }
        return times
    }

    /// Subtitle shown under the recipe title in the Live Activity preview.
    /// Folds-remaining count for bulk-fold stages; otherwise a position hint
    /// so non-fold stages don't show "0/4 folds."
    private func liveActivityDetail(bake: ActiveBake, recipe: Recipe, stage: Stage) -> String {
        if bake.isComplete { return "ready to log" }
        if stage.kind == .bulkFold {
            return "\(bake.foldsDone)/\(bake.totalFolds) folds"
        }
        return "stage \(bake.currentStageIndex + 1) of \(recipe.stages.count)"
    }

    /// One button that morphs through the three meaningful primary actions:
    /// - bulk-fold stage with folds remaining → bump the fold counter
    /// - any other in-progress stage → mark the stage done
    /// - bake fully complete → open the journal-entry sheet
    @ViewBuilder
    private func primaryActionButton(bake: ActiveBake, stage: Stage) -> some View {
        if bake.isComplete {
            Button { completeSheetOpen = true } label: {
                Label("Complete bake", systemImage: "checkmark.seal.fill")
            }.ccPrimary()
        } else if stage.kind == .bulkFold && bake.foldsDone < bake.totalFolds {
            Button { state.incrementFold() } label: {
                Label("Mark fold \(bake.foldsDone + 1) done", systemImage: "checkmark")
            }.ccPrimary()
        } else {
            Button { state.advanceStage() } label: {
                Label("Mark \(stage.kind.rawValue) done", systemImage: "checkmark")
            }.ccPrimary()
        }
    }

    private func timelineRow(idx: Int, stage: Stage, status: StepStatus,
                              startTime: Date, bake: ActiveBake) -> some View {
        let isActive = status == .active
        return HStack(alignment: .top, spacing: 14) {
            Text(CCFormat.clockShort.string(from: startTime))
                .font(Typography.mono(12))
                .foregroundStyle(Theme.slate500)
                .frame(width: 100, alignment: .leading)
                .padding(.top, 4)

            TimelineDot(status: status).padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(stage.kind.rawValue)
                    .font(Typography.ui(13.5, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(status == .done ? Theme.slate500 : Theme.slate900)
                    .strikethrough(status == .done)
                if isActive, let note = bake.history.first(where: { $0.stageIndex == idx })?.note {
                    Text(note)
                        .font(Typography.ui(11.5))
                        .foregroundStyle(Theme.primary)
                } else if status == .done, let note = bake.history.first(where: { $0.stageIndex == idx })?.note {
                    Text(note).font(Typography.ui(11.5)).foregroundStyle(Theme.slate500)
                } else if let note = stage.note, isActive {
                    Text(note).font(Typography.ui(11.5)).foregroundStyle(Theme.slate500)
                }

                let photos = bake.stagePhotos[idx] ?? []
                if !photos.isEmpty || status != .pending {
                    HStack(spacing: 6) {
                        ForEach(photos) { photo in
                            BreadPhoto(assetName: photo.assetName, kind: .crumb, height: 44)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        if status != .pending {
                            Button(action: { photoTargetStage = idx }) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isActive ? Theme.primary : Theme.slate300,
                                            style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                    .frame(width: 44, height: 44)
                                    .overlay(CCIconView(icon: .camera, size: 15,
                                                         color: isActive ? Theme.primary : Theme.slate400))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add photo to \(stage.kind.rawValue)")
                        }
                    }
                    .padding(.top, 8)
                }
            }

            Spacer()

            Text(CCFormat.stageDuration(stage))
                .font(Typography.mono(11))
                .foregroundStyle(Theme.slate500)
                .padding(.top, 4)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(isActive ? Theme.primaryTint : .clear)
        .overlay(alignment: .top) {
            if idx > 0 { Rectangle().fill(Theme.border1).frame(height: 1) }
        }
    }
}

// MARK: - Helper subviews

private struct FoldChip: View {
    let index: Int
    let done: Bool
    let current: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("FOLD \(index)")
                .font(Typography.ui(10, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(done ? .white.opacity(0.85) : Theme.slate500)
            Text(done ? "Done" : (current ? "in 14m" : "+30m"))
                .font(Typography.mono(13, weight: .medium))
                .foregroundStyle(done ? .white : Theme.slate600)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(done ? Theme.primary : .white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(done ? Theme.primary : Theme.border1, lineWidth: 1)
        )
    }
}

private struct TimelineDot: View {
    let status: StepStatus
    var body: some View {
        switch status {
        case .done:
            ZStack {
                Circle().fill(Theme.success50).frame(width: 22, height: 22)
                CCIconView(icon: .check, size: 12, color: Theme.success700)
            }
        case .active:
            ZStack {
                Circle().fill(Theme.primary).frame(width: 22, height: 22)
                Circle().fill(.white).frame(width: 7, height: 7)
            }
            .background(Circle().fill(Theme.primaryRing).frame(width: 30, height: 30))
        default:
            Circle()
                .strokeBorder(Theme.slate300, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .background(Circle().fill(.white))
                .frame(width: 22, height: 22)
        }
    }
}

// Surfaced on the Active Bake screen when the user has denied notifications.
// We can't re-prompt programmatically after a denial — only Settings.app can
// flip the bit — so the banner is the polite nudge.
private struct NotificationsDeniedBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.warm50)
                    .frame(width: 36, height: 36)
                CCIconView(icon: .bell, size: 16, color: Theme.warm700)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Reminders off")
                    .font(Typography.ui(13.5, weight: .semibold))
                    .foregroundStyle(Theme.slate900)
                Text("Enable notifications in Settings to be pinged at each step.")
                    .font(Typography.ui(12))
                    .foregroundStyle(Theme.slate700)
            }
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .ccGhost(compact: true)
        }
        .padding(14)
        .background(Theme.warm50, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.warm.opacity(0.25), lineWidth: 1)
        )
    }
}

// Shown on the Active Bake screen when no bake is in progress — directs the
// user back to the Scheduler so they can create one.
private struct EmptyActiveBakeView: View {
    let onScheduler: () -> Void
    var body: some View {
        SurfaceCard {
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.primaryTint).frame(width: 64, height: 64)
                    CCIconView(icon: .play, size: 24, color: Theme.primary)
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
                }.ccPrimary()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }
}

// Inline wrap-up sheet shown when the bake's stages are all done/skipped.
// Captures a 1-5 rating and a freeform note; on save we hand both to
// `state.completeBake` which writes the journal entry.
private struct CompleteBakeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onComplete: (Int, String) -> Void
    @State private var rating: Int = 5
    @State private var note: String = ""

    var body: some View {
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
                                .font(.system(size: 26, weight: .regular))
                                .foregroundStyle(i <= rating ? Theme.warm : Theme.slate300)
                                .accessibilityHidden(true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(i) star\(i == 1 ? "" : "s")")
                        .accessibilityAddTraits(i == rating ? [.isSelected] : [])
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Rating")
                .accessibilityValue("\(rating) of 5 stars")
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
        .padding(28)
        .frame(width: 520)
        .background(Theme.surface1)
    }
}

#Preview("Active Bake") {
    ActiveBakeScreen(state: AppState(persistence: PersistenceController(filename: "preview-bake.json")))
        .padding()
        .background(Theme.surface1)
}
