import Foundation
import UserNotifications

// Local-notification scheduling for an in-progress bake. Every fold, shape,
// retard, and bake-out becomes a UNTimeIntervalNotificationTrigger keyed by
// `bake-<scheduleId>-<stepIdx>(-<subIdx>)`. Cancel-and-replace is the only
// modify path — we don't try to diff schedules.
//
// We track the set of identifiers we have outstanding so cancellation is
// deterministic and synchronous (no `getPendingNotificationRequests` race).
// On singleton init we hydrate the set from whatever the system still holds,
// so reminders scheduled in a prior launch remain cancellable.
//
// The delegate is set on first access and stashes a one-shot "tap pending"
// flag plus posts an in-app NSNotification, so the shell can route to the
// Active Bake screen whether the tap arrived live or while the app was
// launching cold.

final class NotificationManager {

    static let shared = NotificationManager()

    /// Posted via `NotificationCenter.default` for live taps. The app shell
    /// also drains `consumePendingBakeTap()` on first appear so cold-launch
    /// taps never get lost in the window before observers attach.
    static let bakeReminderTapped = Notification.Name("GeekBread.bakeReminderTapped")

    private let center = UNUserNotificationCenter.current()
    private let delegate: Delegate

    /// Identifiers of pending bake reminders we've scheduled. Mutated only on
    /// the main thread (schedule/cancel are driven by UI actions).
    private var scheduledIdentifiers: Set<String> = []

    /// Set by the delegate when a bake reminder is tapped. Drained by
    /// `consumePendingBakeTap()` on app appear. Write may happen off-main
    /// (delegate callback queue); reads happen on main. Bool word-store is
    /// atomic on Apple platforms — good enough until Swift 6 enforces.
    private var pendingBakeTap: Bool = false

    private init() {
        // Delegate must be set before the first scene connects so the system
        // can deliver any response that was generated while the app wasn't
        // running. GeekBreadApp.init touches `.shared` to force this.
        let d = Delegate()
        self.delegate = d
        UNUserNotificationCenter.current().delegate = d
        // Reclaim identifiers the system still holds from a prior launch so
        // cancel-by-id stays deterministic across cold starts.
        center.getPendingNotificationRequests { [weak self] requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix("bake-") }
            guard !ids.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                self?.scheduledIdentifiers.formUnion(ids)
            }
        }
    }

    // MARK: Permission

    /// Current authorization status, queried fresh from the system.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Prompts the user the first time, then returns the resulting state.
    /// Returns `true` when notifications can fire (authorized / provisional /
    /// ephemeral), `false` when denied or not-determined-after-prompt.
    @discardableResult
    func requestPermissionIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            return granted
        case .denied:
            return false
        case .authorized, .provisional, .ephemeral:
            return true
        @unknown default:
            return false
        }
    }

    // MARK: Scheduling

    /// Cancel any existing bake reminders and schedule new ones for each
    /// action point in the given schedule. Safe to call repeatedly —
    /// cancel-and-replace is the only modify path.
    func scheduleBakeReminders(for schedule: Schedule, recipe: Recipe) {
        // Cancel synchronously based on our tracked id set so freshly-added
        // requests below can never get swept up in a stale async callback.
        cancelAllBakeReminders()

        let now = Date()
        // Pick out the LAST bake step so we can vary the wording. Multi-bake
        // recipes (rare but legal — e.g. double-bake brioche) should only say
        // "pull the bread out" on the final cycle.
        let lastBakeIndex = schedule.steps.lastIndex(where: { $0.kind == .bake })
        for (stepIndex, step) in schedule.steps.enumerated() {
            let actions = actionPoints(for: step, recipe: recipe,
                                        isFinalBakeStep: stepIndex == lastBakeIndex)
            for (subIndex, action) in actions.enumerated() {
                let interval = action.fireDate.timeIntervalSince(now)
                // UNTimeIntervalNotificationTrigger requires a positive
                // interval — skip anything that's already past.
                guard interval > 0 else { continue }

                let content = UNMutableNotificationContent()
                content.title = recipe.title
                content.body = action.body
                content.sound = .default
                content.userInfo = [
                    "type": "bakeReminder",
                    "scheduleId": schedule.id.uuidString,
                    "stepIndex": stepIndex,
                ]
                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: interval, repeats: false
                )
                let identifier = Self.identifier(
                    scheduleId: schedule.id,
                    stepIndex: stepIndex,
                    subIndex: actions.count > 1 ? subIndex : nil
                )
                let request = UNNotificationRequest(
                    identifier: identifier, content: content, trigger: trigger
                )
                scheduledIdentifiers.insert(identifier)
                center.add(request) { _ in
                    // Failures here are non-fatal — worst case the user just
                    // doesn't get one reminder.
                }
            }
        }
    }

    /// Cancel only the reminders belonging to one schedule. Stage 3+ will use
    /// this to refresh a single bake's reminders without wiping every bake
    /// reminder in the system.
    func cancelBakeReminders(for scheduleId: UUID) {
        let prefix = "bake-\(scheduleId.uuidString)-"
        let toCancel = scheduledIdentifiers.filter { $0.hasPrefix(prefix) }
        guard !toCancel.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: Array(toCancel))
        scheduledIdentifiers.subtract(toCancel)
    }

    /// Cancel every bake reminder we've scheduled. Synchronous: removal goes
    /// through the system right away, and our tracking set is cleared in the
    /// same call so subsequent scheduling races can't reach back in.
    func cancelAllBakeReminders() {
        guard !scheduledIdentifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: Array(scheduledIdentifiers))
        scheduledIdentifiers.removeAll()
    }

    // MARK: Tap routing

    /// One-shot drain of the "a notification tap is waiting for us" flag.
    /// AppShell calls this in `.task` so a cold-launch tap survives the gap
    /// between the system delivering the response and SwiftUI attaching its
    /// `.onReceive` subscription.
    @discardableResult
    func consumePendingBakeTap() -> Bool {
        let pending = pendingBakeTap
        pendingBakeTap = false
        return pending
    }

    /// Called from the delegate when a bake reminder is tapped. The flag is
    /// the durable signal; the NSNotification post is for live observers.
    fileprivate func markBakeTap() {
        if Thread.isMainThread {
            pendingBakeTap = true
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.pendingBakeTap = true
            }
        }
    }

    // MARK: Action-point heuristics

    /// One concrete reminder for the user — a fire date and a body string.
    /// We emit several of these per step (e.g. one per fold cycle, or
    /// retard start + end).
    private struct Action {
        let fireDate: Date
        let body: String
    }

    /// Pick which moments inside a step deserve a notification. Honor the
    /// "no spam" principle from the spec — autolyse / silent bulks / scalds
    /// don't get reminders.
    private func actionPoints(for step: ScheduleStep,
                              recipe: Recipe,
                              isFinalBakeStep: Bool) -> [Action] {
        switch step.kind {

        case .mix:
            return [Action(fireDate: step.start, body: "Time to mix the dough.")]

        case .bulkFold:
            // Honor the recipe's per-stage fold count when present; fall back
            // to 4 for legacy recipes that never set it. Spacing keeps the
            // first ping inset from the stage start (so the dough has had a
            // moment to relax) and the last well before stage end.
            let stage = recipe.stages.indices.contains(step.stageIndex)
                ? recipe.stages[step.stageIndex] : nil
            let total = max(1, stage?.totalFolds ?? 4)
            let window = step.end.timeIntervalSince(step.start)
            guard window > 0 else { return [] }
            let spacing = window / Double(total + 1)
            return (1...total).map { i in
                let fireDate = step.start.addingTimeInterval(spacing * Double(i))
                return Action(fireDate: fireDate,
                              body: "Stretch & fold \(i) of \(total).")
            }

        case .preShape:
            return [Action(fireDate: step.start, body: "Pre-shape the dough.")]

        case .finalShape:
            return [Action(fireDate: step.start, body: "Final shape into the banneton.")]

        case .coldRetard:
            return [
                Action(fireDate: step.start,
                       body: "Into the fridge for cold retard."),
                Action(fireDate: step.end,
                       body: "Cold retard done — preheat the oven."),
            ]

        case .bake:
            return [
                Action(fireDate: step.start,
                       body: "Time to bake — load the dough."),
                Action(fireDate: step.end,
                       body: isFinalBakeStep
                            ? "Bake out — pull the bread from the oven."
                            : "First bake done — set up for the next bake."),
            ]

        // Silent stages — per the spec we don't notify on these.
        case .feedLevain, .prepYudane, .prepPoolish, .cookTangzhong, .autolyse,
             .addButter, .bulk, .divide, .divideShape, .proof, .finalProof:
            return []
        }
    }

    // MARK: Identifiers

    private static func identifier(scheduleId: UUID,
                                    stepIndex: Int,
                                    subIndex: Int? = nil) -> String {
        if let subIndex {
            return "bake-\(scheduleId.uuidString)-\(stepIndex)-\(subIndex)"
        }
        return "bake-\(scheduleId.uuidString)-\(stepIndex)"
    }

    // MARK: Delegate

    /// UNUserNotificationCenterDelegate must be an NSObject — keep it as a
    /// nested class so the public API on `NotificationManager` stays clean.
    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {

        // Show the banner + sound while the app is in the foreground so the
        // user still notices a fold reminder without locking the device.
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                     willPresent notification: UNNotification,
                                     withCompletionHandler completionHandler:
                                     @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .sound, .list])
        }

        // Tap → stash flag for cold-launch path + post for live-observer path.
        // The flag write hops to main; the post is wrapped in async so any
        // SwiftUI .onReceive observers are guaranteed to see it on main.
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                     didReceive response: UNNotificationResponse,
                                     withCompletionHandler completionHandler:
                                     @escaping () -> Void) {
            let info = response.notification.request.content.userInfo
            if info["type"] as? String == "bakeReminder" {
                NotificationManager.shared.markBakeTap()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NotificationManager.bakeReminderTapped, object: nil
                    )
                }
            }
            completionHandler()
        }
    }
}
