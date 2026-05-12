import Foundation
import ActivityKit

// Owns the lifecycle of the in-progress bake Live Activity. AppState calls
// `start` when a bake begins, `update` after every fold/advance/skip that
// changes the activity-visible state, and `end` when the bake completes (or
// the user backs out).
//
// We keep at most one activity in flight — there's only one ActiveBake at a
// time. Re-entrant `start` calls end the previous activity first so the
// system doesn't pile up duplicates.
//
// `ActivityAuthorizationInfo.areActivitiesEnabled` is the gate: the user
// can disable Live Activities globally in Settings → Notifications → Live
// Activities. When false, every call here returns without touching the
// system. The user sees no broken state — the existing recipe / active-bake
// screens already cover the in-app surface.

final class LiveActivityManager {

    static let shared = LiveActivityManager()

    private var currentActivity: Activity<ActiveBakeAttributes>?

    private init() {}

    /// Start (or restart) the activity for a newly-confirmed bake. Idempotent
    /// re-call ends the previous activity so we never leak duplicates.
    func start(recipeTitle: String,
               startedAt: Date,
               state: ActiveBakeAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endCurrent()
        let attributes = ActiveBakeAttributes(recipeTitle: recipeTitle, startedAt: startedAt)
        let content = ActivityContent(state: state, staleDate: nil)
        do {
            currentActivity = try Activity.request(attributes: attributes,
                                                    content: content,
                                                    pushType: nil)
        } catch {
            // Activity start failures are non-fatal — the in-app UI is the
            // primary surface. We log via the system; production should
            // route through TelemetryManager once it grows that hook.
            print("LiveActivity start failed: \(error.localizedDescription)")
        }
    }

    /// Push a new ContentState to the running activity. Safe to call when no
    /// activity is in flight — the call is dropped silently.
    func update(_ state: ActiveBakeAttributes.ContentState) {
        guard let activity = currentActivity else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await activity.update(content) }
    }

    /// End the activity. Two paths:
    ///   - `immediate`: dismisses the activity right away (used when the
    ///     user manually backs out or starts a new bake).
    ///   - non-immediate: lets the system fade the activity out over its
    ///     default trailing window (~4 hours), giving the user time to
    ///     glance at the final state on the lock screen after completion.
    func end(immediate: Bool = false) {
        guard let activity = currentActivity else { return }
        currentActivity = nil
        let finalState = activity.content.state
        let content = ActivityContent(state: finalState, staleDate: nil)
        let dismissalPolicy: ActivityUIDismissalPolicy =
            immediate ? .immediate : .default
        Task { await activity.end(content, dismissalPolicy: dismissalPolicy) }
    }

    private func endCurrent() {
        guard let activity = currentActivity else { return }
        currentActivity = nil
        let content = ActivityContent(state: activity.content.state, staleDate: nil)
        Task { await activity.end(content, dismissalPolicy: .immediate) }
    }
}
