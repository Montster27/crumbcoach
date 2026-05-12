import Foundation
import SwiftUI

// App-wide observable state. Loads from / writes to PersistenceController on
// every meaningful mutation, debounced 1 second so slider drags don't thrash
// the disk.
//
// Mutations all go through methods on this class so call sites stay clean and
// every change point has a single place to schedule a save.

@Observable
final class AppState {

    // MARK: Navigation
    enum Screen: Hashable {
        case home, library, recipe(id: String)
        case activeBake, scheduler, starter
        case diagnose, journal
    }

    var screen: Screen = .home
    var selectedRecipeId: String

    // MARK: Persistent data
    var recipes: [Recipe]
    var starters: [Starter]
    var journal: [JournalEntry]
    var activeBake: ActiveBake?

    // MARK: Environment / kitchen
    var kitchenTempC: Double
    var kitchenHumidityPct: Int
    var ovenStatus: String
    var userName: String

    // MARK: Derived
    var insights: [Insight] {
        Analytics.generateInsights(from: journal)
    }
    var greeting: String { Self.greeting(for: Date()) }

    // MARK: Persistence

    private let persistence: PersistenceController
    private var saveTask: Task<Void, Never>?

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence

        if let loaded: PersistedState = persistence.load(), loaded.version == PersistedState.currentVersion {
            self.recipes            = loaded.recipes
            self.starters           = loaded.starters
            self.journal            = loaded.journal
            self.activeBake         = loaded.activeBake
            self.kitchenTempC       = loaded.kitchenTempC
            self.kitchenHumidityPct = loaded.kitchenHumidityPct
            self.ovenStatus         = loaded.ovenStatus
            self.userName           = loaded.userName
            self.selectedRecipeId   = loaded.selectedRecipeId
        } else {
            self.recipes            = SampleRecipes.all
            self.starters           = SampleStarters.all
            self.journal            = SampleJournal.all
            self.activeBake         = AppState.makeSampleActiveBake()
            self.kitchenTempC       = 22.1
            self.kitchenHumidityPct = 54
            self.ovenStatus         = "Off · preheat 7:30 AM"
            self.userName           = "Marisol"
            self.selectedRecipeId   = "hokkaido"
            saveSoon()
        }
    }

    /// Encode the entire mutable surface to a `PersistedState` and write it.
    /// Called on a 1-second debounce after any mutation so we don't write on
    /// every slider tick.
    func saveSoon() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self else { return }
            if Task.isCancelled { return }
            let snapshot = PersistedState(
                recipes: self.recipes,
                starters: self.starters,
                journal: self.journal,
                activeBake: self.activeBake,
                kitchenTempC: self.kitchenTempC,
                kitchenHumidityPct: self.kitchenHumidityPct,
                ovenStatus: self.ovenStatus,
                userName: self.userName,
                selectedRecipeId: self.selectedRecipeId
            )
            self.persistence.save(snapshot)
        }
    }

    /// Synchronous save — call on app background / scenePhase transitions
    /// where we can't wait for the debounce.
    func saveNow() {
        saveTask?.cancel()
        let snapshot = PersistedState(
            recipes: recipes,
            starters: starters,
            journal: journal,
            activeBake: activeBake,
            kitchenTempC: kitchenTempC,
            kitchenHumidityPct: kitchenHumidityPct,
            ovenStatus: ovenStatus,
            userName: userName,
            selectedRecipeId: selectedRecipeId
        )
        persistence.save(snapshot)
    }

    /// Reset everything to sample data. Useful for debug and "start over" UX.
    func resetToSamples() {
        recipes = SampleRecipes.all
        starters = SampleStarters.all
        journal = SampleJournal.all
        activeBake = AppState.makeSampleActiveBake()
        kitchenTempC = 22.1
        kitchenHumidityPct = 54
        ovenStatus = "Off · preheat 7:30 AM"
        userName = "Marisol"
        selectedRecipeId = "hokkaido"
        screen = .home
        saveSoon()
    }

    // MARK: Navigation helpers

    func goTo(_ screen: Screen) {
        withAnimation(.easeOut(duration: 0.18)) {
            self.screen = screen
        }
    }

    func openRecipe(_ id: String) {
        selectedRecipeId = id
        goTo(.recipe(id: id))
        saveSoon()
    }

    // MARK: Data lookups

    func recipe(_ id: String) -> Recipe? { recipes.first(where: { $0.id == id }) }
    func starter(_ id: String) -> Starter? { starters.first(where: { $0.id == id }) }

    // MARK: Mutation helpers (every mutator schedules a save)

    func markFold(_ index: Int) {
        guard var bake = activeBake else { return }
        bake.foldsDone = max(0, min(bake.totalFolds, index))
        activeBake = bake
        saveSoon()
    }

    func incrementFold() {
        guard let bake = activeBake else { return }
        markFold(bake.foldsDone + 1)
    }

    func updateRecipe(_ recipe: Recipe) {
        if let idx = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[idx] = recipe
        } else {
            recipes.append(recipe)
        }
        saveSoon()
    }

    func addJournalEntry(_ entry: JournalEntry) {
        journal.insert(entry, at: 0)
        saveSoon()
    }

    func updateKitchenTemp(_ temp: Double) {
        kitchenTempC = temp
        saveSoon()
    }

    func setUserName(_ name: String) {
        userName = name
        saveSoon()
    }

    // MARK: Sample active-bake (Marisol's Country Sourdough mid-bulk)

    private static func makeSampleActiveBake() -> ActiveBake {
        let now = Date()
        let startedAt = Calendar.current.date(byAdding: .hour, value: -3, to: now) ?? now
        let bakeOut   = Calendar.current.date(byAdding: .hour, value: 14, to: now) ?? now

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
