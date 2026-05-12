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
}
