import SwiftUI

// Scheduler — forward/reverse mode, recipe picker, kitchen temp, retard,
// Sidekick toggle.  Wires real Scheduler.generateForward / generateReverse
// from the core engine.

struct SchedulerScreen: View {
    var state: AppState

    enum Mode { case reverse, forward }
    @State private var mode: Mode = .reverse
    @State private var recipeId: String
    @State private var targetDay: String = "Sun"
    @State private var targetTime: String = "10:00 AM"
    @State private var kitchenTempC: Double = 22
    @State private var coldRetard: Bool = true
    @State private var useSidekick: Bool = true
    @State private var isConfirming: Bool = false

    init(state: AppState) {
        self.state = state
        // Seed from whichever recipe the user just opened. AppShell uses
        // `.id(screenId)` so this init runs each time the user lands on the
        // scheduler — "tap Hokkaido detail → tap Schedule a bake" now arrives
        // with Hokkaido pre-selected instead of resetting to Country.
        let preferred = state.recipes.contains(where: { $0.id == state.selectedRecipeId })
            ? state.selectedRecipeId
            : (state.recipes.first?.id ?? "country")
        _recipeId = State(initialValue: preferred)
    }

    private let days = ["Sat", "Sun", "Mon"]
    private let times = ["7:00 AM", "10:00 AM", "Noon", "5:00 PM"]

    var recipe: Recipe? { state.recipe(recipeId) }

    /// Honest caption for the schedule preview's "adjusted for…" line.
    /// When the user has enough history with this recipe, the caption
    /// shows the real percentage we're applying. Otherwise it admits
    /// we're going off the recipe baseline only.
    private var historyCaption: String {
        guard let recipe else {
            return "Schedule uses the recipe baseline at \(Int(kitchenTempC))°C."
        }
        if let pct = Analytics.historyAdjustmentPct(for: recipe, in: state.journal) {
            let rounded = Int(pct.rounded())
            if rounded == 0 {
                return "Your bakes of this recipe match the recipe baseline at \(Int(kitchenTempC))°C."
            }
            let sign = rounded > 0 ? "+" : ""
            return "Adjusted for your \(sign)\(rounded)% historical bulk variance at \(Int(kitchenTempC))°C in this kitchen."
        }
        return "Recipe baseline at \(Int(kitchenTempC))°C — log a few bakes to teach the scheduler your kitchen."
    }

    var schedule: Schedule? {
        guard let recipe else { return nil }
        // Stage 18.5b — derive the history adjustment from the user's
        // actual journal entries for this recipe. Falls back to 0
        // (no adjustment) when there's not enough data yet, instead of
        // the prior hardcoded 15%.
        let historyPct = Analytics.historyAdjustmentPct(for: recipe, in: state.journal) ?? 0
        let params = ScheduleParams(
            startTime: mode == .forward ? Date() : nil,
            targetEndTime: mode == .reverse ? targetDate : nil,
            kitchenTempC: kitchenTempC,
            coldRetard: coldRetard,
            useSidekick: useSidekick,
            historyAdjustmentPct: historyPct
        )
        return mode == .reverse
            ? Scheduler.generateReverse(for: recipe, params: params)
            : Scheduler.generateForward(for: recipe, params: params)
    }

    private var targetDate: Date {
        let now = Date()
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: now)
        // pick a hour for the target time
        let hour: Int = {
            switch targetTime {
            case "7:00 AM":  return 7
            case "10:00 AM": return 10
            case "Noon":     return 12
            case "5:00 PM":  return 17
            default:         return 10
            }
        }()
        components.hour = hour
        components.minute = 0
        // offset by day of week
        var base = cal.date(from: components) ?? now
        let weekday = cal.component(.weekday, from: base)   // 1 = Sun
        let targetWeekday: Int = {
            switch targetDay { case "Sat": return 7; case "Sun": return 1; case "Mon": return 2; default: return 1 }
        }()
        let delta = (targetWeekday - weekday + 7) % 7
        base = cal.date(byAdding: .day, value: delta == 0 ? 7 : delta, to: base) ?? base
        return base
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            // LEFT — inputs
            VStack(spacing: 16) {
                modeCard
                recipeCard
                if mode == .reverse { targetCard }
                conditionsCard
            }
            .frame(width: 380)

            // RIGHT — preview. The Sidekick loop card stays hidden in
            // v1 until Stage 25's BLE integration lands and there's
            // real device data to display; today the copy was a
            // hardcoded paragraph that didn't reflect the user's
            // schedule or starter.
            VStack(spacing: 16) {
                previewCard
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Mode

    private var modeCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 0) {
                Kicker("Mode")
                HStack(spacing: 6) {
                    ModeButton(label: "Reverse", icon: .clock, active: mode == .reverse) { mode = .reverse }
                    ModeButton(label: "Forward", icon: .play,  active: mode == .forward) { mode = .forward }
                }
                .padding(4)
                .background(Theme.slate100, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 10)
                Text(mode == .reverse
                     ? "Pick when you want bread out of the oven — we'll work backward."
                     : "Start now — we'll walk you forward stage by stage.")
                    .font(Typography.ui(11.5))
                    .foregroundStyle(Theme.slate500)
                    .padding(.top, 10)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    // MARK: Recipe

    private var recipeCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Kicker("Recipe")
                Picker("", selection: $recipeId) {
                    ForEach(state.recipes) { r in
                        Text(r.title).tag(r.id)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.border1, lineWidth: 1)
                )

                if let r = recipe {
                    let total = r.stages.reduce(0) { $0 + $1.durationMin }
                    HStack(spacing: 14) {
                        stat("\(Int(r.hydrationPct))%", "hyd.")
                        stat("\(Int(round(Double(total) / 60.0)))h", "end-to-end")
                        stat("\(r.stages.count)", "stages")
                    }
                }
            }
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        HStack(spacing: 2) {
            Text(v).font(Typography.mono(13, weight: .semibold)).foregroundStyle(Theme.slate700)
            Text(l).font(Typography.ui(12)).foregroundStyle(Theme.slate600)
        }
    }

    // MARK: Target

    private var targetCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Kicker("Target — bread out of the oven")
                FlowLayout(spacing: 6) {
                    ForEach(days, id: \.self) { d in
                        TagPill(label: d, active: d == targetDay) { targetDay = d }
                    }
                }
                FlowLayout(spacing: 6) {
                    ForEach(times, id: \.self) { t in
                        TagPill(label: t, active: t == targetTime) { targetTime = t }
                    }
                }
            }
        }
    }

    // MARK: Conditions

    private var conditionsCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 0) {
                Kicker("Conditions")
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Kitchen temperature", systemImage: "thermometer")
                            .font(Typography.ui(12))
                            .foregroundStyle(Theme.slate600)
                        Spacer()
                        Text("\(Int(kitchenTempC))°C")
                            .font(Typography.mono(12, weight: .semibold))
                            .foregroundStyle(Theme.slate900)
                    }
                    Slider(value: $kitchenTempC, in: 16...32, step: 1).tint(Theme.primary)
                    Text("HomeKit · Kitchen sensor \(String(format: "%.1f", state.kitchenTempC))°C now")
                        .font(Typography.ui(11))
                        .foregroundStyle(Theme.slate500)
                }
                .padding(.top, 12)
                SoftDivider().padding(.vertical, 14)
                ToggleRow(label: "Cold retard overnight",
                           sub: "12h fridge after final shape",
                           isOn: $coldRetard)
                // Sidekick toggle hidden in v1 — the BLE integration is
                // gated on the FirstBuild partnership (Stage 25). The
                // underlying `useSidekick` Bool stays in ScheduleParams so
                // Stage 25 can flip it back on without a model change.
            }
        }
    }

    // MARK: Preview

    private var previewCard: some View {
        SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                if let schedule {
                    VStack(alignment: .leading, spacing: 6) {
                        Kicker(mode == .reverse ? "Bread out · \(targetDay) \(targetTime)" : "Start now",
                               color: Theme.primary)
                        Text(mode == .reverse
                             ? "Start at \(CCFormat.clockShort.string(from: schedule.startTime))"
                             : "Done by \(CCFormat.clockShort.string(from: schedule.endTime))")
                            .font(Typography.display(26, weight: .medium))
                            .foregroundStyle(Theme.slate900)
                        Text(historyCaption)
                            .font(Typography.ui(13))
                            .foregroundStyle(Theme.slate700)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(
                        LinearGradient(colors: [Theme.primaryTint, .white],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.border1).frame(height: 1) }

                    VStack(alignment: .leading, spacing: 12) {
                        Kicker("Timeline preview")
                        timelinePreview(schedule: schedule)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)

                    HStack {
                        Text("Live Activity, Apple Watch, and Sidekick notifications will fire at action points only.")
                            .font(Typography.ui(12)).foregroundStyle(Theme.slate700)
                        Spacer()
                        Button {
                            confirmAndStart(schedule: schedule)
                        } label: {
                            Label("Confirm & start", systemImage: "play.fill")
                        }
                        .ccPrimary()
                        .disabled(isConfirming)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(Theme.slate50)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.border1).frame(height: 1) }
                }
            }
        }
    }

    private func timelinePreview(schedule: Schedule) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(schedule.steps.enumerated()), id: \.offset) { i, step in
                HStack(spacing: 12) {
                    Text(relativeOffset(step.start, from: schedule.startTime))
                        .font(Typography.mono(12))
                        .foregroundStyle(Theme.slate500)
                        .frame(width: 90, alignment: .leading)
                    Circle()
                        .fill(dotColor(for: step.kind))
                        .frame(width: 10, height: 10)
                    Text(step.kind.rawValue)
                        .font(Typography.ui(13.5))
                        .foregroundStyle(Theme.slate900)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(CCFormat.duration(Int(step.end.timeIntervalSince(step.start) / 60)))
                        .font(Typography.mono(12))
                        .foregroundStyle(Theme.slate500)
                        .frame(width: 60, alignment: .trailing)
                }
                .padding(.vertical, 9)
                .overlay(alignment: .top) {
                    i == 0 ? AnyView(EmptyView()) : AnyView(Rectangle().fill(Theme.border1).frame(height: 1))
                }
            }
        }
    }

    /// Prompt for notification permission first so the system alert anchors
    /// to the user's tap (not the next screen), then create the ActiveBake
    /// and navigate. Subsequent confirms are instant — the prompt is a
    /// no-op once authorization is already determined.
    private func confirmAndStart(schedule: Schedule) {
        guard let recipe, !isConfirming else { return }
        isConfirming = true
        let starterId = defaultStarterId(for: recipe)
        Task { @MainActor in
            await state.requestNotificationPermission()
            state.startBake(from: schedule,
                            recipe: recipe,
                            starterId: starterId)
            isConfirming = false
        }
    }

    /// Sourdough bakes default to the user's first starter; other bread types
    /// don't carry one. The recipe editor (Stage 4) will let users pick.
    private func defaultStarterId(for recipe: Recipe) -> String? {
        recipe.breadType == .sourdough ? state.starters.first?.id : nil
    }

    private func relativeOffset(_ d: Date, from origin: Date) -> String {
        let mins = Int(d.timeIntervalSince(origin) / 60)
        return "+\(CCFormat.duration(mins))"
    }

    private func dotColor(for kind: StageKind) -> Color {
        switch kind {
        case .bake: return Theme.warm
        case .coldRetard: return Theme.sky400
        case .feedLevain: return Theme.accent
        default: return Theme.slate300
        }
    }

    // MARK: Sidekick

    private var sidekickLoopCard: some View {
        SurfaceCard(padding: EdgeInsets()) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.primaryTint)
                        .frame(width: 44, height: 44)
                    CCIconView(icon: .device, size: 20, color: Theme.primary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Kicker("Sidekick closed loop", color: Theme.primary)
                    Text("Ruby will be fed 1:5:5 at 2:14 PM to peak 200g of 100% hydration levain at mix time Sat 8:14 PM. If kitchen warms, Sidekick will adjust the last feed and the schedule reflows.")
                        .font(Typography.ui(13))
                        .foregroundStyle(Theme.slate700)
                }
                Spacer()
            }
            .padding(16)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.primaryTint2, lineWidth: 1)
        )
    }
}

// MARK: - Mode button + toggle row

private struct ModeButton: View {
    let label: String
    let icon: CCIcon
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                CCIconView(icon: icon, size: 14,
                            color: active ? Theme.slate900 : Theme.slate600)
                Text(label).font(Typography.ui(13, weight: .medium))
                    .foregroundStyle(active ? Theme.slate900 : Theme.slate600)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(active ? .white : .clear,
                         in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: active ? Theme.shadowCard : .clear, radius: 1, y: 1)
        }
        .buttonStyle(.plain)
    }
}

struct ToggleRow: View {
    let label: String
    let sub: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Typography.ui(13.5, weight: .medium)).foregroundStyle(Theme.slate900)
                Text(sub).font(Typography.ui(11.5)).foregroundStyle(Theme.slate500)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(Theme.primary)
        }
        .padding(.vertical, 10)
    }
}

#Preview("Scheduler") {
    SchedulerScreen(state: AppState(persistence: PersistenceController(filename: "preview-scheduler.json")))
        .padding()
        .background(Theme.surface1)
        .frame(width: 1100, height: 800)
}
