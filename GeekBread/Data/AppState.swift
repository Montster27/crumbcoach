import Foundation
import SwiftUI
import UserNotifications
import WidgetKit

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
        case diagnose, journal, settings
    }

    var screen: Screen = .home
    var selectedRecipeId: String

    /// Filename of a photo the user just captured on another screen, to be
    /// consumed by the diagnostic screen on appear. Not persisted — purely a
    /// short-lived hand-off slot.
    var pendingDiagnosticPhoto: String? = nil

    /// Recipe source URL waiting to be loaded into the editor. Set by the
    /// `geekbread://import?url=…` deep-link handler (Stage 18 share
    /// extension); consumed by `LibraryScreen` which opens the editor and
    /// clears the slot. Not persisted — purely a transient hand-off.
    var pendingImportURL: String? = nil

    /// Cached system permission state for local notifications. Refreshed on
    /// app foreground and after we prompt. Not persisted — the system is the
    /// source of truth.
    var notificationAuthStatus: UNAuthorizationStatus = .notDetermined

    /// Set when a photo save fails (JPEG encode error, disk full, etc).
    /// AppShell observes this and presents a non-blocking alert; the user
    /// dismisses it via `clearPhotoError()`. Not persisted — the error is
    /// only meaningful for the current attempt.
    var photoErrorMessage: String? = nil

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
    /// True once the user has cleared onboarding (entered their name). The
    /// GeekBreadApp scene presents `OnboardingScreen` until this flips true.
    var hasOnboarded: Bool
    /// Whether the user opts in to local crash + diagnostic collection via
    /// `TelemetryManager`. The toggle in Settings flips this; GeekBreadApp
    /// applies it on launch and on every change.
    var telemetryEnabled: Bool
    /// Display weight unit. Grams is the default; oz flips the recipe
    /// editor input and every weight callout across the app.
    var units: Units
    /// Source the kitchen temperature reading comes from. `.manual` ships
    /// in v1; `.homeKit` is the stub Settings exposes for Stage 20.
    var kitchenTempSource: KitchenTempSource
    /// Whether the user has opted in to iCloud Drive sync. CloudSyncManager
    /// owns the actual subscription / pull / push lifecycle; this field is
    /// just the persisted preference.
    var cloudSyncEnabled: Bool
    /// Whether the importer is allowed to call into Apple Foundation
    /// Models. Hidden in Settings when `AIRecipeAssist.isAvailable` is
    /// false; default off so we never silently consult an on-device model.
    var aiAssistEnabled: Bool
    /// Stage 24 — whether Cloud AI (Anthropic Claude Haiku) features are
    /// opted in. Gates every `RemoteAIClient.generate` call site. The
    /// API key lives in Keychain; this is just the persisted preference.
    /// Disabled until the user adds a key in Settings.
    var cloudAIEnabled: Bool
    /// Stage 25 — set once the user runs the Sourdough Sidekick pairing
    /// flow. Real BLE pairing is a future-phase add (waiting on the
    /// FirstBuild protocol); for now this just records pairing was
    /// attempted so Settings can show "Paired" instead of the discovery
    /// CTA on subsequent visits.
    var sidekickPaired: Bool

    // MARK: Derived
    var insights: [Insight] {
        Analytics.generateInsights(from: journal)
    }
    var greeting: String { Self.greeting(for: Date()) }

    // MARK: Persistence

    let persistence: PersistenceController
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
            // Grandfather pre-Stage-5 saves: if the user already had a name on
            // disk, treat them as onboarded even if the flag wasn't persisted.
            self.hasOnboarded       = loaded.hasOnboarded
                || !loaded.userName.trimmingCharacters(in: .whitespaces).isEmpty
            self.telemetryEnabled   = loaded.telemetryEnabled
            self.units              = loaded.units
            self.kitchenTempSource  = loaded.kitchenTempSource
            self.cloudSyncEnabled   = loaded.cloudSyncEnabled
            self.aiAssistEnabled    = loaded.aiAssistEnabled
            self.cloudAIEnabled     = loaded.cloudAIEnabled
            self.sidekickPaired     = loaded.sidekickPaired
        } else {
            // Fresh install: seed the curated recipe library + a starter so
            // the library/starter screens have something to explore, but DO
            // NOT pretend the user has an in-progress bake or a bake history.
            // The user is sent through onboarding to pick a name before the
            // main UI shows.
            self.recipes            = SampleRecipes.all
            self.starters           = SampleStarters.all
            self.journal            = []
            self.activeBake         = nil
            self.kitchenTempC       = 22.0
            self.kitchenHumidityPct = 50
            self.ovenStatus         = "Off"
            self.userName           = ""
            self.selectedRecipeId   = SampleRecipes.all.first?.id ?? ""
            self.hasOnboarded       = false
            self.telemetryEnabled   = true
            self.units              = .grams
            self.kitchenTempSource  = .manual
            self.cloudSyncEnabled   = false
            self.aiAssistEnabled    = false
            self.cloudAIEnabled     = false
            self.sidekickPaired     = false
            saveSoon()
        }

        // Apply the persisted telemetry preference up-front so MetricKit
        // subscription matches the user's choice from launch onward. The
        // call is idempotent and lightweight, safe to make every init.
        TelemetryManager.shared.setEnabled(self.telemetryEnabled)

        // Stage 27 — refresh Spotlight on launch so the system search
        // reflects whatever's in the loaded recipe library. Recipe edits
        // re-index via the saveSoon path.
        SpotlightIndex.index(self.recipes)
        // Recipe sync runs unconditionally when iCloud is signed in
        // (May 2026 — see CloudSyncManager.swift). Seed the published
        // status so Settings reflects iCloud availability immediately;
        // the first pull happens in `syncRecipesWithCloud()` on scene
        // active.
        Task { @MainActor in
            CloudSyncManager.shared.refreshAvailability()
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
                selectedRecipeId: self.selectedRecipeId,
                hasOnboarded: self.hasOnboarded,
                telemetryEnabled: self.telemetryEnabled,
                units: self.units,
                kitchenTempSource: self.kitchenTempSource,
                cloudSyncEnabled: self.cloudSyncEnabled,
                aiAssistEnabled: self.aiAssistEnabled,
                cloudAIEnabled: self.cloudAIEnabled,
                sidekickPaired: self.sidekickPaired
            )
            self.persistence.save(snapshot)
            // Recipe-only cloud sync (May 2026): recipe pushes happen
            // from the explicit recipe-mutation paths (`updateRecipe`,
            // `deleteRecipe`, `loadDemoData`, `startOver`) — not on
            // every save. Folds and stage advances rewrite state.json
            // but never touch the recipe library, so there's no reason
            // to re-upload `recipes.json` for those.
            // Refresh the Home Screen / Lock Screen widget snapshot. Cheap
            // no-op when the App Group entitlement isn't reachable.
            Task { @MainActor in
                self.updateWidgetSnapshot()
                // Re-index Spotlight so renames / deletions / fresh
                // imports surface in the system search.
                SpotlightIndex.index(self.recipes)
            }
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
            selectedRecipeId: selectedRecipeId,
            hasOnboarded: hasOnboarded,
            telemetryEnabled: telemetryEnabled,
            units: units,
            kitchenTempSource: kitchenTempSource,
            cloudSyncEnabled: cloudSyncEnabled,
            aiAssistEnabled: aiAssistEnabled,
            cloudAIEnabled: cloudAIEnabled,
            sidekickPaired: sidekickPaired
        )
        persistence.save(snapshot)
        // No recipe push here — recipe pushes are driven from the
        // explicit recipe-mutation paths. See saveSoon comment above.
        updateWidgetSnapshot()
    }

    /// Replace everything with the Marisol-style demo (named starters, sample
    /// journal, mid-bulk active bake). Reachable from Settings → "Load demo
    /// data" so a user who wants to see the full app can opt in.
    func loadDemoData() {
        recipes = SampleRecipes.all
        starters = SampleStarters.all
        journal = SampleJournal.all
        activeBake = AppState.makeSampleActiveBake()
        kitchenTempC = 22.1
        kitchenHumidityPct = 54
        ovenStatus = "Off · preheat 7:30 AM"
        userName = userName.isEmpty ? "Marisol" : userName
        selectedRecipeId = "hokkaido"
        hasOnboarded = true
        screen = .home
        // The sample bake isn't actually scheduled, so any pending bake
        // notifications point at the old data — clear them.
        NotificationManager.shared.cancelAllBakeReminders()
        runOnMainActor { LiveActivityManager.shared.end(immediate: true) }
        saveSoon()
        pushRecipesToCloud()
    }

    /// Clear personal data (journal, active bake) and re-trigger onboarding.
    /// Keeps the curated recipe library + starters so the app isn't a blank
    /// slate after the user lands on it again.
    func startOver() {
        journal = []
        activeBake = nil
        userName = ""
        hasOnboarded = false
        screen = .home
        recipes = SampleRecipes.all
        starters = SampleStarters.all
        selectedRecipeId = SampleRecipes.all.first?.id ?? ""
        NotificationManager.shared.cancelAllBakeReminders()
        runOnMainActor { LiveActivityManager.shared.end(immediate: true) }
        // Clear Spotlight + the widget snapshot so the system search and
        // Home Screen don't surface stale state after the reset.
        SpotlightIndex.clear()
        SharedContainer.writeWidgetSnapshot(WidgetSnapshot(generatedAt: Date(),
                                                            activeBake: nil))
        saveNow()
        pushRecipesToCloud()
    }

    /// Capture the user's name and flip the onboarded flag. Called from the
    /// onboarding screen's "Get started" button.
    func completeOnboarding(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        userName = trimmed.isEmpty ? "Baker" : trimmed
        hasOnboarded = true
        saveSoon()
    }

    // MARK: Navigation helpers

    /// Tracks `accessibilityReduceMotion`. AppShell mirrors the system value
    /// into this each time the user toggles Reduce Motion so screen
    /// transitions skip the slide/fade animation. Default `false` keeps the
    /// behavior unchanged for everyone else.
    var reduceMotion: Bool = false

    func goTo(_ screen: Screen) {
        if reduceMotion {
            self.screen = screen
        } else {
            // Spring with tight damping — feels snappier than the previous
            // `easeOut(0.18)` curve while still cushioning the arrival.
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                self.screen = screen
            }
        }
    }

    func openRecipe(_ id: String) {
        selectedRecipeId = id
        goTo(.recipe(id: id))
        saveSoon()
    }

    /// Route an incoming `geekbread://…` URL. Two shapes:
    ///   - `geekbread://recipe/<id>`  — open the recipe detail.
    ///   - `geekbread://import?url=<encoded>` — stash the URL in
    ///     `pendingImportURL` and navigate to the library so the editor
    ///     opens with the URL pre-filled (consumed by LibraryScreen).
    /// Unknown URLs are ignored — the caller has no other recourse.
    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "geekbread" else { return }
        let host = (url.host ?? "").lowercased()
        let path = url.pathComponents.filter { $0 != "/" }
        if host == "recipe", let id = path.first, recipe(id) != nil {
            openRecipe(id)
            return
        }
        if host == "import" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let encoded = components?.queryItems?
                .first(where: { $0.name == "url" })?.value,
               !encoded.isEmpty {
                pendingImportURL = encoded
                goTo(.library)
            }
            return
        }
    }

    // MARK: Data lookups

    func recipe(_ id: String) -> Recipe? { recipes.first(where: { $0.id == id }) }
    func starter(_ id: String) -> Starter? { starters.first(where: { $0.id == id }) }

    // MARK: Mutation helpers (every mutator schedules a save)

    func markFold(_ index: Int) {
        guard var bake = activeBake else { return }
        let previousFolds = bake.foldsDone
        bake.foldsDone = max(0, min(bake.totalFolds, index))
        activeBake = bake
        // Only fire a haptic when the value actually changed — tapping the
        // already-done fold count shouldn't buzz.
        if bake.foldsDone != previousFolds {
            Haptics.tick()
            pushLiveActivityUpdate()
        }
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
        pushRecipesToCloud()
    }

    /// Remove a recipe. If the detail screen is currently showing this id we
    /// route back to the library so the user doesn't get stranded on a
    /// "Recipe not found" stub.
    func deleteRecipe(id: String) {
        recipes.removeAll { $0.id == id }
        if case .recipe(let current) = screen, current == id {
            goTo(.library)
        }
        if selectedRecipeId == id {
            selectedRecipeId = recipes.first?.id ?? selectedRecipeId
        }
        saveSoon()
        pushRecipesToCloud()
    }

    /// Fire-and-forget recipe push. CloudSyncManager serializes
    /// overlapping pushes internally, so back-to-back recipe edits don't
    /// race on the iCloud file coordinator.
    private func pushRecipesToCloud() {
        let snapshot = recipes
        Task { await CloudSyncManager.shared.pushRecipes(snapshot) }
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

    /// Flip the telemetry opt-in flag and notify `TelemetryManager` so it
    /// subscribes / unsubscribes from MetricKit and (on disable) deletes
    /// stored payloads. Idempotent — calling with the current value is a
    /// no-op.
    func setTelemetryEnabled(_ enabled: Bool) {
        guard enabled != telemetryEnabled else { return }
        telemetryEnabled = enabled
        TelemetryManager.shared.setEnabled(enabled)
        saveSoon()
    }

    /// Switch between grams and ounces. Persistent recipe weights stay in
    /// grams; this only flips display + editor input. Idempotent.
    func setUnits(_ newUnits: Units) {
        guard newUnits != units else { return }
        units = newUnits
        saveSoon()
    }

    /// Pick the source for kitchen temperature. v1 only supports `.manual`
    /// end-to-end — `.homeKit` is a stub the Scheduler doesn't yet honor,
    /// but persisting the choice keeps the user's preference around for
    /// Stage 20.
    func setKitchenTempSource(_ source: KitchenTempSource) {
        guard source != kitchenTempSource else { return }
        kitchenTempSource = source
        saveSoon()
    }

    /// Legacy full-state iCloud sync toggle. As of the May 2026 recipes-
    /// only sync change, recipe sync runs automatically and this flag is
    /// no longer wired into CloudSyncManager. The setter is preserved so
    /// older persisted state still deserializes cleanly; flipping it has
    /// no effect on cloud behavior.
    func setCloudSyncEnabled(_ enabled: Bool) {
        guard enabled != cloudSyncEnabled else { return }
        cloudSyncEnabled = enabled
        saveSoon()
    }

    /// Toggle the Foundation Models import assist (Stage 17.5b). No-op
    /// when the device or OS doesn't support it; UI hides the toggle in
    /// that case so the user can't enable it pointlessly.
    func setAIAssistEnabled(_ enabled: Bool) {
        guard enabled != aiAssistEnabled else { return }
        aiAssistEnabled = enabled
        saveSoon()
    }

    /// Toggle Cloud AI features (Stage 24, haiku.md Tier 1). Gates every
    /// `RemoteAIClient.generate` call site. The key itself lives in
    /// Keychain — flipping this off doesn't delete the key, just stops
    /// us from using it. UI prevents the user from flipping this on
    /// without a key.
    func setCloudAIEnabled(_ enabled: Bool) {
        guard enabled != cloudAIEnabled else { return }
        cloudAIEnabled = enabled
        saveSoon()
    }

    /// Record Sourdough Sidekick pairing state (Stage 25). True after
    /// `SidekickManager` discovered a device by name; false when the user
    /// runs "Forget" from Settings. The actual peripheral identifier
    /// lives on `SidekickManager`; we keep `sidekickPaired` here only so
    /// Settings can render the right card state across launches.
    func setSidekickPaired(_ paired: Bool) {
        guard paired != sidekickPaired else { return }
        sidekickPaired = paired
        saveSoon()
    }

    /// Pull any newer cloud recipes, merge them into the live recipe
    /// library, then push the (possibly-merged) local copy back. Safe to
    /// call on launch, scene-active, and Settings "Sync now". When the
    /// pull replaces local recipes, dependent UI (`selectedRecipeId`,
    /// `activeBake.recipeId`) is reconciled so the user doesn't get
    /// stranded on a recipe that no longer exists.
    func syncRecipesWithCloud() async {
        await MainActor.run { CloudSyncManager.shared.refreshAvailability() }
        let pulled = await CloudSyncManager.shared.pullRecipesIfNewer()
        if let pulled, pulled != recipes {
            await MainActor.run { self.applyPulledRecipes(pulled) }
        }
        await CloudSyncManager.shared.pushRecipes(recipes)
    }

    /// Apply a freshly-pulled recipe array. Reconciles the currently-
    /// selected recipe and any in-flight active bake so the UI doesn't
    /// point at a stale id.
    private func applyPulledRecipes(_ pulled: [Recipe]) {
        recipes = pulled
        if recipes.first(where: { $0.id == selectedRecipeId }) == nil {
            selectedRecipeId = recipes.first?.id ?? selectedRecipeId
        }
        if case .recipe(let openId) = screen,
           recipes.first(where: { $0.id == openId }) == nil {
            goTo(.library)
        }
        SpotlightIndex.index(recipes)
        saveSoon()
    }

    // MARK: Live Activity bounce

    /// `LiveActivityManager` became `@MainActor` for Swift 6 isolation
    /// readiness. AppState itself is non-isolated (the saveSoon Task body
    /// runs off-main to keep disk I/O off the UI thread), so every call
    /// into the manager bounces through this fire-and-forget hop. Cheap
    /// — no awaiting on the caller, the manager's own operations are
    /// already non-blocking.
    private func runOnMainActor(_ action: @escaping @MainActor @Sendable () -> Void) {
        Task { @MainActor in action() }
    }

    // MARK: Widget snapshot

    /// Compute the widget-facing snapshot from the current state and write
    /// it to the App Group container, then ask WidgetKit to reload its
    /// timelines so the Home Screen / Lock Screen widgets reflect the new
    /// state within a few seconds. Cheap no-op when the App Group
    /// entitlement isn't reachable.
    private func updateWidgetSnapshot() {
        let snapshot = WidgetSnapshot(
            generatedAt: Date(),
            activeBake: makeWidgetBakeSummary()
        )
        SharedContainer.writeWidgetSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Build the activity summary or return nil when there is no active
    /// bake. Frozen at write time so the widget extension doesn't have to
    /// re-derive anything from the recipe library.
    private func makeWidgetBakeSummary() -> WidgetSnapshot.ActiveBakeSummary? {
        guard let bake = activeBake, let recipe = recipe(bake.recipeId) else {
            return nil
        }
        let stage = recipe.stages.indices.contains(bake.currentStageIndex)
            ? recipe.stages[bake.currentStageIndex] : nil
        let stageName = stage?.kind.rawValue ?? "—"

        // Pick the next action timestamp + label. Prefer the rebalanced
        // schedule (Stage 8) when present; fall back to bake-out for the
        // last stage.
        let now = Date()
        let nextActionAt: Date
        let nextActionLabel: String
        if bake.isComplete {
            nextActionAt = now
            nextActionLabel = "Log this bake"
        } else if let sched = bake.schedule {
            let upcoming = sched.steps.first {
                $0.status != .done && $0.status != .skipped && $0.start > now
            }
            if let upcoming, recipe.stages.indices.contains(upcoming.stageIndex) {
                nextActionAt = upcoming.start
                nextActionLabel = recipe.stages[upcoming.stageIndex].kind.rawValue
            } else {
                nextActionAt = bake.bakeOutAt
                nextActionLabel = "Bake out"
            }
        } else {
            nextActionAt = bake.bakeOutAt
            nextActionLabel = "Bake out"
        }

        return WidgetSnapshot.ActiveBakeSummary(
            recipeTitle: recipe.title,
            startedAt: bake.startedAt,
            bakeOutAt: bake.bakeOutAt,
            stageName: stageName,
            stageIndex: bake.currentStageIndex,
            stageCount: recipe.stages.count,
            foldsDone: bake.foldsDone,
            totalFolds: bake.totalFolds,
            nextActionAt: nextActionAt,
            nextActionLabel: nextActionLabel,
            isComplete: bake.isComplete
        )
    }

    // MARK: Photos

    /// Save an image to disk and attach a `BakePhoto` entry to the active
    /// bake's current (or specified) stage. Returns the stored filename, or
    /// nil if the underlying disk write failed — callers don't need to do
    /// anything beyond that; `photoErrorMessage` is set so the global alert
    /// will surface a user-visible explanation.
    @discardableResult
    func addPhoto(_ image: UIImage,
                  toStage stageIndex: Int? = nil,
                  note: String = "Just now") -> String? {
        guard let filename = persistence.savePhoto(image) else {
            photoErrorMessage = "Couldn't save that photo. Try again — your iPad may be low on storage."
            return nil
        }
        if var bake = activeBake {
            let idx = stageIndex ?? bake.currentStageIndex
            let photo = ActiveBake.BakePhoto(
                time: CCFormat.clockTime.string(from: Date()),
                assetName: filename,
                note: note
            )
            bake.stagePhotos[idx, default: []].append(photo)
            activeBake = bake
            saveSoon()
        }
        return filename
    }

    /// Save an image and stash it on the matching starter as its newest photo.
    @discardableResult
    func setStarterPhoto(_ image: UIImage, starterId: String) -> String? {
        guard let filename = persistence.savePhoto(image) else {
            photoErrorMessage = "Couldn't save that photo. Try again — your iPad may be low on storage."
            return nil
        }
        if let idx = starters.firstIndex(where: { $0.id == starterId }) {
            starters[idx].lastPhoto = filename
            starters[idx].lastPhotoTime = CCFormat.clockTime.string(from: Date())
            saveSoon()
        }
        return filename
    }

    /// Save a diagnostic photo and hand it off to the diagnostic screen via
    /// `pendingDiagnosticPhoto`. The diagnostic screen consumes the value on
    /// appear and clears it. Falls through to the global photo error if the
    /// save fails — the diagnostic screen stays on idle.
    func queueDiagnosticPhoto(_ image: UIImage) {
        guard let filename = persistence.savePhoto(image) else {
            photoErrorMessage = "Couldn't save that photo. Try again — your iPad may be low on storage."
            return
        }
        pendingDiagnosticPhoto = filename
    }

    /// Dismiss the photo-save error alert.
    func clearPhotoError() {
        photoErrorMessage = nil
    }

    // MARK: Starters

    /// Create a new starter and append it to the user's starters. Returns the
    /// generated id so the caller can immediately select the new chip.
    @discardableResult
    func addStarter(name: String,
                    flourType: String,
                    hydrationPct: Double = 100) -> String {
        let id = UUID().uuidString
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let starter = Starter(
            id: id,
            name: trimmedName.isEmpty ? "New starter" : trimmedName,
            flourType: flourType,
            hydrationPct: hydrationPct,
            ageDesc: "Just started",
            weightGrams: 0,
            state: "Just fed",
            stateKind: .good,
            storage: .counter,
            lastFeed: "Just now",
            peakAt: "—",
            nextFeed: "In 4–6h",
            peakHeightPct: 0,
            riseHistory: Array(repeating: 0, count: 12),
            feedings: []
        )
        starters.append(starter)
        saveSoon()
        return id
    }

    /// Append a feeding entry to the starter and reset its display state to
    /// "just fed". The rise chart can't actually rewind without a live data
    /// source — Stage 20 (HomeKit / Sidekick) will replace this with sampled
    /// values; for now the feeding is recorded and the metadata reflects it.
    func logStarterFeeding(starterId: String, ratio: String = "1:5:5") {
        guard let idx = starters.firstIndex(where: { $0.id == starterId }) else { return }
        let when = "Today \(CCFormat.clockTime.string(from: Date()))"
        let ambient = starters[idx].storage == .fridge ? 4.0 : kitchenTempC
        starters[idx].feedings.insert(
            StarterFeeding(when: when, ratio: ratio, ambientC: ambient),
            at: 0
        )
        starters[idx].lastFeed = "Just now"
        starters[idx].peakAt = "—"
        starters[idx].nextFeed = starters[idx].storage == .fridge ? "When you bake" : "In 4–6h"
        starters[idx].state = "Just fed"
        starters[idx].stateKind = .good
        saveSoon()
    }

    /// Persist a Cloud AI starter assessment back onto the matching
    /// starter (Stage 24, haiku.md Tier 1.2). Idempotent — passing the
    /// same value twice doesn't re-save. Nil clears any prior
    /// assessment, used when the user removes their starter photo.
    func setStarterAssessment(starterId: String, assessment: StarterAssessment?) {
        guard let idx = starters.firstIndex(where: { $0.id == starterId }) else { return }
        if starters[idx].assessment == assessment { return }
        starters[idx].assessment = assessment
        saveSoon()
    }

    /// Switch a starter between counter / fridge / vacation storage. Refreshes
    /// the visible state pill so the user sees the change reflected.
    func setStarterStorage(starterId: String, storage: StarterStorage) {
        guard let idx = starters.firstIndex(where: { $0.id == starterId }) else { return }
        starters[idx].storage = storage
        switch storage {
        case .counter:
            starters[idx].state = "Resting · counter"
            starters[idx].stateKind = .info
            starters[idx].nextFeed = "In 4–6h"
        case .fridge:
            starters[idx].state = "Resting · fridge"
            starters[idx].stateKind = .info
            starters[idx].nextFeed = "When you bake"
        case .vacation:
            starters[idx].state = "Resting · vacation"
            starters[idx].stateKind = .neutral
            starters[idx].nextFeed = "Long sleep"
        }
        saveSoon()
    }

    // MARK: Bake lifecycle

    /// Build a fresh `ActiveBake` from a user-confirmed schedule + recipe,
    /// schedule reminders, and navigate to the Active Bake screen. Replaces
    /// any in-progress bake — the UI funnels through here only after the user
    /// has confirmed on the Scheduler.
    func startBake(from schedule: Schedule,
                   recipe: Recipe,
                   starterId: String?) {
        let now = Date()
        let scheduledIndices = Set(schedule.steps.map(\.stageIndex))
        let firstScheduled = scheduledIndices.sorted().first ?? 0
        let history: [ActiveBake.StageHistoryEntry] = recipe.stages.indices.map { idx in
            let status: StepStatus
            if !scheduledIndices.contains(idx) {
                status = .skipped
            } else if idx == firstScheduled {
                status = .active
            } else {
                status = .pending
            }
            // Mark the landing stage as entered NOW so completeBake can report
            // real elapsed times. Earlier-skipped stages get no timestamps.
            return ActiveBake.StageHistoryEntry(
                stageIndex: idx,
                status: status,
                note: nil,
                enteredAt: status == .active ? now : nil,
                exitedAt: nil
            )
        }

        // If we land on a bulk-fold stage at start, use its fold count;
        // otherwise borrow from the recipe's first bulk-fold stage anywhere.
        // Final fallback of 4 covers legacy recipes with no per-stage count.
        let landingStage = recipe.stages.indices.contains(firstScheduled)
            ? recipe.stages[firstScheduled] : nil
        let firstFoldStage = recipe.stages.first(where: { $0.kind == .bulkFold })
        let foldSource = landingStage?.kind == .bulkFold ? landingStage : firstFoldStage

        activeBake = ActiveBake(
            recipeId: recipe.id,
            startedAt: schedule.startTime,
            bakeOutAt: schedule.endTime,
            currentStageIndex: firstScheduled,
            stageProgress: 0,
            kitchenTempC: schedule.kitchenTempC,
            starterId: starterId,
            history: history,
            stagePhotos: [:],
            foldsDone: 0,
            totalFolds: max(1, foldSource?.totalFolds ?? 4),
            schedule: schedule
        )
        NotificationManager.shared.scheduleBakeReminders(for: schedule,
                                                           recipe: recipe)
        // Hand off to the lock-screen / Dynamic Island UI. The activity
        // updates on every fold/advance/skip and ends on completeBake.
        if let bake = activeBake {
            let title = recipe.title
            let started = schedule.startTime
            let liveState = liveActivityState(for: bake, recipe: recipe)
            runOnMainActor {
                LiveActivityManager.shared.start(
                    recipeTitle: title,
                    startedAt: started,
                    state: liveState
                )
            }
        }
        saveSoon()
        goTo(.activeBake)
    }

    /// Mark the current stage done and move to the next non-skipped stage.
    /// At the last stage, leave `currentStageIndex` in place but flip the
    /// history entry to `.done` so `isComplete` flips true.
    func advanceStage() {
        Haptics.advance()
        moveStage(markingCurrentAs: .done)
    }

    /// Mark the current stage skipped and move to the next non-skipped stage.
    func skipStage() {
        Haptics.advance()
        moveStage(markingCurrentAs: .skipped)
    }

    /// Shared body for advance/skip — only the status on the outgoing entry
    /// changes.
    private func moveStage(markingCurrentAs status: StepStatus) {
        guard var bake = activeBake, let recipe = recipe(bake.recipeId) else { return }
        let now = Date()
        let outgoingRecipeIdx = bake.currentStageIndex
        if let outIdx = bake.history.firstIndex(where: { $0.stageIndex == outgoingRecipeIdx }) {
            bake.history[outIdx].status = status
            bake.history[outIdx].exitedAt = now
        }
        let next = (bake.currentStageIndex + 1..<recipe.stages.count).first { idx in
            bake.history.first(where: { $0.stageIndex == idx })?.status != .skipped
        }
        if let next {
            bake.currentStageIndex = next
            bake.stageProgress = 0
            if let inIdx = bake.history.firstIndex(where: { $0.stageIndex == next }) {
                bake.history[inIdx].status = .active
                bake.history[inIdx].enteredAt = now
            }
            // Reset fold counters when entering a bulk-fold stage so the UI
            // ring starts at 0/N for the new stage's N.
            if recipe.stages[next].kind == .bulkFold {
                bake.foldsDone = 0
                bake.totalFolds = max(1, recipe.stages[next].totalFolds ?? bake.totalFolds)
            }
        }
        // No next stage: bake is complete. The history entry was just flipped
        // so `bake.isComplete` is now true and the UI surfaces the wrap-up.

        // Rebalance the stored schedule against wall-clock NOW and replace the
        // pending reminder set. Done/skipped stages keep their already-elapsed
        // times; the just-transitioned stage's end becomes `now`, and every
        // remaining stage slides to stack from there (re-applying Q10 against
        // the bake's kitchen temp). Pre-Stage-8 bakes have no `schedule`
        // stored, so we leave their notification cadence alone.
        if var sched = bake.schedule,
           let outScheduleIdx = sched.steps.firstIndex(where: { $0.stageIndex == outgoingRecipeIdx }) {
            sched = Scheduler.rebalance(
                sched,
                currentStageIndex: outScheduleIdx,
                newCurrentEnd: now,
                ambientC: bake.kitchenTempC,
                historyPct: 0,
                recipe: recipe
            )
            // Mark the outgoing schedule step with the same terminal status
            // the history just got — keeps the two views in sync, and lets
            // the timeline strip reflect skipped stages visually.
            sched.steps[outScheduleIdx].status = status
            bake.schedule = sched
            bake.bakeOutAt = sched.endTime

            if bake.isComplete {
                NotificationManager.shared.cancelAllBakeReminders()
            } else {
                NotificationManager.shared.scheduleBakeReminders(for: sched, recipe: recipe)
            }
        }

        activeBake = bake
        pushLiveActivityUpdate()
        saveSoon()
    }

    /// Compute the current activity-visible ContentState and push it to the
    /// running Live Activity (no-op when no activity is in flight). Used
    /// after fold ticks and stage transitions.
    private func pushLiveActivityUpdate() {
        guard let bake = activeBake, let recipe = recipe(bake.recipeId) else { return }
        let state = liveActivityState(for: bake, recipe: recipe)
        runOnMainActor { LiveActivityManager.shared.update(state) }
    }

    /// Snapshot of bake/recipe state in the shape the widget renders.
    /// Pulled out so both `startBake` and update calls can share it.
    private func liveActivityState(for bake: ActiveBake,
                                    recipe: Recipe) -> ActiveBakeAttributes.ContentState {
        let stageName = recipe.stages.indices.contains(bake.currentStageIndex)
            ? recipe.stages[bake.currentStageIndex].kind.rawValue
            : "—"
        // Minutes from now until the next scheduled action point. Prefer
        // the rebalanced schedule when available (Stage 8); fall back to
        // the bake-out target.
        let now = Date()
        let next: Date = {
            if let sched = bake.schedule {
                let upcoming = sched.steps
                    .first { $0.status != .done && $0.status != .skipped && $0.start > now }
                return upcoming?.start ?? sched.endTime
            }
            return bake.bakeOutAt
        }()
        let minutes = max(Int(next.timeIntervalSince(now) / 60), -999)
        return ActiveBakeAttributes.ContentState(
            stageName: stageName,
            foldsDone: bake.foldsDone,
            totalFolds: bake.totalFolds,
            minutesToNextAction: minutes,
            bakeOutAt: bake.bakeOutAt,
            isComplete: bake.isComplete
        )
    }

    /// Log the bake to the journal, update the recipe's lastBake, clear
    /// `activeBake`, cancel reminders, and return to Home. Caller is expected
    /// to gate this on `bake.isComplete`.
    func completeBake(rating: Int, note: String) {
        guard let bake = activeBake, let recipe = recipe(bake.recipeId) else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()

        // Real elapsed bulk time when we have the timestamps; fall back to the
        // recipe baseline for pre-Stage-3 bakes (no enteredAt/exitedAt).
        let bulkEntry = bake.history.first { entry in
            let kind = recipe.stages[entry.stageIndex].kind
            return kind == .bulk || kind == .bulkFold
        }
        let bulkMinutes: Int = {
            if let bulk = bulkEntry,
               let entered = bulk.enteredAt,
               let exited = bulk.exitedAt {
                return max(0, Int(exited.timeIntervalSince(entered) / 60))
            }
            return recipe.stages.first(where: { $0.kind == .bulk || $0.kind == .bulkFold })?.durationMin ?? 0
        }()

        // Pick the freshest photo across the bake: highest stage index, most
        // recently appended within that stage.
        let photoAsset: String? = bake.stagePhotos.keys.sorted(by: >).lazy
            .compactMap { idx in bake.stagePhotos[idx]?.last?.assetName }
            .first

        // Stage 18.5b — capture every stage's actual elapsed time so the
        // analytics layer can later compute kitchen-learned averages.
        // Only entries that BOTH entered and exited contribute; stages
        // the user skipped or never reached are absent from the map.
        var stageDurations: [Int: Int] = [:]
        for historyEntry in bake.history {
            guard let entered = historyEntry.enteredAt,
                  let exited = historyEntry.exitedAt else { continue }
            let mins = max(0, Int(exited.timeIntervalSince(entered) / 60))
            stageDurations[historyEntry.stageIndex] = mins
        }

        let entry = JournalEntry(
            id: UUID().uuidString,
            recipeId: recipe.id,
            bakedAt: now,
            rating: max(1, min(5, rating)),
            hydrationPct: recipe.hydrationPct,
            bulkMinutes: bulkMinutes,
            kitchenC: bake.kitchenTempC,
            note: trimmedNote,
            photoAsset: photoAsset,
            diagnosis: "Self-rated",
            stageDurations: stageDurations.isEmpty ? nil : stageDurations
        )
        addJournalEntry(entry)

        var updatedRecipe = recipe
        updatedRecipe.lastBake = Recipe.LastBake(
            rating: entry.rating,
            bakedAt: now,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )
        updateRecipe(updatedRecipe)

        activeBake = nil
        NotificationManager.shared.cancelAllBakeReminders()
        runOnMainActor { LiveActivityManager.shared.end() }
        Haptics.success()
        saveSoon()
        goTo(.home)
    }

    // MARK: Notifications

    /// Prompt for permission the first time and refresh our cached auth
    /// status. Idempotent: subsequent calls just re-read system state.
    /// Returns true when notifications can fire after the call.
    @discardableResult
    func requestNotificationPermission() async -> Bool {
        let granted = await NotificationManager.shared.requestPermissionIfNeeded()
        let status = await NotificationManager.shared.authorizationStatus()
        await MainActor.run { self.notificationAuthStatus = status }
        return granted
    }

    /// Drop every pending bake reminder. Used when completing a bake or
    /// resetting to samples.
    func cancelAllBakeReminders() {
        NotificationManager.shared.cancelAllBakeReminders()
    }

    /// Pull the latest auth status from the system. Cheap, async; call on
    /// foreground and when surfacing the denied-banner UI.
    func refreshNotificationAuthStatus() async {
        let status = await NotificationManager.shared.authorizationStatus()
        await MainActor.run { self.notificationAuthStatus = status }
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
