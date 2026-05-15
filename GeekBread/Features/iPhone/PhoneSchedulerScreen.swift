import SwiftUI

// iPhone Scheduler — vertical stack of inputs (mode / recipe / target /
// conditions) followed by the preview + confirm action. Reuses the
// `ScheduleParams` + `Scheduler.generate*` core path verbatim. The
// `ToggleRow` view from the iPad screen is internal-scope, so it's
// reusable here without duplication.

struct PhoneSchedulerScreen: View {
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
        let preferred = state.recipes.contains(where: { $0.id == state.selectedRecipeId })
            ? state.selectedRecipeId
            : (state.recipes.first?.id ?? "country")
        _recipeId = State(initialValue: preferred)
    }

    private let days = ["Sat", "Sun", "Mon"]
    private let times = ["7:00 AM", "10:00 AM", "Noon", "5:00 PM"]

    private var recipe: Recipe? { state.recipe(recipeId) }

    private var historyCaption: String {
        guard let recipe else {
            return "Schedule uses the recipe baseline at \(Int(kitchenTempC))°C."
        }
        if let pct = Analytics.historyAdjustmentPct(for: recipe, in: state.journal) {
            let rounded = Int(pct.rounded())
            if rounded == 0 {
                return "Your bakes match the recipe baseline at \(Int(kitchenTempC))°C."
            }
            let sign = rounded > 0 ? "+" : ""
            return "Adjusted for your \(sign)\(rounded)% historical bulk variance at \(Int(kitchenTempC))°C."
        }
        return "Recipe baseline at \(Int(kitchenTempC))°C — log a few bakes to teach the scheduler."
    }

    private var schedule: Schedule? {
        guard let recipe else { return nil }
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
        var base = cal.date(from: components) ?? now
        let weekday = cal.component(.weekday, from: base)
        let targetWeekday: Int = {
            switch targetDay { case "Sat": return 7; case "Sun": return 1; case "Mon": return 2; default: return 1 }
        }()
        let delta = (targetWeekday - weekday + 7) % 7
        base = cal.date(byAdding: .day, value: delta == 0 ? 7 : delta, to: base) ?? base
        return base
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PhoneTheme.cardSpacing) {
                modeCard
                recipeCard
                if mode == .reverse { targetCard }
                conditionsCard
                if let schedule { previewCard(schedule: schedule) }
            }
            .padding(.horizontal, PhoneTheme.screenHPad)
            .padding(.top, PhoneTheme.screenVPad)
            .padding(.bottom, PhoneTheme.sectionSpacing)
        }
        .background(Theme.surface1)
    }

    // MARK: Mode

    private var modeCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Kicker("Mode")
                HStack(spacing: 6) {
                    PhoneModeButton(label: "Reverse", icon: .clock, active: mode == .reverse) {
                        mode = .reverse
                    }
                    PhoneModeButton(label: "Forward", icon: .play, active: mode == .forward) {
                        mode = .forward
                    }
                }
                .padding(4)
                .background(Theme.slate100,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Text(mode == .reverse
                     ? "Pick when bread should come out of the oven. We'll work backward."
                     : "Start now — we'll walk you forward stage by stage.")
                    .font(Typography.ui(11.5))
                    .foregroundStyle(Theme.slate500)
            }
        }
    }

    // MARK: Recipe

    private var recipeCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Kicker("Recipe")
                Picker("", selection: $recipeId) {
                    ForEach(state.recipes) { r in
                        Text(r.title).tag(r.id)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        HStack(spacing: 2) {
            Text(v).font(Typography.mono(12, weight: .semibold)).foregroundStyle(Theme.slate700)
            Text(l).font(Typography.ui(11)).foregroundStyle(Theme.slate600)
        }
    }

    // MARK: Target

    private var targetCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Kicker("Target · bread out of the oven")
                HStack(spacing: 6) {
                    ForEach(days, id: \.self) { d in
                        TagPill(label: d, active: d == targetDay) { targetDay = d }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(times, id: \.self) { t in
                            TagPill(label: t, active: t == targetTime) { targetTime = t }
                        }
                    }
                }
            }
        }
    }

    // MARK: Conditions

    private var conditionsCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
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
                    Slider(value: $kitchenTempC, in: 16...32, step: 1)
                        .tint(Theme.primary)
                    Text("Sensor now \(String(format: "%.1f", state.kitchenTempC))°C")
                        .font(Typography.ui(11))
                        .foregroundStyle(Theme.slate500)
                }
                SoftDivider()
                ToggleRow(label: "Cold retard overnight",
                          sub: "12h fridge after final shape",
                          isOn: $coldRetard)
            }
        }
    }

    // MARK: Preview

    private func previewCard(schedule: Schedule) -> some View {
        SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker(mode == .reverse
                           ? "Out · \(targetDay) \(targetTime)"
                           : "Start now",
                           color: Theme.primary)
                    Text(mode == .reverse
                         ? "Start at \(CCFormat.clockShort.string(from: schedule.startTime))"
                         : "Done by \(CCFormat.clockShort.string(from: schedule.endTime))")
                        .font(Typography.display(22, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                    Text(historyCaption)
                        .font(Typography.ui(12))
                        .foregroundStyle(Theme.slate700)
                }
                .padding(.horizontal, PhoneTheme.cardPad)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [Theme.primaryTint, .white],
                                   startPoint: .top, endPoint: .bottom)
                )
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.border1).frame(height: 1) }

                VStack(alignment: .leading, spacing: 8) {
                    Kicker("Timeline preview")
                    timelinePreview(schedule: schedule)
                }
                .padding(.horizontal, PhoneTheme.cardPad)
                .padding(.vertical, 14)

                Button { confirmAndStart(schedule: schedule) } label: {
                    Label("Confirm & start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .ccPrimary()
                .disabled(isConfirming)
                .padding(.horizontal, PhoneTheme.cardPad)
                .padding(.bottom, 14)
            }
        }
    }

    private func timelinePreview(schedule: Schedule) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(schedule.steps.enumerated()), id: \.offset) { i, step in
                HStack(spacing: 10) {
                    Text(relativeOffset(step.start, from: schedule.startTime))
                        .font(Typography.mono(10.5))
                        .foregroundStyle(Theme.slate500)
                        .frame(width: 56, alignment: .leading)
                    Circle()
                        .fill(dotColor(for: step.kind))
                        .frame(width: 8, height: 8)
                    Text(step.kind.rawValue)
                        .font(Typography.ui(12.5))
                        .foregroundStyle(Theme.slate900)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(CCFormat.duration(Int(step.end.timeIntervalSince(step.start) / 60)))
                        .font(Typography.mono(10.5))
                        .foregroundStyle(Theme.slate500)
                        .frame(width: 48, alignment: .trailing)
                }
                .padding(.vertical, 7)
                .overlay(alignment: .top) {
                    if i > 0 { Rectangle().fill(Theme.border1).frame(height: 1) }
                }
            }
        }
    }

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
}

// MARK: - Mode button (phone variant of iPad's private ModeButton)

private struct PhoneModeButton: View {
    let label: String
    let icon: CCIcon
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                CCIconView(icon: icon, size: 13,
                            color: active ? Theme.slate900 : Theme.slate600)
                Text(label)
                    .font(Typography.ui(13, weight: .medium))
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

#Preview("Phone Scheduler") {
    NavigationStack {
        PhoneSchedulerScreen(state: AppState(persistence: PersistenceController(filename: "preview-phone-scheduler.json")))
            .navigationTitle("Scheduler")
            .navigationBarTitleDisplayMode(.inline)
    }
}
