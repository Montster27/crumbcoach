import SwiftUI

// Active bake screen — recipe card + Live Activity preview on the left,
// current stage + timeline on the right.  Mirrors screen-bake.jsx.

struct ActiveBakeScreen: View {
    @Bindable var state: AppState
    @State private var proofOvenOpen: Bool = false
    @State private var proofOvenActive: Bool = false
    @State private var proofOvenTempC: Double = 26

    var body: some View {
        guard let bake = state.activeBake, let recipe = state.recipe(bake.recipeId) else {
            return AnyView(Text("No active bake").foregroundStyle(Theme.slate500))
        }
        let stage = recipe.stages[bake.currentStageIndex]
        let baseDur = stage.durationMin
        let adjustedDur = proofOvenActive
            ? max(Int(Double(baseDur) * max(0.55, 1 - (proofOvenTempC - 22) * 0.06)), 30)
            : baseDur
        let saved = baseDur - adjustedDur

        return AnyView(
            HStack(alignment: .top, spacing: 24) {
                // LEFT
                VStack(spacing: 16) {
                    recipeHeaderCard(bake: bake, recipe: recipe)
                    liveActivityCard(bake: bake, recipe: recipe, stage: stage)
                }
                .frame(width: 360)

                // RIGHT
                VStack(spacing: 16) {
                    currentStageCard(bake: bake, recipe: recipe, stage: stage,
                                      adjustedDur: adjustedDur, baseDur: baseDur, saved: saved)
                    timelineCard(bake: bake, recipe: recipe)
                }
                .frame(maxWidth: .infinity)
            }
        )
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

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        statBlock("Hydration", "\(Int(recipe.hydrationPct))%")
                        statBlock("Total weight", "\(Int(recipe.totalDoughGrams))g")
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
                        Text("\(stage.kind.rawValue) · \(bake.foldsDone)/\(bake.totalFolds) folds")
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
                // Header gradient
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
                    }
                    HStack(spacing: 8) {
                        ForEach(0..<bake.totalFolds, id: \.self) { i in
                            FoldChip(index: i + 1, done: i < bake.foldsDone, current: i == bake.foldsDone)
                                .onTapGesture {
                                    state.activeBake?.foldsDone = i + 1
                                }
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

                // Action bar
                HStack(spacing: 10) {
                    Button {
                        if let b = state.activeBake {
                            state.activeBake?.foldsDone = min(b.totalFolds, b.foldsDone + 1)
                        }
                    } label: {
                        Label("Mark fold \(bake.foldsDone + 1) done", systemImage: "checkmark")
                    }.ccPrimary()

                    Button { } label: {
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

                    Button { } label: {
                        Label("Running late", systemImage: "clock")
                    }.ccSecondary()

                    Spacer()
                    Button("Skip stage") { }.ccGhost(compact: true)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.border1).frame(height: 1) }

                if proofOvenOpen {
                    proofOvenPanel(stage: stage, adjustedDur: adjustedDur, baseDur: baseDur, saved: saved)
                }

                // Adaptive note
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

    private func proofOvenPanel(stage: Stage, adjustedDur: Int, baseDur: Int, saved: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Kicker("Stage override · not in recipe", color: Theme.primaryDeep)
                    Text("Proofing oven · hold \(stage.kind.rawValue) at a steady temp")
                        .font(Typography.display(18, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                    Text("Kitchen is 22.1°C. Holding at \(Int(proofOvenTempC))°C shortens this stage to \(CCFormat.duration(adjustedDur)) (saves \(CCFormat.duration(saved))). Recipe baseline \(CCFormat.duration(baseDur)).")
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
                Text("Schedule reflowed: next fold in 9m (was 14m), bake out 5:47 AM (was 7:38 AM).")
                    .font(Typography.ui(12)).foregroundStyle(Theme.slate700)
                Spacer()
                Button("Undo →") { }.ccGhost(compact: true)
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

    // MARK: Timeline card

    private func timelineCard(bake: ActiveBake, recipe: Recipe) -> some View {
        let stageTimes = computeStageTimes(recipe: recipe)
        let totalPhotos = bake.stagePhotos.values.reduce(0) { $0 + $1.count }
        return SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker("Timeline")
                        Text("18h end-to-end · ")
                            .font(Typography.ui(11)).foregroundStyle(Theme.slate500)
                        + Text("\(totalPhotos)").font(Typography.mono(11, weight: .semibold)).foregroundStyle(Theme.slate700)
                        + Text(" photos this bake").font(Typography.ui(11)).foregroundStyle(Theme.slate500)
                    }
                    Spacer()
                    Button("View grid →") { }.ccGhost(compact: true)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)

                ForEach(Array(recipe.stages.enumerated()), id: \.offset) { idx, stage in
                    let status = bake.history.first(where: { $0.stageIndex == idx })?.status ?? .pending
                    let isActive = status == .active
                    timelineRow(idx: idx, stage: stage, status: status,
                                startMin: stageTimes[idx].start,
                                isActive: isActive,
                                bake: bake)
                }
                .padding(.bottom, 12)
            }
        }
    }

    private func computeStageTimes(recipe: Recipe) -> [(start: Int, end: Int)] {
        var cursor = 0
        return recipe.stages.map { s in
            let start = cursor
            cursor += s.durationMin
            return (start, cursor)
        }
    }

    private func formatClockOffset(_ minutes: Int, baseHour: Int = 16, baseMinute: Int = 12) -> String {
        let total = baseHour * 60 + baseMinute + minutes
        let day = total >= 24 * 60 ? "Sun " : ""
        let t = total % (24 * 60)
        let h = t / 60
        let m = t % 60
        let hh = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        let ampm = h >= 12 ? "PM" : "AM"
        return "\(day)\(hh):\(String(format: "%02d", m)) \(ampm)"
    }

    private func timelineRow(idx: Int, stage: Stage, status: StepStatus, startMin: Int,
                              isActive: Bool, bake: ActiveBake) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(formatClockOffset(startMin))
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
                        ForEach(photos) { _ in
                            Rectangle().fill(Theme.primaryTint)
                                .frame(width: 44, height: 44)
                                .overlay(CCIconView(icon: .camera, size: 15, color: Theme.primary))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        if status != .pending {
                            Button(action: {}) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isActive ? Theme.primary : Theme.slate300,
                                            style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                    .frame(width: 44, height: 44)
                                    .overlay(CCIconView(icon: .camera, size: 15,
                                                         color: isActive ? Theme.primary : Theme.slate400))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                }
            }

            Spacer()

            Text(CCFormat.duration(stage.durationMin))
                .font(Typography.mono(11))
                .foregroundStyle(Theme.slate500)
                .padding(.top, 4)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(isActive ? Theme.primaryTint : .clear)
        .overlay(alignment: .top) { idx == 0 ? AnyView(EmptyView()) : AnyView(Rectangle().fill(Theme.border1).frame(height: 1)) }
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
