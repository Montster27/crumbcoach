import Foundation
import SwiftUI

// App-wide observable state. Holds the user's data (recipes, starters, journal,
// active bake) and the navigation selection.  In production this would persist
// via SwiftData / CloudKit; here it lives in memory with sample seeds.

@Observable
final class AppState {
    // MARK: Navigation
    enum Screen: Hashable {
        case home, library, recipe(id: String)
        case activeBake, scheduler, starter
        case diagnose, journal
    }

    var screen: Screen = .home
    var selectedRecipeId: String = "hokkaido"

    // MARK: Data
    var recipes: [Recipe]
    var starters: [Starter]
    var journal: [JournalEntry]
    var activeBake: ActiveBake?
    var insights: [Insight]

    // MARK: Environment
    var kitchenTempC: Double = 22.1
    var kitchenHumidityPct: Int = 54
    var ovenStatus: String = "Off · preheat 7:30 AM"
    var userName: String = "Marisol"
    var greeting: String { Self.greeting(for: Date()) }

    init() {
        self.recipes = SampleRecipes.all
        self.starters = SampleStarters.all
        self.journal = SampleJournal.all
        self.activeBake = AppState.makeSampleActiveBake()
        self.insights = Analytics.generateInsights(from: SampleJournal.all)
    }

    // MARK: Navigation helpers

    func goTo(_ screen: Screen) {
        withAnimation(.easeOut(duration: 0.18)) {
            self.screen = screen
        }
    }

    func openRecipe(_ id: String) {
        self.selectedRecipeId = id
        goTo(.recipe(id: id))
    }

    func recipe(_ id: String) -> Recipe? { recipes.first(where: { $0.id == id }) }
    func starter(_ id: String) -> Starter? { starters.first(where: { $0.id == id }) }

    // MARK: Sample active-bake (Marisol's Country Sourdough mid-bulk)

    private static func makeSampleActiveBake() -> ActiveBake {
        let calendar = Calendar.current
        let now = Date()
        // Started ~3h ago, bake-out tomorrow morning
        let startedAt = calendar.date(byAdding: .hour, value: -3, to: now) ?? now
        let bakeOut = calendar.date(byAdding: .hour, value: 14, to: now) ?? now

        let history: [ActiveBake.StageHistoryEntry] = [
            .init(stageIndex: 0, status: .done,    note: "Levain peaked at 9:48 PM"),
            .init(stageIndex: 1, status: .done,    note: "Autolyse 60m"),
            .init(stageIndex: 2, status: .done,    note: "Salt + levain incorporated"),
            .init(stageIndex: 3, status: .active,  note: "2 of 4 folds complete"),
            .init(stageIndex: 4, status: .pending, note: nil),
            .init(stageIndex: 5, status: .pending, note: nil),
            .init(stageIndex: 6, status: .pending, note: nil),
            .init(stageIndex: 7, status: .pending, note: nil),
        ]

        let photos: [Int: [ActiveBake.BakePhoto]] = [
            0: [.init(time: "4:18 PM", assetName: "starter", note: "Levain build")],
            2: [.init(time: "6:02 PM", assetName: "dough_bowl", note: "Shaggy mix")],
            3: [.init(time: "7:14 PM", assetName: "dough_bowl", note: "After fold 1"),
                .init(time: "7:46 PM", assetName: "crumb_open", note: "After fold 2 — windowpane")],
        ]

        return ActiveBake(
            recipeId: "country",
            startedAt: startedAt,
            bakeOutAt: bakeOut,
            currentStageIndex: 3,
            stageProgress: 0.62,
            kitchenTempC: 22,
            starterId: "ruby",
            history: history,
            stagePhotos: photos,
            foldsDone: 2,
            totalFolds: 4
        )
    }

    private static func greeting(for date: Date) -> String {
        let h = Calendar.current.component(.hour, from: date)
        switch h {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Up late"
        }
    }
}
