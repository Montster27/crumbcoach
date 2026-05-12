import Foundation
import ActivityKit

// Shared attributes for the in-progress bake Live Activity. The struct is
// compiled into BOTH the main app target (which starts / updates / ends the
// activity via `LiveActivityManager`) and the widget extension target
// (which renders the lock-screen + Dynamic Island UI). project.yml lists
// this file under both targets' sources to keep the contract honest.
//
// The split between "static" attributes and "dynamic" ContentState is the
// ActivityKit shape:
//   - `ActiveBakeAttributes` holds values that never change during the
//     activity's lifetime (recipe title, bake-out time at start).
//   - `ContentState` holds values the system re-renders on each update
//     (current stage name, folds done / total, minutes-to-next-action).

struct ActiveBakeAttributes: ActivityAttributes {
    public typealias BakeState = ContentState

    /// Frozen at start. Renaming the recipe mid-bake doesn't update the
    /// activity title — restart the activity if that matters (rare).
    var recipeTitle: String
    /// Wall-clock time the bake started. Used to render "Started 4:12 PM".
    var startedAt: Date

    public struct ContentState: Codable, Hashable {
        var stageName: String
        var foldsDone: Int
        var totalFolds: Int
        /// Estimated minutes until the next user action. Negative when the
        /// scheduled action has slipped past now — the widget can render a
        /// "Running late" cue without us recomputing on its side.
        var minutesToNextAction: Int
        /// Updated end time so the lock screen can show a moving "Bake out
        /// 7:38 AM" countdown.
        var bakeOutAt: Date
        /// True once every stage is done / skipped. Drives the "Log this
        /// bake" prompt on the activity.
        var isComplete: Bool
    }
}
