import Foundation

// Stage 19 — wire-format between the main app and the widget extension.
// The main app writes this Codable struct to the App Group container on
// every `activeBake` mutation; the widget extension's TimelineProvider
// reads it. The struct is deliberately small (no photos, no full recipe)
// so it can be re-read cheaply on every widget refresh.
//
// The file lives in `Shared/` and is listed in both targets' sources in
// `project.yml` so encode and decode stay byte-identical.

struct WidgetSnapshot: Codable, Equatable {
    /// When this snapshot was written. Widgets use the age as a "stale"
    /// hint; a snapshot older than ~48h almost certainly means the bake
    /// completed and we forgot to clear.
    var generatedAt: Date

    /// Active-bake summary. Nil when no bake is in progress — the widget
    /// renders the "no active bake" placeholder.
    var activeBake: ActiveBakeSummary?

    /// One-line stage entry suitable for the small widget. Nil when no
    /// active bake.
    struct ActiveBakeSummary: Codable, Equatable {
        var recipeTitle: String
        var startedAt: Date
        var bakeOutAt: Date
        var stageName: String
        var stageIndex: Int
        var stageCount: Int
        var foldsDone: Int
        var totalFolds: Int
        /// Estimated wall-clock time of the next user action. Widgets render
        /// a live countdown with `Text(_, style: .timer)` so a single
        /// timeline entry stays accurate until the date passes.
        var nextActionAt: Date
        /// Display string for the next action ("Fold 3 of 4", "Shape",
        /// "Bake out"). Frozen in the snapshot so the widget doesn't need
        /// to re-derive from stage history.
        var nextActionLabel: String
        var isComplete: Bool
    }
}
