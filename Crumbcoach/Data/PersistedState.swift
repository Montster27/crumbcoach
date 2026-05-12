import Foundation

// PersistedState — the on-disk shape, versioned so we can migrate later.

struct PersistedState: Codable {
    static let currentVersion = 1

    var version: Int = currentVersion
    var recipes: [Recipe]
    var starters: [Starter]
    var journal: [JournalEntry]
    var activeBake: ActiveBake?
    var kitchenTempC: Double
    var kitchenHumidityPct: Int
    var ovenStatus: String
    var userName: String
    var selectedRecipeId: String
    /// Set once the user completes onboarding (name entry). Defaults to false
    /// so existing saves missing this field present onboarding once; AppState
    /// grandfathers users who already had a non-empty `userName`.
    var hasOnboarded: Bool = false
    /// Whether the user has opted in to local crash + diagnostic collection
    /// via MetricKit. Defaults to true (opt-out model, per Stage 9 plan).
    /// Existing saves missing the field get treated as opted-in.
    var telemetryEnabled: Bool = true
    /// Display weight unit (grams vs ounces). All ingredient weights stay
    /// in grams under the hood — `Units` only flips the display + editor
    /// layer. Defaults to grams so existing saves grandfather without
    /// surprising the user with an oz UI.
    var units: Units = .grams
    /// Where the Scheduler's kitchen temperature reading comes from.
    /// `.manual` is the only shipping path in v1; `.homeKit` is a stub
    /// surfaced in Settings, wired by Stage 20.
    var kitchenTempSource: KitchenTempSource = .manual
    /// Whether the user has opted in to iCloud Drive sync of the state
    /// file. Defaults to false — opt-in model. Stage 15 uses the ubiquity
    /// Documents container, not full CloudKit; see plan.md.
    var cloudSyncEnabled: Bool = false
}
