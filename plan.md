# CrumbCoach — Implementation Plan

Staged roadmap from the current TestFlight-ready prototype to a fully
functional app. Each stage is self-contained: a future Claude session can
pick up any one stage, follow the linked files, and ship it without
needing context from the previous stages (beyond reading this preamble).

---

## Preamble — read this every session

### Project state

- iPad-only SwiftUI app, iOS 17+, landscape, full-screen (no Split View).
- XcodeGen project (`project.yml` → `Crumbcoach.xcodeproj`). **Regenerate
  the project after editing `project.yml` or adding/removing files:**
  ```bash
  xcodegen generate
  ```
- Bundle id: `com.monty.crumbcoach.app` (this repo, signed under Monty's
  personal team `9C4LVC9DR6`). Forks change `DEVELOPMENT_TEAM` + every
  `com.monty.crumbcoach.app*` reference in `project.yml` (main + widget
  + share + tests targets, plus the iCloud container in `entitlements`).
- Repo: <https://github.com/Montster27/crumbcoach>.
- Currently in TestFlight as `GeekBread` 0.1.0.

### Key files (memorize these paths)

```
Crumbcoach/
├── CrumbcoachApp.swift              # @main, scenePhase persist hook
├── Models/                          # Codable structs — Recipe, Stage,
│                                    # Ingredient, Preferment, Starter,
│                                    # Schedule, ActiveBake, JournalEntry,
│                                    # Insight
├── Core/                            # Pure functions, no UI deps
│   ├── BakersPercentages.swift      # computePercentages, scale, adjustHydration, HydrationWarning
│   ├── Conversion.swift             # tangzhong, yudane, yeasted→sourdough
│   ├── Scheduler.swift              # generateForward, generateReverse, rebalance
│   ├── StarterPrediction.swift      # minutesToPeak, levainBuild
│   ├── Analytics.swift              # generateInsights, correlations
│   └── Formatters.swift             # CCFormat
├── Data/
│   ├── AppState.swift               # @Observable; mutation helpers + saveSoon()
│   ├── PersistedState.swift         # versioned on-disk shape
│   ├── PersistenceController.swift  # JSON → Application Support
│   ├── SampleRecipes.swift          # 9 seed recipes
│   ├── SampleStarters.swift         # Ruby + Ozzy
│   └── SampleJournal.swift          # 6 sample bakes
├── DesignSystem/
│   ├── Theme.swift                  # colors, Typography
│   └── Components.swift             # Card, Kicker, StatusPill, TagPill,
│                                    # RingProgress, Sparkline, BreadPhoto,
│                                    # CCIcon/CCIconView, CCButtonStyle
├── Shared/                          # Cross-cutting helpers (Stage 1+)
│   └── PhotoPicker.swift            # PHPicker + UIImagePicker wrappers,
│                                    # .photoPicker(isPresented:onPick:) modifier
└── Features/
    ├── Shell/AppShell.swift         # sidebar + header
    ├── Home/HomeScreen.swift
    ├── Library/LibraryScreen.swift
    ├── Library/RecipeDetailScreen.swift
    ├── ActiveBake/ActiveBakeScreen.swift
    ├── Scheduler/SchedulerScreen.swift
    ├── Starter/StarterScreen.swift
    ├── Diagnostic/DiagnosticScreen.swift
    └── Journal/JournalScreen.swift
```

Tests live in `CrumbcoachTests/` and cover the four `Core/` modules.

### Conventions

- **Persistence:** every state mutation goes through a named method on
  `AppState` and calls `saveSoon()`. Never mutate `state.foo` directly from
  a view; add a helper like `state.markFold()` instead.
- **Screen state:** screens take `var state: AppState` (not `@Bindable`
  unless they actually write to `$state.foo`). Local UI-only state lives
  in `@State` properties on the screen.
- **Layout:** sidebar 232pt (scales with dynamic type), right rail
  typically 360pt, content fills the rest. Don't introduce breakpoints —
  the app is landscape-only.
- **Typography:** `Typography.display / .ui / .mono` only. Custom font
  names fall back to system fonts automatically.
- **Colors:** `Theme.*` only. Don't hardcode hex except for one-offs that
  match the existing palette (e.g. annotation marker colors).
- **Comments:** explain *why*, never *what*. The code names are clear; the
  reasoning is what rots.

### Build / test commands

```bash
# Regenerate Xcode project after editing project.yml or adding files
xcodegen generate

# Typecheck app (works around the broken simulator runtime on dev Macs)
find Crumbcoach -name "*.swift" -print0 | xargs -0 swiftc -typecheck \
  -sdk $(xcrun --sdk iphoneos --show-sdk-path) \
  -target arm64-apple-ios17.0 -swift-version 5

# Tests (requires working simulator)
xcodebuild test -project Crumbcoach.xcodeproj -scheme Crumbcoach \
  -destination 'platform=iOS Simulator,name=iPad Pro (12.9-inch)'
```

### How to commit & push

```bash
git add -A
git commit -m "<imperative subject>

<optional body>"
git push
```

Conventional commit subject prefixes are fine but not required. Co-author
trailers are appreciated.

---

## Stage 1 — Camera & photo picker

**Goal:** wire the "Take photo" / "Add photo" buttons throughout the app
to real photo capture or library picker, persisting selected images into
the `ActiveBake.stagePhotos` model and the diagnostic flow.

**Effort:** ~half day.

### Where the stubs live today

- [`HomeScreen.swift`](Crumbcoach/Features/Home/HomeScreen.swift) — the
  "Take photo" button on the Diagnose card. Routes to `state.goTo(.diagnose)`
  today; should also seed the diagnostic state with a photo.
- [`ActiveBakeScreen.swift`](Crumbcoach/Features/ActiveBake/ActiveBakeScreen.swift) —
  `Button { } label: { Label("Add photo", systemImage: "camera") }` in the
  current-stage action bar. Also the dashed `Button(action: {})` in each
  timeline row.
- [`DiagnosticScreen.swift`](Crumbcoach/Features/Diagnostic/DiagnosticScreen.swift) —
  the giant camera button in `idleOverlay` currently just calls
  `startAnalysis()` which is a timer. Should open a picker / camera first,
  load the chosen image, then start (stubbed) analysis on it.
- [`StarterScreen.swift`](Crumbcoach/Features/Starter/StarterScreen.swift) —
  "Photo · 6:14 PM today" badge implies a starter photo flow; needs an
  "Add photo" affordance.

### Implementation

1. **Info.plist** — add usage descriptions in `project.yml`:
   ```yaml
   NSCameraUsageDescription: "Photograph your crumb, dough, and starter so CrumbCoach can analyze and log them."
   NSPhotoLibraryUsageDescription: "Attach photos from your library to bakes and diagnostics."
   ```
   Then `xcodegen generate`.

2. **New file:** `Crumbcoach/Shared/PhotoPicker.swift`
   - SwiftUI wrapper around `PHPickerViewController` for library picking.
   - SwiftUI wrapper around `UIImagePickerController` with `.camera`
     source for live capture (PHPicker doesn't support camera).
   - Single API: `PhotoPicker(source: .camera | .library, onPick: (UIImage) -> Void)`
     presented as a `.sheet`.

3. **Persist images.** UIImage isn't Codable. Two options:
   - Save as JPEG bytes to `Application Support/Crumbcoach/photos/<uuid>.jpg`,
     store the relative path string in `BakePhoto.assetName`.
   - Or embed base64 in JSON (simpler, fine for the data volume here).

   Choose path-based storage — JSON pretty-printed with embedded base64
   blows up file size. Add `PersistenceController.photosDirectory` and
   helpers `savePhoto(_ image: UIImage) -> String` (returns filename) and
   `loadPhoto(named: String) -> UIImage?`.

4. **Update `BreadPhoto`** in [`Components.swift`](Crumbcoach/DesignSystem/Components.swift)
   to try loading from the photos directory before falling back to bundled
   asset name, before falling back to gradient.

5. **AppState helper:**
   ```swift
   func addPhoto(_ image: UIImage, toStage stageIndex: Int, note: String = "Just now") {
       let filename = persistence.savePhoto(image)
       let photo = ActiveBake.BakePhoto(time: CCFormat.clockTime.string(from: Date()),
                                         assetName: filename, note: note)
       activeBake?.stagePhotos[stageIndex, default: []].append(photo)
       saveSoon()
   }
   ```

6. **Wire the buttons.** Each "Add photo" button presents a confirmation
   dialog ("Choose photo" / "Take photo") → `PhotoPicker` sheet → calls
   `state.addPhoto`.

### Acceptance criteria

- Tapping any "Add photo" button presents a sheet with camera and library
  options.
- Picking a photo persists it to disk and shows it in the timeline strip
  (replacing the camera-icon placeholder).
- App relaunches show the photos still there.
- Info.plist usage strings are descriptive and don't trigger App Store
  Review rejection.

### Don't touch

- The AI diagnostic state machine (Stage X) — leave the stubbed
  `startAnalysis()` timer. Just feed it a real photo.
- The model itself; reuse `ActiveBake.BakePhoto`.

### Stage 1 — completion notes

What landed and what later stages can lean on:

- `Crumbcoach/Shared/PhotoPicker.swift` — `PhotoPicker(source:onPick:)` and a
  `View.photoPicker(isPresented:onPick:) -> UIImage` modifier that shows a
  confirmation dialog (Camera / Library) and then the sheet. Camera falls
  through to the library if the device has no camera (e.g. Simulator).
- `PersistenceController` exposes `photosDirectory: URL`,
  `savePhoto(_:quality:) -> String` (returns `<uuid>.jpg`),
  `loadPhoto(named:) -> UIImage?`, and `photoURL(for:) -> URL`.
- `BreadPhoto(assetName:)` resolves disk → bundled asset → gradient, so any
  filename returned from `savePhoto` Just Works as an asset name.
- `AppState`:
  - `persistence` is now `let` (was `private`) — Stage 2's
    `NotificationManager` is free to read/write its own files via the same
    controller if it ever needs to.
  - `addPhoto(_:toStage:note:) -> String` — attach to active bake.
  - `setStarterPhoto(_:starterId:) -> String` — overwrites the selected
    starter's `lastPhoto` / `lastPhotoTime`.
  - `queueDiagnosticPhoto(_:)` + `pendingDiagnosticPhoto: String?` — one-shot
    hand-off slot consumed by `DiagnosticScreen.onAppear`. Not persisted.
- `Starter` gained `lastPhoto: String?` and `lastPhotoTime: String?` (both
  default to nil — old persisted state still decodes cleanly).
- `Info.plist` has `NSCameraUsageDescription` and
  `NSPhotoLibraryUsageDescription` (configured in `project.yml`).

Known gaps deliberately left for later:

- Diagnostic "edit context" / region annotations still operate on the
  showcase image overlay; not pixel-aligned to user photos.
- Starter photo flow stores only `lastPhoto` — no per-feeding photo history.
- "View grid →" in the ActiveBake timeline header is still a stub.

---

## Stage 2 — Local notifications for schedule

**Goal:** when a bake is in progress, the schedule actually pings the
user at each action point — fold reminders, mix-time, oven preheat, bake
out.

**Effort:** ~half day.

### Implementation

1. **Info.plist** — add `UIBackgroundModes` for remote-notification not
   needed; local notifications don't require it. But the app needs:
   ```yaml
   NSUserNotificationsUsageDescription: "Remind you when each bake step is due — folds, shaping, baking."
   ```
   (Note: iOS 17 doesn't strictly require a usage string for local
   notifications; the system shows a permission dialog automatically. The
   string is courtesy.)

2. **New file:** `Crumbcoach/Shared/NotificationManager.swift`
   - Singleton wrapping `UNUserNotificationCenter`.
   - `requestPermissionIfNeeded() async -> Bool`.
   - `scheduleBakeReminders(for schedule: Schedule, recipe: Recipe)` — for
     every step whose stage kind warrants a reminder (folds, shape, retard
     end, bake start, bake out), creates a `UNTimeIntervalNotificationTrigger`
     at the step's start time. Identifier = `bake-<scheduleId>-<stepIdx>` so
     we can cancel/replace.
   - `cancelBakeReminders(for scheduleId: UUID)`.

3. **Action-point heuristics.** Don't notify on every stage; honor the
   spec's "no spam" principle:
   - `.mix`, `.bulkFold` (each fold cycle), `.preShape`, `.finalShape`,
     `.coldRetard` (start + end), `.bake` (start), and "bake out" (end).
   - Skip `.autolyse`, `.bulk` (silent unless it's the only stage),
     `.cookTangzhong`, `.prepYudane`.

4. **Hook into the start-a-bake flow** (Stage 3). When a new bake starts,
   schedule reminders. When the user manually advances or skips a stage,
   `state.activeBake?.history` changes — recompute and replace pending
   notifications via `cancelBakeReminders` + `scheduleBakeReminders`.

5. **Permission flow.** First time the user taps "Confirm & start" on the
   scheduler, request permission. If denied, surface a small banner on
   the active-bake screen: "Reminders off. Enable in Settings to be
   pinged at each step."

### Acceptance criteria

- After starting a bake, the system shows a permission dialog (once).
- Notifications fire at the expected step times when the app is
  backgrounded or device is locked.
- Tapping a notification opens the app to the Active Bake screen.
- Skipping a stage cancels its pending notification.

### Don't touch

- Schedule math is solid; don't refactor `Scheduler`. Just consume its
  output.

### Stage 2 — completion notes

What landed and what Stage 3 can lean on:

- `Crumbcoach/Shared/NotificationManager.swift` — `NotificationManager.shared`
  singleton wrapping `UNUserNotificationCenter`. Public API:
  - `authorizationStatus() async -> UNAuthorizationStatus`
  - `requestPermissionIfNeeded() async -> Bool` (idempotent; reads system
    state, only prompts when `.notDetermined`)
  - `scheduleBakeReminders(for schedule:Schedule, recipe:Recipe)` —
    cancels every prior `bake-*` reminder then schedules one
    `UNTimeIntervalNotificationTrigger` per action point, keyed
    `bake-<schedule.id>-<stepIdx>(-<subIdx>)`.
  - `cancelBakeReminders(for scheduleId: UUID)` — narrow cancel for one
    schedule.
  - `cancelAllBakeReminders()` — broad cancel, used by `resetToSamples`.
  - `NotificationManager.bakeReminderTapped` — `Notification.Name` posted
    on `NotificationCenter.default` when a bake reminder is tapped. The
    shell observes it and routes to `.activeBake`.
- Action-point heuristics (private to the manager) cover `.mix`,
  `.bulkFold` (4 evenly-spaced fold pings — Stage 3 will replace 4 with a
  real `Stage.totalFolds`), `.preShape`, `.finalShape`, `.coldRetard`
  (start + end), and `.bake` (start + end / bake-out). Autolyse, plain
  bulk, divides, scalds, etc. are intentionally silent per spec.
- `AppState` gained:
  - `notificationAuthStatus: UNAuthorizationStatus` — cached system state
    used to drive the denied banner. Not persisted (system is the truth).
  - `requestAndScheduleBakeReminders(for:recipe:) async -> Bool` — prompts
    on first call, refreshes cached status, schedules if granted.
  - `cancelAllBakeReminders()`
  - `refreshNotificationAuthStatus() async`
- `CrumbcoachApp.init` touches `NotificationManager.shared` so the
  delegate is registered before scenes connect (avoids dropping a
  cold-launch tap). `scenePhase == .active` refreshes the cached auth
  status; `bakeReminderTapped` routes to `.activeBake`.
- `SchedulerScreen.confirmAndStart` calls the AppState helper inside a
  `Task` then immediately navigates — Stage 3 will replace this with
  `startBake(from:recipe:)` and the bake creation will live there.
- `ActiveBakeScreen` shows a `NotificationsDeniedBanner` (warm/amber,
  "Open Settings" deep link) above the bake content when
  `notificationAuthStatus == .denied`. The screen `.task` refreshes the
  status on appear.
- `project.yml` adds `NSUserNotificationsUsageDescription` (regenerated
  into `Info.plist`).

Known gaps deliberately left for Stage 3:

- ~~`bulkFold` always assumes 4 folds.~~ Closed in Stage 3 — manager now reads
  `Stage.totalFolds ?? 4`.
- No persisted "active schedule id" — `cancelAllBakeReminders` is the
  safe sledgehammer until Stage 3 binds a Schedule to an ActiveBake.
- ~~The Scheduler still navigates to the seeded sample bake on confirm.~~
  Closed in Stage 3 — `confirmAndStart` now calls
  `state.startBake(from:recipe:starterId:)`.

Post-Stage 3 follow-ups landed:

- Cancel-add race: replaced the prefix-fetch cancellation with a deterministic
  `scheduledIdentifiers: Set<String>` tracked alongside each `add()`, so cancel
  is synchronous and freshly-scheduled requests can't be swept up by a stale
  async callback. The set is hydrated from existing pending requests on
  singleton init, so prior-launch reminders remain cancellable.
- Multi-bake recipes: the bake-out "pull the bread from the oven" body now
  fires only on the *last* `.bake` step; earlier bake steps in
  double-bake recipes get a softer "First bake done…" instead.
- Cold-launch tap: delegate sets a `pendingBakeTap` flag in addition to
  posting `bakeReminderTapped`; `consumePendingBakeTap()` is drained by the
  shell on first appear so a tap before SwiftUI observers attach isn't lost.

---

## Stage 3 — Real "Start a bake" flow

**Goal:** when the user picks a recipe + start time on the Scheduler and
hits "Confirm & start", a *new* `ActiveBake` is created from that
schedule and persisted. The app stops always showing the seeded Country
Sourdough.

**Effort:** ~1 day.

### Current state

[`SchedulerScreen.swift`](Crumbcoach/Features/Scheduler/SchedulerScreen.swift)'s
"Confirm & start" button currently just navigates: `state.goTo(.activeBake)`.
The active bake on the receiving end is always the seeded sample.

### Implementation

1. **AppState helper:**
   ```swift
   func startBake(from schedule: Schedule, recipe: Recipe, starterId: String?) {
       let now = Date()
       let history = schedule.steps.enumerated().map { idx, _ in
           ActiveBake.StageHistoryEntry(stageIndex: idx, status: .pending, note: nil)
       }
       activeBake = ActiveBake(
           recipeId: recipe.id,
           startedAt: schedule.startTime,
           bakeOutAt: schedule.endTime,
           currentStageIndex: 0,
           stageProgress: 0,
           kitchenTempC: schedule.kitchenTempC,
           starterId: starterId,
           history: history,
           stagePhotos: [:],
           foldsDone: 0,
           totalFolds: recipe.stages.first(where: { $0.kind == .bulkFold })?.totalFolds ?? 4
       )
       NotificationManager.shared.scheduleBakeReminders(for: schedule, recipe: recipe)
       saveSoon()
       goTo(.activeBake)
   }
   ```
   (`totalFolds` needs adding to `Stage` — see model change below, or
   default to 4.)

2. **Stage advancement.** Add to `AppState`:
   ```swift
   func advanceStage() { /* mark current done, move to next */ }
   func skipStage()    { /* mark current skipped, move to next */ }
   func completeBake(rating: Int, note: String) {
       // Create JournalEntry from active bake, append, clear activeBake
   }
   ```
   The Active Bake screen's "Mark fold done" button on the last fold
   should advance the stage. "Skip stage" button should call skipStage.

3. **Empty active-bake state.** If `state.activeBake == nil`, the Active
   Bake sidebar entry should be hidden or show "No active bake — start one
   on the Scheduler." Same for Home: hide the active-bake banner.

4. **Sidebar "LIVE" badge** should only render when `state.activeBake != nil`.

### Acceptance criteria

- Pick a recipe + target time + "Confirm & start" → Active Bake screen
  now shows the *new* bake (different recipe, different start time).
- Advance / skip stages → history updates and persists across launches.
- "Complete bake" → adds to Journal, clears active bake, returns to Home.
- Notifications from Stage 2 fire on the new schedule.

### Don't touch

- The seeded `ActiveBake` factory (`AppState.makeSampleActiveBake()`)
  stays as the fallback for first-launch demo data.

### Stage 3 — completion notes

What landed and what later stages can lean on:

- `Stage` gained an optional `totalFolds: Int?` (defaults to nil — old
  persisted recipes decode unchanged). `bulkFold` stages in the seed library
  now carry the count explicitly (Country/Ciabatta 4, Baguette/Focaccia 3).
  `NotificationManager` reads `recipe.stages[step.stageIndex].totalFolds ?? 4`
  so the fold pings always match the recipe rather than a hardcoded 4.
- `ActiveBake.isComplete` (computed): `!history.isEmpty &&
  history.allSatisfy { .done || .skipped }`. UI gates the wrap-up flow on this.
- `AppState`:
  - `startBake(from:recipe:starterId:)` — builds a fresh `ActiveBake` from a
    confirmed `Schedule` + `Recipe`. History spans every recipe stage; stages
    not present in the schedule (e.g. cold retard when the user opted out)
    are pre-marked `.skipped`, the first scheduled stage starts `.active`,
    the rest `.pending`. `currentStageIndex` lands on the first scheduled
    stage. `totalFolds` is sourced from that stage if it's a bulk-fold, else
    the recipe's first bulk-fold stage, else 4. Schedules reminders via
    `NotificationManager.shared.scheduleBakeReminders` and navigates to
    `.activeBake`.
  - `advanceStage()` / `skipStage()` — both flip the outgoing history entry
    (`.done` vs `.skipped`) and move `currentStageIndex` to the next
    non-skipped recipe stage. Entering a bulk-fold stage resets
    `foldsDone = 0` and refreshes `totalFolds` from the stage. When there's
    no next stage, `currentStageIndex` stays put and `isComplete` flips
    true on the next state read.
  - `completeBake(rating:note:)` — writes a `JournalEntry` (current time,
    clamped 1-5 rating, recipe hydration, recipe bulk/bulkFold duration,
    bake's kitchen temp, freshest stage photo, diagnosis "Self-rated"),
    updates `Recipe.lastBake`, clears `activeBake`, cancels all bake
    reminders, and navigates home.
  - `requestNotificationPermission() async -> Bool` replaces the Stage 2
    `requestAndScheduleBakeReminders`. Scheduling is now `startBake`'s
    responsibility, so the helper just prompts + refreshes the cached
    `notificationAuthStatus`.
- `SchedulerScreen.confirmAndStart` now calls
  `state.startBake(from:recipe:starterId:)` with the first user starter for
  sourdough recipes (nil for everything else) and fires the permission
  prompt in parallel.
- `ActiveBakeScreen`:
  - New `EmptyActiveBakeView` with an "Open Scheduler" CTA when
    `state.activeBake == nil` (replaces the bare "No active bake" string).
  - `primaryActionButton(bake:stage:)` morphs through three states:
    `Mark fold N done` (bulk-fold with folds remaining), `Mark <stage> done`
    (advance any other stage), `Complete bake` (when `bake.isComplete`).
  - `Skip stage` now calls `state.skipStage()`; disabled once
    `bake.isComplete`.
  - `CompleteBakeSheet` — 5-star rating + note `TextField`, presented as a
    `.sheet` when the user taps the wrapped-up primary button. Hands the
    rating + note to `state.completeBake`.
- `AppShell`:
  - Sidebar "LIVE" badge on the Active Bake entry is gated on
    `state.activeBake != nil` (was always on).
  - Header title for `.activeBake` falls back to "No bake in progress" when
    the bake is nil and shows "<recipe> · ready to log" when complete.

Known gaps deliberately left for later:

- Notifications are scheduled once at `startBake` and never recomputed when
  the user advances / skips / runs late. The Plan §2 hook (cancel + replace
  on history change) is still TODO for a future refinement.
- `completeBake` writes recipe baseline `bulkMinutes` to the journal rather
  than the actual elapsed bulk window — fine for v1, revisit when we track
  actual stage durations.
- The seeded `ActiveBake.makeSampleActiveBake()` remains the first-launch
  fallback; we don't autorun `startBake` from sample data.

Post-Stage 3 follow-ups landed:

- Scheduler now seeds `recipeId` from `state.selectedRecipeId` in its `init`,
  so tapping "Schedule a bake" on a recipe detail arrives with the right
  recipe selected instead of resetting to the default.
- `confirmAndStart` prompts for notification permission *before* calling
  `state.startBake` (was the other order). The confirm button is disabled via
  an `isConfirming` flag while the prompt is in-flight so a double-tap can't
  spawn two bakes.
- `RecipeDetailScreen` "Open original" actually opens the URL via
  `UIApplication.shared.open` (was a no-op).

---

## Stage 4 — Recipe editor

**Goal:** create / edit / delete user recipes via a real UI, not just
edit the seeded ones in-memory.

**Effort:** ~1–2 days.

### Implementation

1. **New file:** `Features/Library/RecipeEditorScreen.swift`. Modal sheet
   (`.sheet`) with three sections:
   - **Metadata** — title, bread type, source kind (Original / User-
     created / Linked URL).
   - **Ingredients** — `List` of `Ingredient` rows, swipe-to-delete,
     add-row button. Each row edits name + category + weight (grams).
     Baker's % is derived, never edited directly.
   - **Stages** — `List` of `Stage` rows, drag to reorder, swipe-to-delete.
     Each row edits kind, duration (minutes), temperature, note.

2. **Wire it in:**
   - `Library` screen's "New recipe" button presents the editor with an
     empty `Recipe`.
   - `Recipe Detail` screen gains an "Edit" button (probably right next
     to the "Open original" affordance) that presents the editor with the
     current recipe.
   - On save: `state.updateRecipe(_:)` (already exists).
   - On delete (from the editor's destructive action): `state.deleteRecipe(id:)`
     needs adding.

3. **Validation.** Title non-empty, at least one flour ingredient, at
   least one stage, no negative weights. Show inline errors; disable Save
   until valid.

4. **URL recipes — minimal first pass.** When source is `.linked`,
   surface a text field for the URL. Don't implement JSON-LD parsing
   yet (that's Stage 9). Just store the URL string.

### Acceptance criteria

- Create a new recipe end-to-end, see it appear in the Library grid.
- Edit a recipe, see numbers recompute via `BakersMath`.
- Delete a recipe; if it was the selected one, the detail screen
  gracefully returns to Library.
- Validation prevents broken recipes from being saved.

### Don't touch

- `BakersMath` is fine; it'll recompute correctly on any well-formed
  recipe.
- Don't try to handle every edge case (preferments editing,
  twin-scald). Edit the simple case first; preferments are read-only in
  v1.

### Stage 4 — completion notes

What landed and what later stages can lean on:

- New file `Features/Library/RecipeEditorScreen.swift`. Modal sheet with
  three Form sections (Recipe metadata / Ingredients / Stages) wrapped
  in a `NavigationStack` for Cancel + Save chrome. Sized
  `minWidth: 640, idealWidth: 760, minHeight: 720, idealHeight: 860`
  for iPad landscape.
- Editing UX:
  - Ingredients: name + category Picker + grams. Swipe-to-delete via
    `.onDelete`. "Add ingredient" appends a blank flour row.
  - Stages: kind Picker + minutes + optional °C + optional note.
    `.onDelete` + `.onMove` (via `EditButton`). Bulk-fold stages also
    expose a `totalFolds` `Stepper` (1...10).
  - URL field is always visible. If filled on save, source becomes
    `.linked(url:sourceName:sourceLogo:nil)`; if empty on a brand-new
    recipe, source stays `.userCreated`; for edits with no URL the
    existing source is preserved.
- `RecipeEditorScreen.blank()` seeds new recipes with a four-fold
  sourdough skeleton (flour / water / salt / levain + mix → bulkFold →
  shape → retard → bake) so the editor isn't empty.
- Save flow recomputes `totalDoughGrams` from ingredient sums, then
  re-derives each ingredient's `bakersPct` against the flour total, then
  re-derives recipe-level `hydrationPct / saltPct / leavenPct` via
  `BakersMath.computePercentages`. Blank-name zero-weight rows are
  dropped. After save the editor sets `state.selectedRecipeId` to the
  new id so the library scrolls/highlights cleanly.
- Validation surfaces inline only after the first Save tap (`triedSave`
  flag): title non-empty, ≥1 flour ingredient with weight > 0, ≥1
  stage, no negative weights/durations.
- `AppState.deleteRecipe(id:)` added. If the current screen is
  `.recipe(id)` we route back to `.library`; if `selectedRecipeId`
  matched we move it to the first remaining recipe.
- Wiring:
  - `LibraryScreen` — "New recipe" and "Paste URL" both present the
    editor as `.sheet(isPresented: $editorOpen)`. The URL flow uses the
    same editor; user types the URL in the metadata section.
  - `RecipeDetailScreen` — new "Edit" button next to "Open original" in
    the header. "Open original" now actually opens the linked URL via
    `UIApplication.shared.open`.

Known gaps deliberately left for later:

- Preferments (tangzhong / yudane / levain build) are read-only — the
  editor can't add or modify preferment blocks. Hand-edit through code
  for now.
- `twinScald` toggle isn't exposed. Existing twin-scald recipes round-
  trip but can't be created in the editor.
- "Paste URL" doesn't pre-parse the URL or fetch JSON-LD — Stage 8.
- No photo picker for `Recipe.photo` yet; the editor preserves the
  existing asset name but can't change it.

---

## Stage 5 — Settings & onboarding

**Goal:** users can customize the app (name, units, sensor source,
reset) and new users see a brief intro on first launch.

**Effort:** ~half day.

### Settings

1. **New file:** `Features/Settings/SettingsScreen.swift`. Reach via a
   gear icon in the sidebar footer (next to the Kitchen card).
   - Profile: user name (`state.setUserName`).
   - Units: grams vs ounces (add `Units` enum to AppState; convert in
     formatters).
   - Kitchen temperature: manual entry vs HomeKit (UI only for now;
     HomeKit integration is Tier 3).
   - Notifications: open Settings.app link if denied.
   - Reset to sample data (`state.resetToSamples()`).
   - About: version, privacy policy URL, build number.

### Onboarding

2. **New file:** `Features/Onboarding/OnboardingScreen.swift`. Presented
   as `.fullScreenCover` when `state.hasOnboarded == false`.
   - Page 1: "One app for every bread you bake."
   - Page 2: "Bake with the timer, get reminders, see what worked."
   - Page 3: name entry + notification-permission prompt.
   - On complete: set `state.hasOnboarded = true` (add to PersistedState).

### Acceptance criteria

- First launch shows onboarding. Subsequent launches don't.
- Settings actions all work; "Reset to samples" restores the seeded data
  and returns to Home.
- Units setting flips between g and oz globally.

### Don't touch

- The persistence schema works; just add fields to `PersistedState`.
  Version bump optional — graceful fallback handles old files.

### Stage 5 — completion notes

What landed:

- **Clean first-launch state.** Fresh installs no longer ship with the
  Marisol-style mid-bulk active bake or the 6 demo journal entries.
  Recipes (9) and starters (2) still seed — they're the curated library
  + sample starters worth exploring. `userName` starts empty, kitchen
  defaults to 22.0 °C / 50 % / Off.
- **`PersistedState.hasOnboarded: Bool = false`** added (defaulted so
  pre-Stage-5 saves still decode). `AppState.init` grandfathers existing
  users: if a loaded save has a non-empty `userName`, the user is
  considered onboarded even if the flag was missing.
- **`OnboardingScreen`** (`Features/Onboarding/OnboardingScreen.swift`)
  — single-card layout with brand mark, name field, "Get started"
  primary button, and a "Load demo data" secondary link. Presented as
  `fullScreenCover` from `CrumbcoachApp.body` while
  `!state.hasOnboarded`. Submit calls `state.completeOnboarding(name:)`
  which flips the flag and dismisses.
- **`SettingsScreen`** (`Features/Settings/SettingsScreen.swift`)
  — Profile (rename), Notifications status pill + Settings.app deep link,
  Data ("Load demo" / "Start over"), About (version, build, counts).
- **`AppState`** additions:
  - `hasOnboarded: Bool` stored property (was inferred-only before).
  - `completeOnboarding(name:)` — sets `userName` (falling back to "Baker"
    on empty input) and flips `hasOnboarded` true.
  - `loadDemoData()` (renamed from `resetToSamples`) — keeps the user's
    name if non-empty; otherwise restores Marisol.
  - `startOver()` — clears journal + active bake, keeps the curated
    recipe library + starters, flips `hasOnboarded` false so the user is
    sent back through onboarding. Uses `saveNow` for an immediate flush.
  - New `.settings` screen case (in `Screen` enum + `AppShell` switch +
    `screenId` map).
- **`AppShell`** sidebar gains a Settings item (gear icon). Header copy
  for `.home` falls back to just the greeting when `userName` is empty
  ("Good morning" instead of "Good morning, "). Brand subtitle falls
  back to "Your kitchen" when `userName` is empty.
- **`StarterScreen`** now seeds `selectedId` from
  `state.starters.first?.id` instead of hard-coding `"ruby"`. Empty
  starter list renders no detail panel (chips row is also empty).
- **CCIcon** gains `.settings = "gearshape"` and `.trash`.

Known gaps:

- Units (g vs oz), kitchen-temperature source switcher (manual vs
  HomeKit), and the multi-page onboarding tour are still TODO — the
  scope was scaled back to the minimum that makes the app feel like
  yours rather than Marisol's.
- The "Load demo data" alert wording calls itself destructive, but it
  is — it replaces the user's journal/active bake. A future pass could
  warn more explicitly or merge instead of replace.

---

## Phase A — Pre-1.0 ship-readiness (blocking for App Store)

These six are what makes the difference between "TestFlight prototype"
and "App Store 1.0". Every item is reachable from the current shell;
none introduces new architecture. Reviewers and users will notice each
gap.

### Stage 6 — Stub-button cleanup

Audit every visible button in the app and either wire it or remove it.
Today's empty-closure offenders, by screen:

- **ActiveBake**: "Running late", timeline "View grid →", proof-oven "Undo →".
- **Diagnostic**: "Edit context →", share button (`square.and.arrow.up`).
- **Starter**: "Add starter", "Feed now", "Refrigerate", date-range chips.
- **Journal**: "Export to Markdown" (will be wired in Stage 16).
- **Header chrome**: search icon, notification bell.

For each: decide whether the action ships in v1.0 or gets pulled.
Anything not shipping should be removed visually — empty buttons leave
users wondering what they're missing.

### Stage 6 — completion notes

Ship vs. pull decisions:

- **Wired (ship v1):** Starter screen's Add starter / Feed now /
  Refrigerate — these are core starter management. Date-range chips
  on the rise chart were pulled (no multi-day data behind them).
- **Pulled (out of v1):** ActiveBake "Running late" / "View grid →" /
  proof-oven "Undo →"; Diagnostic "Edit context →" + share button;
  Journal "Export to Markdown"; header search + notification bell.
  Pulled means deleted from the UI, not visually hidden — empty
  closures masquerading as features will not ship.

Source of truth for the wired actions:

- `AppState.addStarter(name:flourType:hydrationPct:) -> String` — appends
  a fresh `Starter` (UUID id, default counter / 100% hydration, empty
  feedings, flat rise history) and returns its id so the calling screen
  can switch to it.
- `AppState.logStarterFeeding(starterId:ratio:)` — inserts a feeding
  entry at index 0 with `when = "Today \(clockTime)"`, fills ambient
  temperature from `kitchenTempC` (or 4 °C if in the fridge), and resets
  the display state to `"Just fed"` / `stateKind == .good`.
- `AppState.setStarterStorage(starterId:storage:)` — flips storage and
  rewrites the visible state pill + next-feed label so the user sees the
  change. Counter↔Fridge↔Vacation are all covered.

UI changes worth flagging for later stages:

- The Starter rise chart still shows a 12-hour static history regardless
  of the starter's recent feedings — Stage 20's HomeKit / Sidekick path
  is the real fix. The kicker still hardcodes "last 12 hours" because
  that's the only window the data supports today.
- "Feed now" doesn't yet predict a new peak time — `peakAt` resets to
  `—` and `nextFeed` to `"In 4–6h"`. Once we have live sensor data
  (Stage 20 / Stage 25), the prediction can replace these strings.
- The "Refrigerate" button now toggles between "Refrigerate" and
  "Bring to counter" based on `starter.storage`, so the action label
  always reflects what tapping it will do.
- The starter AI-check card still contains the hardcoded "State: post-
  peak. Surface flattening, large open bubbles…" copy. That's a Stage 7
  empty-state concern, not a Stage 6 stub.

### Stage 7 — Empty & error states

The screens look broken when they have no data:

- **Journal** with 0 entries renders the synthetic bulk-time chart
  ("What your last 6 bakes are telling us") with no actual bakes —
  confusing and dishonest.
- **Starter** with 0 starters renders an empty switcher row and no
  detail panel.
- **Home** insights strip renders an empty grid when there are no
  insights to surface.
- **No-photo** state in journal entries and active-bake timelines
  shows a placeholder camera icon — fine, but the "0 photos this
  bake" copy could be friendlier.

Also: surface user-visible errors for the failure paths we silently
swallow today — `persistence.savePhoto` failures, `center.add`
permission rejections, JSON-LD import errors.

### Stage 7 — completion notes

Empty states landed across the three screens called out in the plan:

- `JournalScreen` now branches at the top of `body`: if
  `state.journal.isEmpty`, the screen renders just `EmptyJournalView`
  (icon + copy + "Open Scheduler" CTA). With data it renders the normal
  left/right layout, but the bulk-time-vs-rating trend card is gated on
  `state.journal.filter { $0.recipeId == "country" }.count >= 3` —
  the chart was hardcoded to Country Sourdough and looked dishonest with
  fewer than three real bakes.
- `BulkTimeChart` no longer appends 8 synthetic priors; it plots only
  real journal points. With < 3 country bakes the chart never renders.
- `JournalScreen.monthSummaryCard` lost the fake subtitles
  ("+2 vs last month", "↑ 0.4", "1.2°C cooler", "King Arthur 70%") and
  the entirely-fake "Flour used 5.4 kg" row. Values are now the real
  count / average rating / average kitchen °C with no commentary.
- `HomeScreen.InsightsStrip` is wrapped in `if !state.insights.isEmpty`
  — the whole card disappears when there's no journal to summarize. The
  "last 6 bakes" headline now reads "last \(min(6, journal.count)) bakes"
  so the number stays honest during the 1-5 entry ramp-up.
- `HomeScreen.StarterCard`'s `EmptyView` branch is gone; with no
  starters it shows a dashed-border CTA card ("Add a starter →") that
  still routes to the Starter screen on tap.
- `StarterScreen` body now branches on `state.starters.isEmpty`: empty
  → `EmptyStarterView` with "Add starter" primary CTA that opens the
  same `AddStarterSheet` Stage 6 added; non-empty → the normal
  switcher + detail layout. No more orphan addStarterButton sitting
  beside an empty switcher row.
- `ActiveBakeScreen` timeline header copy adapts to photo count:
  0 → "tap the camera in each stage to log a photo"; 1 → "1 photo this
  bake"; N → "N photos this bake".

`Analytics.generateInsights` was the upstream culprit feeding the
ghost insights tile: it always tacked on a hardcoded flour-stub
insight ("Switching to King Arthur bread flour shortened your bulk by
~20 min."). The function now early-returns `[]` for an empty journal
and the flour-stub is gone — that placeholder reappears as a real
insight once we track ingredient brands.

Photo error path:

- `PersistenceController.savePhoto(_:quality:) -> String?` now returns
  nil if JPEG encoding fails or the disk write throws — previously both
  paths were silently swallowed with `try?` and we handed back a
  filename pointing at a file that didn't exist.
- `AppState` propagates the optional through `addPhoto`,
  `setStarterPhoto`, and `queueDiagnosticPhoto`. On nil, the helper
  sets `photoErrorMessage` and returns nil without mutating any state.
- New `AppState.photoErrorMessage: String?` (not persisted) +
  `clearPhotoError()`. `AppShell.body` attaches a global
  `.alert("Couldn't save photo", …)` bound to this field so the
  message surfaces from whichever screen tried to save.
- `DiagnosticScreen` is the only direct caller of
  `persistence.savePhoto` (it needs the filename synchronously to feed
  the analyzer); it now checks the optional and sets the same
  `photoErrorMessage` on failure.

Notification `center.add` failures are intentionally left silent — the
authorized path is the only place this gets reached, and the worst case
is one missed reminder. The denied path was already surfaced by Stage
2's `NotificationsDeniedBanner`. JSON-LD import errors aren't yet
relevant because import doesn't exist (Stage 17).

Known gaps:

- The Starter AI-check card still hardcodes "State: post-peak. Surface
  flattening, large open bubbles. Use now…" regardless of the
  starter's actual storage / state. Replacing that copy with a real
  derivation from `Starter.stateKind` is polish for Stage 14, not
  Stage 7.
- The Home `UpNextCard` still references "Country Sourdough at 10 AM
  Sun" even when the user has no such recipe. Real personalization
  belongs to Stage 12+ (multi-page onboarding) or whenever we add a
  "favorite recipe" notion.
- Photo error copy is one fixed string — once Stage 9 wires up crash
  reporting we can differentiate JPEG-encode vs. disk-full and tell
  the user which one to act on.

### Stage 8 — Notification rescheduling on advance / skip

Stage 3 known gap. `NotificationManager.scheduleBakeReminders` runs
once at `startBake` time; if the user skips a fold or runs late, the
old fold pings still fire on their original cadence.

Fix:
- Persist the active `Schedule` alongside the `ActiveBake` (currently
  derived ephemerally in `SchedulerScreen.schedule`).
- On every `AppState.advanceStage` / `skipStage`, recompute the
  schedule from the *current* stage start and call
  `NotificationManager.scheduleBakeReminders` again. The synchronous
  cancel-by-id path makes this safe to call repeatedly.

### Stage 8 — completion notes

- `ActiveBake.schedule: Schedule? = nil` — the confirmed schedule now
  rides on the bake itself (was ephemeral on `SchedulerScreen`).
  Optional + default so pre-Stage-8 persisted bakes still decode;
  those bakes simply skip the rebalance path. New bakes set
  `bake.schedule = schedule` at `startBake` time, and the schedule is
  re-saved on every state transition.
- `AppState.moveStage` (the shared body for `advanceStage` /
  `skipStage`) now rebalances `bake.schedule` against wall-clock
  `now` via `Scheduler.rebalance`:
  - The outgoing schedule step's `end` becomes `now`, its `start`
    stays put so the journal can later report real elapsed time, and
    its `status` is flipped to match the history entry (`.done` or
    `.skipped`) so the schedule and history don't drift apart.
  - Subsequent stages re-stack from `now`, re-applying Q10 against
    `bake.kitchenTempC`. `bake.bakeOutAt` is updated to the new
    schedule end-time so the recipe header card and Live Activity
    preview reflect the slip.
  - `NotificationManager.scheduleBakeReminders(for:recipe:)` is then
    called fresh — its synchronous cancel-and-replace path replaces
    every pending `bake-*` request, so leftover fold/shape/retard
    pings from the previous cadence can never fire on the old times.
  - When the move flips `bake.isComplete` (the user advanced/skipped
    past the last stage), we call `cancelAllBakeReminders` instead so
    no zombie reminders linger between the user wrapping up and the
    journal-entry sheet appearing.
- "Running late" stayed pulled in Stage 6 — there's no explicit "I'm
  behind" button, but the rebalance covers the de-facto late case
  automatically: when the user finally advances after lingering on a
  stage, every subsequent reminder reanchors from that moment. A
  future stage can re-introduce the explicit button by calling the
  same path with a user-supplied delta.

Known gaps deliberately left for later:

- The Active Bake screen still shows the bake's *original* recipe
  stage durations in the timeline rail rather than the rebalanced
  schedule. Surfacing the live schedule durations is a cosmetic
  refactor for Stage 14 polish.
- `Scheduler.rebalance` uses `historyPct: 0` in this path — we don't
  yet feed user-history adjustments into mid-bake reflows. Stage 24
  (on-device AI) is the more interesting place to add that signal.
- Demo bakes (`AppState.makeSampleActiveBake`) have `schedule == nil`
  on purpose — their reminders aren't scheduled by `startBake`, so
  there's nothing to reschedule.

### Stage 9 — Crash reporting & telemetry

Sentry or Apple's MetricKit / TelemetryDeck. Privacy-friendly,
opt-out toggle in Settings. Without this, we can't tell whether v1.0
is crashing in real kitchens. Spec §13.

Surface in `SettingsScreen.aboutCard`: "Send anonymous usage data
to help fix bugs" toggle.

### Stage 9 — completion notes

Pragmatic v1 picked MetricKit over Sentry / TelemetryDeck:

- Zero third-party dependencies — `MetricKit` ships with iOS.
- No backend required — we don't run a crash-ingestion service yet,
  so an "upload everything on a timer" design would have nothing on
  the other end. MetricKit + manual share matches our infrastructure.
- Apple's App Store Connect crash analytics still surfaces aggregated
  crashes automatically (via the system-level "Share with App
  Developers" toggle). MetricKit adds programmatic access to the same
  payloads so the user can hand us a detailed report when asked.

What landed:

- `Crumbcoach/Shared/TelemetryManager.swift` — `NSObject` singleton
  conforming to `MXMetricManagerSubscriber`. Public surface:
  - `setEnabled(_:)` — idempotent subscribe / unsubscribe. Disabling
    also deletes every stored payload (toggle off is a real reset,
    not a pause).
  - `storedPayloadFiles() -> [URL]` — every JSON payload on disk,
    newest first.
  - `diagnosticReportText() -> String?` — concatenated text blob
    suitable for the iOS share sheet. Nil when no payloads exist.
  - `didReceive(_:)` for both `MXMetricPayload` and
    `MXDiagnosticPayload` — saves the raw `jsonRepresentation()` into
    `<App Support>/Crumbcoach/telemetry/<kind>-<ts>-<uuid>.json`,
    logs counts via `os.Logger`.
- `PersistedState.telemetryEnabled: Bool = true` — opt-out model per
  spec. Default ensures fresh installs subscribe and pre-Stage-9
  saves grandfather to opted-in.
- `AppState.telemetryEnabled` is stored + persisted; the init applies
  the preference via `TelemetryManager.shared.setEnabled` so the
  subscription state matches the saved choice from launch onward.
  `setTelemetryEnabled(_:)` is the mutator the Settings toggle calls.
- `SettingsScreen.telemetryCard` — explanatory copy plus the toggle.
  When enabled, a "Share" button under the toggle hands the
  concatenated report text to a `UIActivityViewController`-wrapping
  `ShareSheet` (presented as `.sheet`). The Share button is disabled
  until at least one payload has actually arrived from MetricKit
  (which is daily, not real-time — the helper copy says so).
- `CrumbcoachApp.init` no longer touches telemetry directly;
  `AppState.init` is the single place the subscription gets applied,
  which dodges the "read `@State` from `App.init`" SwiftUI footgun.

Privacy posture summary, for the App Store privacy questionnaire
(Stage 11):

- Data we collect on-device: MetricKit crash + hang diagnostics and
  daily metric payloads (CPU / memory / disk-write outliers, signpost
  intervals). Apple-aggregated; no PII.
- Data we transmit: none, automatically. Users can manually share
  reports via the iOS share sheet.
- Identifiers: none beyond what MetricKit itself includes (already
  privacy-anonymized by Apple).
- Toggle path: Settings → Diagnostics → "Collect crash diagnostics on
  this iPad".

Known gaps:

- No backend ingestion means we still rely on App Store Connect's
  automatic crash analytics for the actual "is v1 crashing" signal.
  Wiring a Sentry/TelemetryDeck account is a Phase D consideration
  once the user base justifies it.
- `MXMetricPayload.jsonRepresentation()` produces verbose JSON; we
  don't redact anything on the local side. App sandbox already keeps
  this private to the user.
- We don't yet count "share button taps" or surface which payloads
  the user has already shared. Stage 14 polish if it ever matters.

### Stage 10 — Accessibility audit

- VoiceOver labels on every interactive element. Many of our custom
  `Button { Label(...) }` views render the label visually but not as
  an accessibility label.
- Dynamic Type rollout beyond the sidebar (active-bake numbers,
  recipe-detail tables).
- High-contrast mode pass — verify all `Theme.*` colors meet WCAG AA
  on white.
- Reduced motion: gate the `.easeOut(duration: 0.18)` screen-switch
  animation in `AppShell` behind `@Environment(\.accessibilityReduceMotion)`.

### Stage 10 — completion notes

**VoiceOver:**

- `CCIconView` now defaults to `.accessibilityHidden(true)`. The
  overwhelming majority of icon usages pair an SF Symbol with sibling
  text — VoiceOver would otherwise read "Camera. Take photo." for
  every Label. The decorative default cleans that up across every
  screen.
  - New optional `accessibilityLabel: String?` parameter exposes the
    icon explicitly when it IS the meaning (no current callers; the
    hook is there for future icon-only contexts).
- Icon-only buttons now carry explicit `.accessibilityLabel`:
  - DiagnosticScreen idle-overlay big camera ("Take crumb photo" +
    hint "Opens the camera or photo library to start a diagnostic").
  - `FeedbackButton` thumbs up / thumbs down ("Useful" / "Not
    useful") with `.isSelected` trait when active.
  - `AnnotationOverlay` (the colored region markers over the crumb
    photo) is fully `.accessibilityHidden(true)` — they were already
    `.allowsHitTesting(false)` but visible to VoiceOver.
- The `CompleteBakeSheet` rating stars are now a single
  `.accessibilityElement(children: .contain)` group labeled "Rating"
  with value `"\(rating) of 5 stars"`. Each star button still works
  individually but VoiceOver also gets a coherent summary.
- `FoldChip` (tap-gesture, not a Button) gets `.accessibilityAddTraits(.isButton)`
  plus a label ("Fold N of M") and value (Done / Up next / Pending)
  so VoiceOver can both find the chips and announce their state.

**Dynamic Type:**

- `Typography.display / .ui / .mono` now anchor every font to `.body`:
  - Custom-font path: `Font.custom(name, size:size, relativeTo: .body)`
    so installed Instrument Serif / Geist / Geist Mono scale with the
    user's Larger Text setting.
  - System-fallback path: `UIFontMetrics(forTextStyle: .body).scaledValue(for: size)`
    so the same scaling applies when the bundled font isn't loaded.
- The `Theme.swift` file gained `import UIKit` because `UIFontMetrics`
  lives there.
- Side effect: every Text in the app now scales beyond the sidebar
  bounds the plan called out — active-bake numbers, recipe-detail
  tables, journal cards, etc. The sidebar's existing
  `@Environment(\.dynamicTypeSize)` scaling stays in place and now
  agrees with the rest of the UI.

**Reduced motion:**

- `AppState.reduceMotion: Bool = false`. `AppShell` mirrors
  `@Environment(\.accessibilityReduceMotion)` into it on appear and
  on change.
- `AppState.goTo(_:)` no longer wraps the screen switch in
  `withAnimation` when `reduceMotion == true` — the state change
  still happens, just instantly.
- The ScrollView's screen-switch `.transition` is also gated:
  `reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top))`.

**Contrast audit on white (#FFFFFF) — WCAG AA findings:**

Colors that pass for normal body text (≥ 4.5:1):
`slate500..slate950`, `primaryDeep`, `warm700`, `accent`,
`success700`, `pillGoodFg`, `pillWarnFg`, `pillInfoFg`, `pillBadFg`,
`pillNeutFg`.

Colors that pass only for large text (3:1 ≤ contrast < 4.5):
`slate400` (decorative + large-only usages today),
`primary` (#B86A3A — used as link color at 12pt in a few places),
`warm` (#D97706),
`success600`.

Colors that fail for all text:
`slate300` (~1.6:1, used for dashed borders + disabled stars —
decorative, OK),
`sky400` (~2.0:1, used as scheduler dot color — decorative).

Known gap: `primary` as link color at 12pt in "Add a starter →" /
"Feed at 8:14 PM →" misses AA. Fixing this means either bumping the
primary toward a deeper terracotta (visual identity change — needs
designer input) or moving those small-text uses to `primaryDeep`.
Documented; not auto-fixed. `warm` at 11.5–12pt in the Active Bake
"Live activity" subtitle has the same shape; same call.

Known gaps deliberately left for later:

- The Sidebar's "LIVE" badge uses 9pt text — fails AA even with
  `success700` (3.2:1 at that size). The minimum body text size in
  the app is 11pt; bringing the badge up costs design churn.
- Recipe-detail tables and the diagnostic context bar still rely
  heavily on `slate500` body — passes by a hair (4.7:1). A future
  Dark Mode pass (Stage 14+ polish) is the place to recompute these
  semantically.

## Phase B — 1.x quality & polish (post-launch)

The "now that we shipped, make it feel like an app people pay for"
phase. None of these block 1.0 but each one is a noticeable upgrade.

### Stage 12 — Multi-page onboarding tour + Settings units & temp source

Replace the single-card onboarding with a 3-page tour (one-app-pitch,
how-it-works, name + notifications). Add to `SettingsScreen`:

- Units toggle (g vs oz). Threads through `CCFormat` and the recipe
  editor's "Grams" labels.
- Kitchen-temp source switcher: Manual (current) vs HomeKit (Stage 20
  delivers the actual data path; the switcher is just a stub UI for
  now).

### Stage 12 — completion notes

**Onboarding tour:** `OnboardingScreen` is now a 3-page TabView-style
flow driven by a `page` int + shared chrome:
- **Page 1 — pitch.** "One app for every bread you bake." + three
  feature rows (library / scheduler / starter).
- **Page 2 — how it works.** "Bake with the timer." + three rows
  (action-point reminders, schedule reflow, journal patterns).
- **Page 3 — name + notifications.** The original name TextField plus
  a primary-tint callout offering "Allow" reminders inline. Tapping
  Allow calls `state.requestNotificationPermission()` and morphs the
  callout to a "Reminders set up" check state. Skipping it just keeps
  the system prompt for first Scheduler-confirm. Either way, "Get
  started" closes onboarding and writes the user's name through
  `state.completeOnboarding(name:)`.
- The page dots animation honors `state.reduceMotion` (Stage 10).
- Brand + page indicator stay in the same place across pages so the
  reader's eye doesn't have to relocate. "Load demo data" stays in
  the bottom-left of every page.

**Units (grams / ounces):**

- `Units` enum lives in `Core/Formatters.swift` next to `CCFormat`.
  `shortLabel` returns "g" / "oz"; `inputLabel` returns "Grams" /
  "Ounces" for headers; `gramsPerOunce = 28.349523125` is the
  conversion constant.
- `CCFormat` gained:
  - `weight(grams:units:) -> String` — "500 g" or "17.6 oz".
  - `weightValue(grams:units:) -> String` — value only, used in
    sites with a separate unit label.
  - `grams(from:units:) -> Double` — editor input parser, converts
    user-typed numbers back to canonical grams.
- `PersistedState.units: Units = .grams` (default = grams, so old
  saves grandfather without surprise). `AppState.units` mirrors it,
  with `setUnits(_:)` as the mutator.
- All ingredient weights remain canonical grams on disk; only the
  display + editor input layer flips.
- Call sites updated:
  - `RecipeEditorScreen.IngredientRow` — TextField binds through a
    `displayWeight: Binding<Double>` projection that converts on
    read/write so the user types in their chosen unit but the model
    stores grams.
  - Editor section header shows "Ingredients (grams)" / "(ounces)"
    so the unit is unambiguous before the row labels appear.
  - `RecipeDetailScreen` — Dough wt hero, ingredient table column,
    and the scale-slider total all run through `CCFormat.weight(...)`.
  - `ActiveBakeScreen` recipe header "Total weight" stat.
  - `LibraryScreen.RecipeCard` — picks up `units` as a parameter,
    formats the dough-weight stat block accordingly.

**Kitchen-temp source switcher (stub):**

- `KitchenTempSource` enum (`.manual`, `.homeKit`).
- `AppState.kitchenTempSource` + `setKitchenTempSource(_:)`, persisted
  via `PersistedState.kitchenTempSource`.
- New `kitchenCard` section in `SettingsScreen` with two
  segmented-Picker rows: weight units, then kitchen temp source. Both
  copy lines explicitly say "HomeKit pairing arrives in a future
  update" / "Slide the Scheduler's kitchen temperature manually each
  bake" — keeps the user from expecting magic.
- The Scheduler does NOT yet honor `.homeKit` — Stage 20 wires that.
  Persisting the choice means Stage 20 can flip behavior without
  another migration.

Known gaps deliberately left for later:

- The Starter screen still displays raw "(weightGrams)g" / "180g" in
  the chip + AI card (we didn't audit all weight-text in the starter
  surface). That's a Stage 13 starter-editor concern once we have a
  starter editor to thread units through.
- Active-bake fold spacing and recipe-detail preferment percentages
  show no oz path — they don't have raw weights to flip.
- Onboarding doesn't expose Units / Temp source on the way through.
  The thinking was: "fewer decisions during first-launch keeps the
  flow short", and Settings is one tap from Home. Reconsider if
  TestFlight feedback says otherwise.

### Stage 13 — Recipe editor v2

Editor scope creep deferred from Stage 4:

- **Preferments** — add / remove / edit tangzhong, yudane, levain
  build blocks. Currently read-only (and seeded recipes round-trip
  but can't be re-created in the UI).
- **Twin-scald** toggle.
- **Recipe photo picker** — replace `Recipe.photo` (currently the
  bundled asset name) via `.photoPicker`. Reuse Stage 1 plumbing.

### Stage 13 — completion notes

All three scope items landed in `RecipeEditorScreen`. Threading them
through the save path also fixed a latent bug where preferment flour
was missing from the baker's-percent denominator.

**Preferments** — new collapsible `prefermentsSection`:

- One `DisclosureGroup` per `Preferment` (`PrefermentRow`). Collapsed
  shows the name + technique + flour %; expanded reveals name /
  technique / prep / flour% / sub-ingredient list with the same
  unit-aware `IngredientRow` the main dough uses (so oz mode applies
  inside preferments too).
- "Add preferment" is a `Menu` with a fixed catalogue of templates —
  `PrefermentTemplate.levain / .yudane / .tangzhong / .biga / .poolish`.
  Each ships a sensible default name, technique, prep text, flour %,
  and seed sub-ingredients tagged with `section = id`. Templates
  already present in the recipe are listed as disabled checkmarks so
  the user can see they exist.
- Deleting a preferment scrubs any `Stage.scaldRef` pointing at it so
  there are no dangling references after the row goes away.
- Custom preferments (free-form ids) are intentionally out of scope —
  `Stage.scaldRef` and `Ingredient.section` reference these ids by
  string, and a freeform id field invites collisions and typos.

**Twin-scald toggle:** one `Toggle("Twin scald (yudane + tangzhong)",
isOn: $draft.twinScald)` row in the metadata section. The recipe-
detail surfaces (Stage 4) already know how to read `twinScald` — they
just had no editor entry point before.

**Recipe photo:**

- New `photoSection` at the very top of the form: a 110×80 preview
  (`BreadPhoto`, which resolves disk → bundled asset → gradient
  fallback per Stage 1), a "Choose photo" / "Replace photo" button,
  and a destructive "Remove photo" button.
- The picker uses the existing `.photoPicker` modifier (Stage 1).
  Saved photos persist via `state.persistence.savePhoto` and the
  returned filename becomes `draft.photo`. The Stage 7 photo-error
  surface (`state.photoErrorMessage`) catches save failures.

**Save path tightened:**

- Blank-name preferment sub-ingredients get filtered out alongside
  main-dough blanks.
- Every main-dough ingredient is now tagged `section = "main"` on
  save (seed recipes did this; user-created ones now match).
- Every preferment sub-ingredient is force-re-tagged with its
  preferment's id so a stage / detail view can group them by section
  even if the user dragged a row in from somewhere else.
- `combinedFlour` (main + preferment flour) is the denominator for
  baker's % across every ingredient row, AND for `Preferment.flourPct`.
  Previously the editor only summed main-dough flour, so a recipe
  with a yudane on save reported wrong percentages.
- `totalDoughGrams` sums across main + every preferment.
- `flourError` and `weightsError` validators now look at preferment
  ingredients too, so an all-preferment recipe (rare but legal) can
  validate, and a negative sub-ingredient weight is caught.

Known gaps deliberately left for later:

- Recipe photo input is library/camera only; we don't yet pull the
  hero from a linked URL's OG-image when the user pastes a URL.
  That's Stage 17 (JSON-LD import) territory.
- No drag-to-reorder preferments — the order they're added is the
  order they appear. Reorder is a small editor polish if it becomes
  a complaint, but the only reader of this order is the Recipe Detail
  ingredients table.
- Sub-ingredient list inside a preferment uses an `.onDelete` swipe
  but doesn't expose `EditButton` — adding `.onMove` would mean a
  per-preferment edit-mode toggle, which is more chrome than the
  three-row average case warrants.

### Stage 14 — Haptics + sound polish

- Light haptic on "Mark fold N done".
- Medium haptic on stage advance / skip.
- Success haptic + sound on `completeBake`.
- Selection haptic on TagPill / chip taps.
- Animation pass: tighten spring damping on the screen-switch
  transition, add micro-fade on Active Bake card content changes.

Wraps a polish pass over the whole app — the difference between
"works" and "feels designed".

### Stage 14 — completion notes

**Haptics** — new `Crumbcoach/Shared/Haptics.swift` is the single
choke point. Four static methods cover every surface that wants
feedback:

- `Haptics.tick()` — light `UIImpactFeedbackGenerator(.light)`. Wired
  into `AppState.markFold` (the inner method that drives both
  `incrementFold` and direct chip taps). Only fires when the fold
  count actually changes — tapping the already-done fold count
  doesn't buzz.
- `Haptics.advance()` — medium impact. `advanceStage()` and
  `skipStage()` both fire it before delegating to `moveStage`, so the
  outer-method intent is the haptic source, not the internal state
  machine.
- `Haptics.success()` — `UINotificationFeedbackGenerator` success.
  Fires once inside `completeBake(rating:note:)` after the journal
  entry persists.
- `Haptics.select()` — `UISelectionFeedbackGenerator`. Wired into
  every `TagPill` tap (Library filters, Scheduler day/time, Diagnose
  context chips, etc.) by routing through the button's action.

Haptics deliberately don't go through `AppState.reduceMotion` — the
system has its own accessibility setting for haptics (Settings →
Accessibility → Touch → Vibration), and the generators respect it
automatically. The system also silences haptics in Low Power Mode.

**Sound (deferred):** the spec mentioned "Success haptic + sound on
completeBake". A reliable cross-version sound needs a bundled audio
asset, and v1's curated copy doesn't have one yet. The success
haptic carries the moment; sound is a known gap.

**Animation polish:**

- `AppState.goTo(_:)` now uses
  `.spring(response: 0.28, dampingFraction: 0.86)` instead of
  `.easeOut(duration: 0.18)`. Snappier into the new screen with
  enough damping to avoid overshoot. Reduce-motion still gates the
  whole `withAnimation` — that path stays cut.
- `ActiveBakeScreen.currentStageCard` — the title/note stack gets
  `.id(bake.currentStageIndex)` plus `.transition(.opacity)` +
  `.animation(.easeInOut(0.18), value: currentStageIndex)`, so the
  stage swap crossfades the title rather than popping. The fold-
  count ring gets a separate `.easeOut(0.25)` animation keyed off
  `foldsDone` so the ring sweep doesn't jump. Both gates are
  `nil`-when-`state.reduceMotion`.

Known gaps deliberately left for later:

- No bundled success sound (see above). Adding one means picking a
  ~80ms WAV and dropping it into Resources; trivially small change,
  just unfinished design work.
- Onboarding page-dot animation still uses `easeOut(0.18)` — kept
  for now because the dots are 6pt circles and the curve hardly
  matters at that scale.
- `ccPrimary` / `ccSecondary` buttons don't fire haptics on their
  own. The few places where a haptic would help (Schedule confirm,
  Settings reset confirmations) currently rely on the chip/Toggle/
  action path. Worth a future polish if user feedback asks.

### Stage 15 — iCloud sync

Replace the JSON-on-disk store with `NSPersistentCloudKitContainer`.

Considerations:
- SwiftData migration is a larger rewrite (every value-type model
  becomes a `@Model` class with `@Relationship`).
- `NSPersistentCloudKitContainer` is the lower-risk path — Core Data
  underneath but minimal API surface change.
- Either way, requires the iCloud capability in `project.yml`:
  ```yaml
  entitlements:
    com.apple.developer.icloud-services:
      - CloudKit
    com.apple.developer.icloud-container-identifiers:
      - iCloud.com.crumbcoach.app
  ```
- Photo blobs need a CloudKit asset path, not the local
  `Application Support/photos/` directory.

### Stage 15 — completion notes

**Scope decision:** the plan's `NSPersistentCloudKitContainer` path is
a multi-day model-layer rewrite (every Codable struct → `@Model`
class). For Phase B polish, we shipped a pragmatic alternative —
**iCloud Drive sync of the existing JSON state file** via the
ubiquity Documents container. This gives users cross-device sync
without touching the persistence schema. Conflict resolution is
last-write-wins on the JSON blob; per-record merge is a Phase C
upgrade when iPhone / Watch targets (Stages 21, 28) justify the
CloudKit container effort.

**Implementation:**

- `Crumbcoach/Shared/CloudSyncManager.swift` — `@MainActor`
  `ObservableObject` singleton.
  - `isAvailable: Bool` — checks `FileManager.default.ubiquityIdentityToken`.
  - `setEnabled(_:)` — mirror of the Settings toggle. When disabling,
    leaves the cloud copy intact (Settings can re-enable without
    losing it).
  - `push(localStateURL:) async` — copies the local `state.json` up
    to `<ubiquity>/Documents/state.json`. Status flips to `.syncing`
    while the off-main copy runs, then `.syncedAt(date)` or `.failed`.
  - `pullIfNewer(into:) async -> Bool` — reads cloud mtime, compares
    against local, copies down only if cloud is strictly newer (with
    a 0.5s slop for filesystem precision). Returns true so callers
    can reload state.
  - `SyncStatus` enum drives the Settings status line:
    `.disabled / .unavailable / .ready / .syncing / .syncedAt / .failed`.
- `PersistedState.cloudSyncEnabled: Bool = false` — opt-in default.
  Existing saves grandfather to off; the user has to flip the toggle.
- `AppState`:
  - `cloudSyncEnabled` mirrors the persisted preference.
  - `setCloudSyncEnabled(_:)` toggles and kicks an immediate
    `syncWithCloud()` on enable so a freshly-paired iPad pulls
    whatever the user's other devices have written.
  - `syncWithCloud()` does pull-then-push; if the pull replaces
    local state, `reload(from:)` walks every observable field so
    the live UI matches the new file without re-instantiating
    AppState (which would drop notification auth, photo error, etc).
  - `saveSoon` / `saveNow` push to cloud after every local write
    (when enabled). The push runs in a detached Task so it can't
    block the save loop.
  - `init` bounces `CloudSyncManager.shared.setEnabled(initial)`
    onto MainActor so the manager's internal flag matches the
    persisted preference from launch onward.
- `CrumbcoachApp.scenePhase == .active` fires a `syncWithCloud()`
  task alongside the existing notification auth refresh. Cheap
  no-op when disabled or iCloud is signed out.
- `SettingsScreen.cloudSyncCard` — new section with toggle (disabled
  when `cloudSync.isAvailable == false`), "Sync now" button driving
  `state.syncWithCloud()`, and a live status line bound to
  `cloudSync.status` via `@ObservedObject`.
- `project.yml` gains an `entitlements:` block for the bundle id —
  `iCloud.com.crumbcoach.app` for documents + ubiquity. A team
  building this needs to enable iCloud (Documents) on the App ID in
  Apple Developer + provision the container. `CloudSyncManager`
  gracefully no-ops at runtime if the container isn't reachable, so
  builds without provisioning still run.

**Known gaps deliberately left for later:**

- Photos aren't synced. Each device keeps its own
  `<App Support>/Crumbcoach/photos/` directory; the JSON references
  filenames that resolve to gradient placeholders on the other iPad.
  Mirroring photos as CKAssets or as additional files in the same
  ubiquity container is the obvious extension — natural Stage 18
  (share & export) companion or Stage 21 (Watch) work.
- No CloudKit subscriptions / push notifications. Cross-device
  propagation only happens on the receiving device's next foreground
  (or "Sync now" tap). Real-time sync between two iPads open in the
  same kitchen is Phase C territory.
- Last-write-wins on the JSON blob: if both devices edit the same
  recipe before either syncs, the later push wins outright. For a
  single-baker single-iPad app the conflict surface is small; the
  status line ("Last synced HH:MM") lets the user spot drift.
- The plan's full `NSPersistentCloudKitContainer` migration remains
  the long-term answer. The ubiquity-Documents path is a stepping
  stone; when Stage 21 / 28 adds an iPhone or Watch target, the
  team should revisit the model-layer rewrite.

Post-Stage 15 follow-ups landed (post-review):

- `NSFileCoordinator` now wraps both push and pull. Apple requires
  coordinated access to ubiquity URLs — without it, the iCloud
  daemon can return stale bytes mid-sync, and concurrent writes can
  corrupt the file. `coordinate(writingItemAt: .forReplacing)` for
  push, `coordinate(readingItemAt:)` for pull. Coordination errors
  log + flip `status = .failed(…)`.
- In-app push/pull serialization via `pushTask` and `pullTask`
  chains. Each new call awaits the prior in-flight task before
  running, so two saves spawned 0.5s apart can't race their own
  `removeItem` + `copyItem` on the cloud URL. NSFileCoordinator
  handles cross-process; the chain handles in-app ordering.
- iCloud container identifier moved to `iCloud.com.monty.crumbcoach.app`
  to match the personal-team signing prefix (see preamble). Fork
  to a different team changes this alongside the bundle ids.

### Stage 16 — Live Activity

`ActivityKit` widget showing the active bake's current stage, fold
count, and time-to-next-action. The static preview in
`ActiveBakeScreen.liveActivityCard` defines the visual target.

Includes a Dynamic Island compact variant for iPhones (still relevant
even though the main app is iPad-only, since notifications can target
the user's phone if they ever bring CrumbCoach there).

### Stage 16 — completion notes

The Live Activity landed with a full widget-extension target. Lock
Screen + StandBy view on iPad, Dynamic Island compact + expanded for
when an iPhone visitor lands.

**Shared contract:** `Crumbcoach/Shared/ActiveBakeAttributes.swift`
defines the `ActivityAttributes` type plus its `ContentState`. The
file is listed in both targets' sources in `project.yml`, so the
main app and the widget extension agree on the wire shape without a
framework / package boundary. Static fields (recipe title, started-
at) freeze at start; dynamic fields (stage name, folds, minutes-to-
next-action, bake-out-at, isComplete) re-render on every update.

**Widget extension target** (`CrumbcoachWidgets/`):

- `CrumbcoachWidgetsBundle.swift` — `@main WidgetBundle` that vends
  `ActiveBakeLiveActivity`. Stage 19 (Home Screen / Lock Screen
  complications) will add neighbours here.
- `ActiveBakeLiveActivity.swift` — `Widget` with an
  `ActivityConfiguration` shape:
  - Lock-screen view mirrors the in-app `liveActivityCard` preview:
    brand chip + recipe title + stage subtitle on the left, time-to-
    next-action + "Bake out" / "Ready to log" label on the right.
  - Dynamic Island regions: compact leading icon, compact trailing
    minutes-to-next, minimal icon, and a four-region expanded view
    with leading title/stage, trailing time, and a fold-progress
    capsule strip across the bottom.
  - Copy helpers (`subtitleText`, `timeToNextLabel`,
    `compactTrailing`) handle the "complete" branch ("Ready to log",
    "Done") so the widget doesn't need any conditional rendering on
    the main app's side.
- `project.yml` widget entries: `type: app-extension`, bundle id
  `com.crumbcoach.app.widgets`, sources include the shared
  attributes file, Info.plist carries the
  `com.apple.widgetkit-extension` extension point.
- Main app target embeds the widget via `dependencies: [{ target:
  CrumbcoachWidgets, embed: true }]` and gains
  `NSSupportsLiveActivities: true` in Info.plist (required for
  `Activity<>.request()` to succeed).

**Manager:** `Crumbcoach/Shared/LiveActivityManager.swift` is the
main-app singleton.

- `start(recipeTitle:startedAt:state:)` — gated on
  `ActivityAuthorizationInfo().areActivitiesEnabled` so opted-out
  users see no broken state. Idempotent: re-call ends the previous
  activity first.
- `update(_:)` — pushes a fresh `ContentState` to the running
  activity. Silently dropped when no activity is in flight.
- `end(immediate:)` — `.default` dismissal lets the lock-screen
  trailing window keep the final state around (~4h) so the user can
  glance at "Ready to log" before it fades. `.immediate` is used by
  reset paths.

**AppState wiring:**

- `startBake` — calls `LiveActivityManager.shared.start(...)` with
  the freshly-built bake's `ContentState`.
- `markFold` — pushes an update only when `foldsDone` actually
  changed (same gate as the haptic).
- `moveStage` (the shared advance / skip body) — pushes an update
  after the move completes so the stage name + minutes-to-next-
  action change ride out together.
- `completeBake` — `.default` end so the "Ready to log" state
  lingers briefly.
- `loadDemoData` / `startOver` — `.immediate` end so no stale
  activity hangs around after a reset.
- Two new private helpers: `pushLiveActivityUpdate()` and
  `liveActivityState(for:recipe:)`. The state-shaper prefers the
  Stage-8 rebalanced schedule for `minutesToNextAction` and falls
  back to `bake.bakeOutAt` when there's no schedule.

**Known gaps deliberately left for later:**

- No push-via-server updates — every push happens from the main app
  while it's foregrounded or briefly backgrounded. Cron-style
  countdown ticks (the time-to-next number updating once a minute)
  would need a server push or an in-app timer that wakes the
  activity on a schedule.
- The Dynamic Island center region is intentionally empty — on the
  iPad-only target there's nothing to render there and iPhone
  expanded variant prefers leading/trailing/bottom. Easy to add a
  ring progress later when a clearer visual brief emerges.
- The widget UI uses system fonts / colors (no Geist / Theme) — the
  widget extension can't read the main app's bundle resources at
  render time. Pulling Theme tokens into the widget would mean
  shipping a small shared package; Stage 14 already covered the
  in-app polish so this stays minimal.
- "Live Activity disabled by user" doesn't surface anywhere in the
  app. Worth a Settings tile once we have telemetry to show how
  often users disable it.

Post-Stage 16 follow-ups landed (post-review):

- `AppState.reload(from:)` (Stage 15's cloud-pull hand-off) now
  reconciles the Live Activity with the swapped `activeBake`. The
  prior code blindly replaced `activeBake`, leaving the lock-screen
  widget pointing at a bake that no longer existed in app state.
  Now: if the bake id changed (cleared, or a different bake from
  another device), end the existing activity and start fresh; if
  the same id's internal state advanced, push an update. Stops the
  cross-device "ghost bake" scenario the review caught.

### Stage 17 — Recipe URL import (JSON-LD)

The Stage 4 "Paste URL" button stores the URL string; Stage 17 parses
the page. Most major bread sites (King Arthur, The Perfect Loaf,
Foodgeek, Maurizio Leo) publish `Recipe` schema in JSON-LD. Extract
formula only (ingredients + weights + stages) — don't copy prose.

Spec §6.1. On-device parsing via `URLSession` + light HTML/JSON-LD
extraction; no server required.

### Stage 17 — completion notes

On-device JSON-LD importer + an "Import recipe" affordance on the
editor's URL row. Network round-trip stays in-app; no backend.

**Importer** (`Crumbcoach/Shared/RecipeImporter.swift`):

- `RecipeImporter.import(from:session:) async throws -> ImportedRecipe`
  is the public entry point. Returns a draft `Recipe` + a list of
  user-visible warnings about lossy parts.
- Fetch uses `URLSession.shared` with a 20s timeout and a custom
  `User-Agent` so sites that 403 the default Swift agent (some
  Cloudflare-fronted bread blogs) still respond.
- HTTP errors map to `RecipeImporterError.fetchFailed(message)`;
  non-HTML responses to `.notHTML`. The error type conforms to
  `LocalizedError` so the editor can surface `.errorDescription`
  inline.
- JSON-LD extraction uses an `NSRegularExpression` over the raw
  HTML to find every `<script type="application/ld+json">…</script>`
  block. Decoded values are flattened from three common shapes
  (single object, array, or `@graph` wrapper) into a list of
  dictionaries.
- The first dict with `@type == "Recipe"` (case-insensitive, also
  accepts an array of types) wins. `noRecipeSchema` is the error
  when none is found.
- Field mapping:
  - `name` → title (defaults to `"Imported recipe"` with a warning
    if missing).
  - `recipeIngredient` (or older `ingredients`) → ingredient list
    via `parseGramsAndName`, which handles `g / kg / oz` (with
    plural / "kilograms" / "ounce" variants) and decimal commas.
    Unparseable strings become rows with `weightGrams = 0` and add
    a warning per row.
  - `categoryGuess(for:)` picks an `IngredientCategory` from name
    keywords (salt / leaven / liquid / sweet / fat / inclusion /
    flour fallback). Wrong guesses are cheap — the editor row's
    Picker corrects them.
  - `recipeInstructions` accepts a string, an array of strings,
    `HowToStep` dicts with `text`, or an `itemListElement` nesting.
    Flattened into one ordered list of strings.
  - `stageKindGuess(for:)` keyword-maps each instruction to a
    `StageKind`. The full instruction text becomes the stage note;
    `durationMin` stays at 0 — we don't make up ferment times.
- Returned draft carries `source = .linked(url:sourceName:sourceLogo:)`
  with the source name derived from `url.host` (stripping `www.`).
  `hydrationPct`/`saltPct`/`leavenPct` are left at 0 — the editor's
  save path recomputes them against the imported ingredients.

**Editor wiring** (`RecipeEditorScreen.swift`):

- New state: `isImporting`, `importWarnings`, `importError`,
  `showOverwriteConfirm`.
- The metadata section's source-URL row gains an "Import recipe"
  button (with a spinner while in-flight). Below it, an inline
  error line for `.fetchFailed`/`.noJSONLD`/etc., and a warnings
  block (yellow triangle icons) for each parse-warning so the user
  sees exactly what they need to clean up.
- "Editor has user content" gate: typing a title or adding flour
  beyond the four-row sourdough skeleton flips an overwrite
  confirmation before the fetch. Fresh "I just pasted a URL"
  imports skip the confirmation.
- `applyImport(_:)` replaces title / ingredients / preferments /
  stages / source / twin-scald from the imported draft; the user's
  `editingRecipeId` and `editingRecipeId`-bound buttons stay put.
- The existing save path's combined-flour math (Stage 13)
  recomputes percentages on save, so imported recipes round-trip
  cleanly without an extra import-time pass.

**Known gaps deliberately left for later:**

- Photos aren't downloaded. The schema's `image` field is ignored —
  the editor stays on the bundled fallback, and the user can pick
  a photo via the Stage 13 photo picker.
- We don't honor the `nutrition` block. Bakers don't care; the
  field exists in the schema but parsing it would add noise without
  signal.
- No preferment auto-detection. If a recipe lists a separate "for
  the levain" section, those ingredients land in the main list and
  the user has to move them into a preferment block. A common
  schema variant uses `recipeIngredient` groups with section
  headings; supporting that cleanly is a future polish.
- Cup / tbsp / tsp parsing is intentionally out of scope. Different
  flours have different cup→gram ratios, and our v1 stance is "if
  the recipe doesn't publish grams, the import is incomplete." Each
  such row becomes a warning the user resolves manually.
- We don't follow JSON-LD `@id` references across blocks. Rare in
  the wild for Recipe schemas; the failure mode is the same as
  `noRecipeSchema`.
- The custom `User-Agent` string is best-effort. Sites that gate on
  more sophisticated bot detection (rare for recipe blogs) may
  still 403; the user sees the `.fetchFailed(HTTP 403)` message.

Post-Stage 17 follow-ups landed (post King-Arthur-import test):

- Parenthesized-weight parsing. King Arthur, Foodgeek, Maurizio Leo,
  and most US bread blogs format ingredients as
  `"1 1/4 cups (284g) lukewarm water"` — volume primary, grams as
  the metric annotation. The original parser required the string to
  *start* with a number+unit, so all seven ingredients on a typical
  KA recipe import landed with `weightGrams = 0` and a "couldn't
  parse" warning. New layered parser:
  1. **`parseLeadingWeight`** — the existing "500 g flour" path
     (handles plain metric recipes).
  2. **`parseParenthesizedWeight`** — finds the first `(284g)` /
     `(0.5 kg)` / `(17.6 oz)` group anywhere in the string.
  3. Falls through with a warning if neither matches (recipes that
     publish only US-customary units).
- Ingredient name cleanup (`cleanIngredientName`). After
  parenthesized extraction, strips all `(…)` blocks, the leading
  volume quantity (`"1 1/4 cups"`, `"2 tablespoons"`), and an
  optional `"to N units"` range tail (`"to 1 1/2 cups"`). Trims
  footnote markers, doubled spaces, and trailing punctuation. So
  `"1 1/4 cups (284g)  to 1 1/2 cups (340g) lukewarm water*"` lands
  as `"lukewarm water"` rather than the full source string.
- `parseIngredients` now produces a `weightGrams > 0` row for every
  ingredient that has gram annotations in parens — six of seven
  rows on the King Arthur Classic Sourdough recipe parse cleanly
  on import (only `"2 1/4 teaspoons instant yeast"` falls through,
  since it carries no gram value at all).
- Editor auto-import on first appear (`.task`). The share-extension
  and Library "Paste URL" entry points seed the editor's URL field
  but the user previously had to tap "Import recipe" manually.
  Saving without the explicit tap persisted the `blank()` sourdough
  skeleton with just the URL attached — the "URL right but
  everything else wrong" trap. Now `runImport()` fires once on
  appear when `editingRecipeId == nil` and the URL field is
  pre-seeded; editing an existing linked recipe still requires an
  explicit Import tap so the user can't silently overwrite their
  data.

### Stage 17.5 — Import gap-filling (lookup table + Foundation Models)

**Sketch — not started.** Slots between Stage 17 (regex JSON-LD)
and Stage 18 (share/export) as the second-pass import quality lift.
The regex import handles "ingredient has grams in the source"; this
stage handles "ingredient has no grams in the source" + "stage has
no duration in the source" — the two warning categories left over
after the post-King-Arthur fixes.

**Two-layer approach:**

#### 17.5a — Static volume-to-grams lookup

A small constant table for the ~30 most common bread ingredients,
mapping `(name keyword, US volume unit) → grams`. Deterministic, no
device-version gate, no inference cost. Handles the long tail of
"2 1/4 teaspoons instant yeast" style rows that fall through Stage
17's parser today.

Sketch:

```swift
// Crumbcoach/Shared/IngredientWeightTable.swift
enum IngredientWeightTable {
    /// (lowercased keyword, unit) → grams per unit.
    /// Source: King Arthur ingredient weights chart + standard
    /// baker references; comment each entry with provenance.
    private static let table: [(String, Unit, Double)] = [
        ("instant yeast",       .teaspoon,   3.1),
        ("active dry yeast",    .teaspoon,   3.1),
        ("table salt",          .teaspoon,   6.0),
        ("kosher salt",         .teaspoon,   4.8),  // Diamond
        ("bread flour",         .cup,      120.0),
        ("all-purpose flour",   .cup,      120.0),
        ("water",               .cup,      237.0),
        ("milk",                .cup,      227.0),
        ("granulated sugar",    .cup,      198.0),
        ("brown sugar",         .cup,      213.0),
        ("honey",               .tablespoon, 21.0),
        ("butter",              .tablespoon, 14.2),
        // … ~30 rows total covering top-of-pareto
    ]

    enum Unit { case teaspoon, tablespoon, cup }

    /// Returns nil when the (name keyword × unit) pair isn't in the
    /// table. Callers fall back to LLM (17.5b) or leave the row at
    /// 0g with a warning.
    static func estimate(name: String, quantity: Double, unit: Unit) -> Double?
}
```

`RecipeImporter.parseIngredients` calls this after both regex
attempts fail; on a hit, the row gets `weightGrams` populated +
warnings note "estimated from table" so the user knows to verify.

#### 17.5b — Foundation Models fallback

For rows the table misses, use Apple's on-device LLM via the
`FoundationModels` framework (iOS 18.1+, Apple Intelligence-eligible
devices: iPhone 15 Pro+, M1+ iPad). Same for stage duration
estimates pulled from instruction text.

Sketch:

```swift
import FoundationModels   // iOS 18.1+ only

@available(iOS 18.1, *)
enum AIRecipeAssist {
    @Generable
    struct IngredientEstimate {
        @Guide(description: "Weight in grams. 0 if unsure.")
        let grams: Double
        @Guide(description: "Confidence 0..1.")
        let confidence: Double
    }

    @Generable
    struct StageEstimate {
        @Guide(description: "Duration in minutes. 0 if unsure.")
        let minutes: Int
        @Guide(description: "Confidence 0..1.")
        let confidence: Double
    }

    static var isAvailable: Bool {
        if #available(iOS 18.1, *) {
            return SystemLanguageModel.default.availability == .available
        }
        return false
    }

    @available(iOS 18.1, *)
    static func estimateGrams(for ingredients: [String]) async throws -> [Double?] {
        let session = LanguageModelSession(instructions: """
        You estimate ingredient weights for bread recipes. The user
        sends one ingredient string at a time. Return grams + a
        confidence. If you cannot estimate confidently from standard
        US recipe conventions, return grams = 0 and confidence < 0.5.
        Never guess wildly — bakers will weigh by the number you
        return.
        """)
        return try await withThrowingTaskGroup(of: (Int, Double?).self) { group in
            for (i, line) in ingredients.enumerated() {
                group.addTask {
                    let r = try await session.respond(
                        to: line,
                        generating: IngredientEstimate.self
                    )
                    // Reject low-confidence + sanity-check against
                    // the lookup table when possible.
                    return (i, r.content.confidence >= 0.6 ? r.content.grams : nil)
                }
            }
            var out = Array<Double?>(repeating: nil, count: ingredients.count)
            for try await (i, g) in group { out[i] = g }
            return out
        }
    }

    @available(iOS 18.1, *)
    static func estimateDurations(for instructions: [String]) async throws -> [Int?] {
        // Symmetric to estimateGrams: prompts the model with a
        // single stage instruction, returns minutes when confident.
        // Captures "Let rest 4 hours" → 240, "Bake until golden
        // brown" → ~30 (a default), "Overnight" → 720.
    }
}
```

#### Integration points

- `RecipeImporter.import(from:)` becomes async-capable (already is)
  and grows an optional post-processing pass:
  1. Regex extraction (today's Stage 17 path) — wins for most rows.
  2. Table lookup for unparsed rows (17.5a).
  3. Foundation Models for everything still at 0g/0min when
     `AIRecipeAssist.isAvailable && state.aiAssistEnabled`.
- Warnings shape: each row gets a source tag — `.parsed`, `.table`,
  `.aiAssisted`, or `.unfilled` — and the editor's import-notes
  block surfaces "AI-assisted N rows, please verify" so the user
  treats those rows with extra scrutiny.
- Settings adds a "Use Apple Intelligence to fill recipe gaps"
  toggle. Default ON when available (matches the opt-out posture
  of Stage 9 telemetry), with copy explaining "Runs on this iPad
  only — no upload."

#### Risks + guard rails

- **Hallucinated weights.** Mitigation: sanity-check LLM output
  against the lookup table when there's any keyword overlap; reject
  estimates outside ±50% of the table value.
- **Latency.** ~1–2s per inference on M1; batched task group
  brings a 7-ingredient recipe down to ~3s overall. Acceptable for
  a one-shot import; not on the hot path.
- **Device gating.** iOS 17.0 deployment target stays — runtime
  `#available(iOS 18.1, *)` checks hide the LLM path on older
  devices and iPads without Apple Intelligence. Table layer (17.5a)
  works everywhere.
- **API drift.** `FoundationModels` is iOS 26+ public API; surface
  area may evolve. Worth shipping behind a feature flag and
  isolating in `AIRecipeAssist.swift` so a future API change is one
  file to refactor.
- **Privacy posture preserved.** Both layers stay on-device — no
  upload, no cloud round-trip. Same story as Stage 9 telemetry.

#### Effort estimate

- 17.5a (lookup table): ~2 hours including data entry, integration,
  and a couple of unit tests.
- 17.5b (Foundation Models): ~4–6 hours including the assist
  module, Settings toggle, and editor warning-tag surface.
- Total: under a day of focused work.

#### When to do it

- If 17.5a alone closes most "couldn't parse" warnings on real
  recipes the user actually imports, 17.5b may not be worth the
  iOS 18.1+ availability gate + the hallucination risk.
- Sequence: ship 17.5a first; watch the warnings rate; pull
  17.5b in only if 17.5a leaves real gaps.

### Stage 17.5a — completion notes

Two improvements bundled here — the volume-to-grams table AND
instruction-time parsing. Together they close most of the "fill it
in manually" gaps that the JSON-LD importer left behind.

**Volume-to-grams lookup.** `Crumbcoach/Shared/IngredientWeightTable.swift`
ships ~35 entries covering flours, liquids, salts, leavens,
sweeteners, fats, and a few common misc rows (cocoa powder, dry
milk). Each entry maps `(keyword, unit) → grams per unit`. Numbers
sourced from King Arthur's published ingredient-weight chart with
brand-specific notes where they diverge (kosher salt: Diamond
Crystal 4.8g/tsp vs Morton 6.0g/tsp — table ships Diamond as the
US default, comment captures the divergence).

Wired into `RecipeImporter.parseIngredients` as the third pattern
after the Stage 17 regex paths:

1. `parseLeadingWeight` — "500 g flour" (Stage 17)
2. `parseParenthesizedWeight` — "1 1/4 cups (284g) water" (Stage 17)
3. `parseFromTable` — "2 1/4 teaspoons instant yeast" → 7g (Stage 17.5a, NEW)

`parseFromTable` matches a leading `(quantity)(unit)` group via
regex, then converts:

- Quantity parser handles whole numbers, decimals, simple fractions
  (`1/2`), and mixed numbers (`2 1/4`) — the four numeric forms
  recipes actually publish.
- Volume-unit mapper folds `cup / cups / tablespoon / tbsp / tbs /
  teaspoon / tsp` (with optional trailing period) into the table's
  three-case `Unit` enum.
- Keyword match is longest-first so `"all-purpose flour"` wins
  over plain `"flour"`. A catch-all `"flour"` row at 120g/cup
  handles unrecognized varietals so the row still gets a weight.

Warnings shape changed: table-sourced rows surface as
`"Estimated Xg for "2 1/4 teaspoons instant yeast" using the
standard weight for instant yeast — verify before baking."` so
the user sees exactly which rows are estimates and what the table
matched against.

**Stage duration extraction.** Real-world test against King Arthur
exposed a parallel gap: even when JSON-LD instructions contain
explicit times ("Bake for 20 minutes", "Let rise for 60 to 90
minutes"), the importer was emitting every stage at `0 min` because
duration parsing didn't exist. New `parseDurationMinutes(from:)`
tries three regex patterns in priority order:

1. **Compound** — `"1 hour 30 minutes"` → 90.
2. **Range** — `"60 to 90 minutes"` → 60 (lower bound; bakers want
   the timer to fire on the early end so they can check). Hyphen,
   en-dash, em-dash, and `"to"` all count as range separators.
3. **Single** — `"20 minutes"`, `"1.5 hours"`, `"1 hr"` → as-is.

Plus a special case: `"overnight"` → 480 min (8h, conservative).
Returns nil for instructions like `"Bake until golden brown"` —
no number to anchor on, the user fills in.

Warnings differentiate three cases now:
- Zero stages parsed: "No instructions were detected — add stages
  by hand."
- All stages got 0 min: "Stage durations weren't recognized in
  the source — fill them in."
- Partial: "3 of 5 stages had no explicit duration — fill those
  in." (so the user knows which fraction needs attention)

**Post-Sally's-Brioche follow-ups landed:**

- **"and" between whole and fraction.** Sally's Baking Addiction
  publishes `"1 and 1/2 teaspoons salt"` — the quantity parser
  silently dropped these because it only accepted whitespace
  between the whole and the fraction. Both the
  `leadingQuantityUnitRegex` and the inline `parseQuantity` now
  accept either form, and `parseQuantity` normalizes `and` to a
  space + decimal comma to period.
- **Unicode vulgar fractions** (`½`, `¼`, `¾`, `⅓`, `⅔`, `⅛`,
  `⅜`, `⅝`, `⅞`) get normalized to their ASCII equivalents in
  `parseQuantity` so older recipe templates using typographic
  fractions parse the same as plain text.
- **Parenthesized grams with extra content.** Sally's publishes
  `"1/2 cup (113g; 8 Tbsp) unsalted butter"` — the parens-weight
  regex required `\s*\)` immediately after the unit, so the
  `; 8 Tbsp` tail broke the match and we fell back to the table
  (114g for "butter"). Loosened to `[^)]*\)` with a `\b` after
  the unit, so any non-paren content between unit and close
  paren is consumed. The authoritative source value now wins.
- **Egg counts** — `parseEggCount` added as a fourth parser path
  after the table. Matches `"3 large eggs"` / `"1 jumbo egg"` /
  `"2 medium eggs, room temperature"` with optional size word;
  uses USDA standard weights (jumbo 63g, extra-large 56g, large
  50g, medium 44g, small 38g) and defaults to "large" when the
  size isn't written (recipe convention). Egg-wash composite
  strings like `"egg wash: 1 large egg beaten with…"` start with
  a word, not a digit, so they correctly fall through to the
  "couldn't parse" warning rather than mis-extracting the egg.

Known gaps deliberately left for later:

- Long-tail ingredients (almond meal, einkorn, malt syrup, kefir,
  etc.) aren't in the table. They fall through to the
  "couldn't parse" warning today. Adding rows is mechanical when
  the user surfaces a specific case.
- The table assumes US-customary volume conventions (a US cup =
  237 ml). Recipes from UK / AU sites with imperial cups (284 ml)
  would skew low. Worth a `Locale`-based switch if European
  imports become common.
- No oz / lb mass parsing — Stage 17's regex already handles those
  cases.
- Composite ingredients (`"egg wash: …beaten with…milk"`) drop to
  the "couldn't parse" warning. Splitting these into two ingredient
  rows is a Stage 17.5b LLM job, not a regex job.
- Range *display* — duration ranges (`"60 to 90 minutes"`) collapse
  to the lower bound on import. Surfacing the range to the user is
  Stage 18.5a's model change + UI work.

### Stage 18 — Share & export

- Share a recipe via deep link (`crumbcoach://recipe/<id>`) and
  Markdown.
- Wire Journal's "Export to Markdown" to actually produce a `.md` or
  `.csv` file via the iOS share sheet.
- iOS Share Sheet integration for incoming recipes from Safari (the
  receive side of Stage 17).

### Stage 18 — completion notes

All three sub-tasks landed. Share / export now works in both
directions: recipes + journal flow out via the iOS share sheet, and
Safari pages flow in via a dedicated share extension.

**Markdown serializer** (`Crumbcoach/Shared/RecipeExporter.swift`):

- `markdown(for recipe:units:)` — title + metadata + per-preferment
  block + main-dough ingredients table + numbered stages, with a
  trailing `crumbcoach://recipe/<id>` deep link footer so any
  Markdown reader has a "tap to open" path back. Tables render in
  the user's chosen units (Stage 12).
- `markdown(forJournal entries:recipeLookup:units:)` — headline
  stats (count, average rating, average kitchen temp) + one block
  per entry (rating with star glyphs, hydration, bulk, kitchen,
  diagnosis, freeform note).
- `deepLink(for recipe:)` — canonical `crumbcoach://recipe/<id>`.
- `importDeepLink(sourceURL:)` — canonical
  `crumbcoach://import?url=<encoded>` used by the share extension.

**URL scheme + deep-link routing:**

- `project.yml` registers `CFBundleURLTypes` with the `crumbcoach`
  scheme on the main app's Info.plist.
- `AppState.pendingImportURL: String?` is the transient hand-off
  slot (mirrors Stage 1's `pendingDiagnosticPhoto`).
- `AppState.handleIncomingURL(_:)` parses two shapes:
  - `crumbcoach://recipe/<id>` → opens the detail (404s gracefully
    if the id isn't in the user's library).
  - `crumbcoach://import?url=<encoded>` → stashes the URL,
    navigates to the library so the editor can pick it up.
- `CrumbcoachApp` gains `.onOpenURL { appState.handleIncomingURL($0) }`.
- `LibraryScreen` watches `state.pendingImportURL` via `.onAppear`
  + `.onChange`, drains it into a local `editorImportSeed`, and
  presents the editor. The seed clears on `onDismiss` so a second
  share doesn't reuse stale state.
- `RecipeEditorScreen.init(state:editingRecipeId:initialSourceURL:)`
  takes the seed and pre-fills its `sourceURL` field, so the user
  just taps "Import recipe" (Stage 17) without retyping.

**Recipe share** (RecipeDetailScreen):

- New "Share" button alongside "Open original" and "Edit". On tap,
  builds the markdown + deep link via `RecipeExporter` and presents
  `ShareActivitySheet` with both items, letting the user pick the
  destination (Mail, Notes, Files, etc).

**Journal export** (JournalScreen):

- The "Export to Markdown" button is back (Stage 6 removed it as a
  stub). It calls `RecipeExporter.markdown(forJournal:…)` over the
  full journal and presents the share sheet. Empty-journal state
  (Stage 7) still hides the right rail entirely, so this button
  only appears when there's something to export.

**Shared helper:** `Crumbcoach/Shared/ShareActivitySheet.swift` is a
single `UIActivityViewController` wrapper used by RecipeDetail,
Journal, and the existing Stage 9 diagnostic share. The previous
private copy in `SettingsScreen` was deleted in favor of this
shared one.

**Share extension** (`CrumbcoachShareExtension/`):

- `ShareViewController.swift` — `UIViewController` that reads the
  shared URL from `extensionContext.inputItems` (handling both
  `UTType.url` and a plain-text URL fallback), encodes a
  `crumbcoach://import?url=<encoded>` deep link, walks the
  responder chain to find `openURL:`, and calls it to hand control
  to the main app.
- `project.yml` widget block: type `app-extension`, bundle id
  `com.crumbcoach.app.share`. Info.plist declares:
  - `NSExtensionPointIdentifier: com.apple.share-services`
  - `NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).ShareViewController`
  - `NSExtensionAttributes.NSExtensionActivationRule` —
    `NSExtensionActivationSupportsWebURLWithMaxCount: 1` so the
    extension only surfaces in Safari's share sheet for a single
    URL (not arbitrary text or files).
- Main app embeds it via `dependencies: [{ target:
  CrumbcoachShareExtension, embed: true }]`.

**End-to-end flow** that now works:

1. User reads a King Arthur Country Loaf in Safari.
2. Taps Share → CrumbCoach.
3. Share extension fires, encodes the URL, opens the main app via
   `crumbcoach://import?url=https%3A%2F%2F…`.
4. `onOpenURL` routes through `handleIncomingURL`, stashes the URL,
   navigates to the library.
5. Library's `.onAppear`/`.onChange` drains the pending URL and
   presents the editor with the source URL pre-filled.
6. User taps "Import recipe" (Stage 17), the JSON-LD importer
   populates ingredients + stages, and the user saves.

**Known gaps deliberately left for later:**

- Markdown export doesn't include the recipe photo. The Markdown
  format can't embed images inline; bundled-asset names are
  meaningless to the recipient. A future "Export bundle" (zip
  containing .md + photos) is the natural extension.
- Journal export is a single concatenated Markdown blob. A CSV
  variant for spreadsheet importers was mentioned in the plan but
  not built — bakers asking for "spreadsheet of my bakes" usually
  want the Markdown copy anyway.
- The share extension always opens the main app via the responder-
  chain `openURL:` trick. In sandboxed iOS that's documented as
  supported for share extensions; it's worked in practice since
  iOS 14 but isn't formally future-proof. If Apple ever locks this
  down, App Groups + a queued file the main app drains on launch
  is the fallback.
- The share extension has no UI — taps Share → CrumbCoach → main
  app opens almost instantly. A toast/confirmation could go in if
  user testing finds the silent hand-off confusing.

### Stage 18.5 — Duration ranges + kitchen-learned timings

**Sketch — not started.** The honest answer to "Many bread timings
will be ranges based on a condition, double in size etc. … if the
user enters the time they waited during the active bake we can show
that in the future for the time it took in their kitchen."

Two halves to this stage, sharing the same model change:

#### 18.5a — Capture and surface the source range

Today Stage 17 collapses `"60 to 90 minutes"` to a single
`durationMin = 60` (lower bound). The upper bound is thrown away
and the user sees no hint that the source published a window. This
hides exactly the most useful piece of recipe judgment — "check at
60, may need up to 90."

Model change:

```swift
struct Stage: Identifiable, Codable, Hashable {
    var kind: StageKind
    var durationMin: Int             // lower bound (or single value)
    var durationMaxMin: Int? = nil   // upper bound when a range was published
    // ...
}
```

`durationMin` keeps its current meaning (the conservative single
value the scheduler uses); `durationMaxMin` is optional and
populated only when the importer saw a range. Old persisted
recipes decode unchanged.

Importer change: `parseDurationMinutes` becomes
`parseDurationWindow -> (Int, Int?)` — returns lower + optional
upper. Range pattern populates both; compound / single populate
lower only. The compound case (`"1 hour 30 minutes"` → 90) is
single by design.

UI surfaces:

- **Recipe editor `StageRow`** — single duration field when
  `durationMaxMin == nil`; a `Min – Max` pair of fields when both
  set. Swapping to the single form clears the upper bound.
- **Recipe detail timeline** — show `60–90 min` in the stage row
  pill when both set, otherwise the existing single duration.
- **Scheduler timeline preview** — schedule against the lower
  bound (today's behavior, conservative) but caption it
  `"start checking at 60 min — recipe says up to 90"` for ranged
  stages.
- **Active bake current-stage card** — show the range plus a "your
  kitchen typically takes X" override once 18.5b lands (below).

This half delivers value on its own — the user sees what the
source actually said. Maybe 2–3 hours of work.

#### 18.5a — completion notes

Landed exactly as sketched, no scope surprises.

- `Stage.durationMaxMin: Int? = nil` added to `Models/Recipe.swift`.
  Optional with default, so every existing recipe initializer
  (sample data, journal serialized entries, editor `blank()`, etc.)
  decodes unchanged and behaves as before — single-value duration
  unless explicitly set.
- `RecipeImporter.parseDurationMinutes` is now `parseDurationWindow`
  returning `(lower: Int, upper: Int?)`. Range pattern fills both;
  compound and single fill `(value, nil)`. A back-compat
  `parseDurationMinutes` shim is kept so nothing outside the
  importer broke. `mapStages` reads both from the window into
  `durationMin` + `durationMaxMin`.
- `CCFormat.stageDuration(_ stage:)` is the single display helper.
  Returns `"60m"` for a single value, `"60m–1h 30m"` for a range.
  Three display sites switched over:
  - `ActiveBakeScreen` timeline row
  - `RecipeDetailScreen` stages list
  - `RecipeExporter` markdown export
- Schedule math (`Scheduler.adjustedDuration`,
  `stageStartTimes`, end-to-end sums) deliberately *did not*
  change — they keep using `durationMin` so the scheduler still
  builds a conservative timeline. Showing the range is purely a
  display concern at this stage; switching the scheduler over to
  an upper-bound or midpoint mode is a deliberate Phase C polish
  if user testing asks for it.
- `RecipeEditorScreen` `StageRow` grew a range toggle. Default is
  a single field. Tapping the plus-rectangle icon adds an upper-
  bound field next to the lower with a `–` separator; tapping
  the slash icon removes it. New range default = max(lower+15,
  lower×1.5) so the user lands on a sensible starting value they
  can edit immediately.

Known gaps deliberately left for 18.5b / later:

- The Scheduler still ignores the upper bound. Stage 18.5b can
  promote the upper-bound when kitchen learning suggests a slow
  kitchen needs the extra time.
- Validation: if the user enters `max < min`, we don't swap or
  warn. The save path's `weightsError` doesn't check ranges. A
  three-line addition could swap or surface — left out to keep
  this stage tight.
- The Scheduler timeline preview doesn't yet caption ranged
  stages with "start checking at 60 min". Documented as a polish
  item once the timeline gets a real proof-state UI.

#### 18.5b — Kitchen-learned timings from journal data

`ActiveBake.StageHistoryEntry` already captures `enteredAt` and
`exitedAt` per stage (Stage 3 added them). `completeBake` writes
`bulkMinutes` to the journal. The data foundation is there; what
is missing is an aggregation surface that says "for this recipe,
this stage, in this kitchen, you usually take N minutes."

Two new pieces:

- **`JournalEntry.stageDurations: [Int: Int]?`** — `stageIndex →
  minutes`. Populated in `completeBake` from every history entry's
  `enteredAt`/`exitedAt`. Today we drop everything except bulk;
  this preserves the rest.
- **`Analytics.kitchenTimings(for recipeId:, in journal:) ->
  [Int: KitchenTiming]`** where:

  ```swift
  struct KitchenTiming {
      let stageIndex: Int
      let averageMinutes: Int
      let bakes: Int          // sample size — UI gates on >= 3
      let median: Int?        // outlier guard for small samples
      let lastBake: Int       // most recent timing for "this week" context
  }
  ```

  Iterates the journal entries for the recipe, gathers per-stage
  durations, computes mean/median. Sample-size threshold means the
  feature surfaces only after the user has actually baked the
  recipe a few times.

UI:

- **Active bake current-stage card** picks up a third line beneath
  the title — `"Your kitchen typically takes 4h 35m for this stage
  (5 bakes)."` — when the threshold is met. Replaces or augments
  today's hardcoded "this dough has averaged 4h 45m bulk in your
  last 5 bakes" copy (which is currently a static string in
  `currentStageCard`).
- **Recipe detail timeline** swaps the recipe-baseline duration
  for the user's average when the sample size is sufficient,
  badged `"your kitchen"` so the source-of-truth is visible.
- **Scheduler timeline preview** uses `kitchenTimings` to compute
  the `historyAdjustmentPct` the scheduler already accepts as a
  parameter — replaces today's hardcoded `historyAdjustmentPct:
  15` with a per-recipe / per-stage computed value.

This half is the spec's whole "scheduler learns your kitchen"
pitch made real. ~4–6 hours of work including the model change,
the aggregation, and three UI surfaces.

#### Why these belong together

They share the model: `Stage.durationMaxMin` (18.5a) gives the
recipe-side range, and `KitchenTiming.averageMinutes` (18.5b)
gives the kitchen-side actual. Both pieces appear in the same UI
surfaces (active bake stage card, recipe detail, scheduler) — a
ranged stage with kitchen learning reads as:

> **Cold retard** — recipe says **8 – 12 hours**; your kitchen
> averages **9h 20m** over your last 4 bakes.

Without 18.5a, the recipe-side number is misleadingly precise.
Without 18.5b, the user has to remember their own kitchen's
timing. With both, the active-bake card stops being a recipe
read-out and becomes the user's running coach. That's the
"crumbcoach" pitch.

#### Risks and trade-offs

- **Model migration**: optional field with default `nil`, so
  no breaking change. The Scheduler still uses `durationMin` for
  reverse-scheduling — adding `durationMaxMin` is purely
  informational unless the user opts into "schedule against upper
  bound" (Phase C polish).
- **Sample-size threshold**: too low (1 bake) is noisy; too high
  (10 bakes) means the feature never appears for slow bakers. 3
  bakes feels right; expose as a constant for tuning.
- **Kitchen drift**: a baker's kitchen warms over the summer, so
  averages from 6 months ago may not reflect today. `KitchenTiming`
  should weight recent bakes higher — exponential decay on age,
  or simple "last 5 bakes" window.
- **Cross-recipe transfer**: if the user bakes a new recipe with
  a `.bulkFold` stage at 22°C, their kitchen's history on other
  recipes' `.bulkFold` stages at similar temps is relevant. Cross-
  recipe aggregation is a Phase D possibility (Stage 24-ish, on-
  device modeling).

#### Sequencing

Build 18.5a first — it's the model change + simple UI updates,
delivers immediate value, unblocks 18.5b. If user testing on real
recipes shows the range surface is enough, 18.5b can wait until
the journal has enough data to be useful (the user needs to bake
3+ times before kitchen learning even appears).

---

## Phase C — Platform expansion (1.x → 2.0)

iOS-ecosystem features that turn CrumbCoach from "an iPad app" into
"a baker's tool that lives across their devices".

### Stage 19 — iOS widgets

Home Screen + Lock Screen widgets for active bake / next action:

- Small: current stage + minutes-to-next-action.
- Medium: + fold counter ring + bake-out time.
- Large: + timeline strip.

Lock Screen widget pairs naturally with the Live Activity from Stage 16.

### Stage 20 — HomeKit / Matter kitchen-temperature integration

Read real kitchen temperature from a HomeKit accessory; replace the
static `state.kitchenTempC`. Settings exposes the device picker.
Scheduler's "kitchen temperature" slider becomes the override (manual
mode), with HomeKit as the auto source.

### Stage 21 — Apple Watch companion

WatchKit / SwiftUI for watchOS showing next-action prompts and the
bake timer. Mark folds from the watch (taps in the wrist).
Complications on the watch face for active bakes.

Separate target in `project.yml`; shares Models + Core via a package.

### Stage 22 — Localization

English-only at launch (per spec). Pick one major language for 1.x —
likely Spanish or German based on baker community density. RTL
support if Arabic / Hebrew are ever on the list (currently no).

---

## Phase D — Commercial / Pro tier

Monetization + the headline ML feature. Don't start until 1.x is
stable in users' hands.

### Stage 23 — Cloud Pro subscription tier

StoreKit 2 subscription ($30/year per the spec). Includes:

- Paywall screen, restore-purchases flow, family sharing.
- Receipt validation (server-side preferred).
- Subscription state in `AppState` (active / lapsed / trial).
- Pro-gated features TBD — likely Stage 24's cloud inference, deeper
  analytics, recipe collaboration.

Spec §7 and §9.

### Stage 24 — On-device AI crumb diagnostic

The headline differentiator. Train a 4 B-parameter vision-language
model on bread imagery, quantize to int4, export to Core ML, bundle
in the app (2–4 GB). Replaces the stubbed
`DiagnosticScreen.startAnalysis` timer with a real diagnosis.

This is a separate ML project, not an app-engineering task. Spec §4.5
and §10.

### Stage 25 — Sourdough Sidekick BLE integration

Requires partnership with FirstBuild for the API. Until then this is
blocked. Spec §4.7 and §8. The UI surface
(`StarterScreen.sidekickCard`) is already designed; only the BLE
plumbing is missing.

---

## Phase E — Content & growth

Long-tail features that grow the user base or surface area but aren't
on the critical path.

### Stage 26 — Recipe library expansion to 50+

Bring the seed library to ~50 originals across every bread type in
spec §4.1. Currently 9 originals + 4 linked recipes.

### Stage 27 — Native iPad citizenship

Spotlight indexing of recipes, Handoff between devices,
drag-and-drop photos into the editor / active bake. Small features
individually; together they make CrumbCoach feel like a first-class
iPad app.

### Stage 28 — iPhone target decision

The current layout is iPad-landscape-only and uses 1440 × 1024 as a
canvas. Two paths:

1. **Stay iPad-exclusive** — lean into that in marketing; iPad is
   where the kitchen counter lives anyway.
2. **Ship an iPhone build** — significant work; every screen would
   need a portrait/compact layout.

Pick one before 2.0. The decision affects Stage 21's Watch
companion architecture (Watch typically pairs with iPhone).

---

## Phase F — Final ship prep

The non-code work that has to happen to actually push v1.0 to the App
Store. Moved to the end of the plan so the engineering phases (A–E)
can land first; this is a marketing / content sprint, not a Swift
sprint.

### Stage 11 — App Store assets + privacy

12.9" iPad landscape screenshots (5 minimum: Today, Active bake,
Library, Recipe detail, Journal). Description, keywords, App Store
category, age rating questionnaire. **Privacy questionnaire** is the
non-obvious blocker — answer requires knowing what the app collects.
Add:

- Public privacy policy URL (host on a static site or GitHub Pages).
- Support URL.
- Marketing URL (optional).

---

## Pre-1.0 stub inventory (post-Stage-6 audit)

Found by a code-review pass after Phase B landed. Stage 6's "stub-
button cleanup" caught the empty-closure cases; this list is the
gap — copy and state that *looks* real but isn't. None of these
block compilation, but several read as outright lies to the user.
Worth working through before the TestFlight beta widens.

### User-visible hardcoded copy

- [ ] **HomeScreen StarterCard "Feed at 8:14 PM →"**
  ([HomeScreen.swift:191](Crumbcoach/Features/Home/HomeScreen.swift:191))
  — fixed clock time regardless of selected starter's `nextFeed`.
  Replace with `starter.nextFeed` or compute from last-fed + 4–6h.
- [ ] **HomeScreen UpNextCard "Country Sourdough … at 4:14 PM"**
  ([HomeScreen.swift:261](Crumbcoach/Features/Home/HomeScreen.swift:261)
  / [:265](Crumbcoach/Features/Home/HomeScreen.swift:265))
  — recipe title + levain-build time both hardcoded. Should derive
  from the user's most-recently-baked or favorited recipe, and
  compute the build time from the chosen target.
- [ ] **HomeScreen DiagnosePromptCard "your last 6 Country
  Sourdoughs"** ([HomeScreen.swift:297](Crumbcoach/Features/Home/HomeScreen.swift:297))
  — hardcoded recipe name in promo copy. Should reflect the user's
  actual most-baked recipe (or generic "recent bakes" when journal
  is sparse).
- [ ] **StarterScreen photo timestamp fallback "6:14 PM today"**
  ([StarterScreen.swift:130](Crumbcoach/Features/Starter/StarterScreen.swift:130))
  — when `starter.lastPhotoTime` is nil. Replace with "No photo
  yet" or hide the timestamp line entirely.
- [ ] **ActiveBakeScreen proof-oven schedule reflow line**
  ([ActiveBakeScreen.swift:328](Crumbcoach/Features/ActiveBake/ActiveBakeScreen.swift:328))
  — "Schedule reflowed: next fold in 9m (was 14m), bake out 5:47
  AM (was 7:38 AM)" is a static demo string. Should derive from
  the Stage-8 rebalanced schedule.

### Sidekick UI (mocked until Stage 25)

The Sourdough Sidekick BLE integration is blocked on a partnership
(Phase D Stage 25). The UI surfaces below render as if the device
is paired and reporting; until the integration lands they're
narrative theater.

- [ ] **StarterScreen sidekickCard**
  ([StarterScreen.swift:193–208](Crumbcoach/Features/Starter/StarterScreen.swift:193))
  — Connected pill, "Counter-active" preset, "Last feed at 8:14 AM
  · jar temp 23.1°C · 152% peak observed" all hardcoded with no
  data path behind them. Hide behind a feature flag (`Stage25Enabled`
  / `state.sidekickPaired`) and surface a "Pair a Sourdough Sidekick
  (coming soon)" stub instead, or remove from v1.
- [ ] **SchedulerScreen sidekickLoopCard**
  ([SchedulerScreen.swift:338–349](Crumbcoach/Features/Scheduler/SchedulerScreen.swift:338))
  — "Ruby will be fed 1:5:5 at 2:14 PM to peak 200g of 100%
  hydration levain at mix time Sat 8:14 PM" — single static
  paragraph. The `useSidekick` toggle in the conditions card gates
  visibility but the copy never adapts. Same fix as above.

### Interaction lies

- [ ] **HomeScreen UpNextCard time chips**
  ([HomeScreen.swift:237](Crumbcoach/Features/Home/HomeScreen.swift:237))
  — `@State selectedTime` mutated by TagPills (line 255), but the
  paragraph below (lines 259–267) is fully hardcoded and never
  reads it. Taps register, nothing changes on screen. Either wire
  the chips into the displayed schedule preview or remove them.

### Recently spotted from review

(Carried in from the post-eb606ff code-review pass — many already
closed by `1c0a4d8`. Surviving worth-addressing items kept here for
visibility.)

- [x] ~~`RecipeImporter.categoryGuess` operator-precedence bug —
  "vegetable oil" / "canola oil" tag as `.liquid` instead of
  `.fat`.~~ Closed: parenthesized the melted-butter clause and
  pulled `oil` out of the liquid chain entirely; oil is always a
  fat in bread math.
  ([RecipeImporter.swift](Crumbcoach/Shared/RecipeImporter.swift))
- [ ] `cloudSyncEnabled` round-trips through the cloud JSON, so
  opt-out on one device gets silently re-enabled by a pull from a
  still-enabled device.
  ([AppState.swift](Crumbcoach/Data/AppState.swift))
  Move opt-in to UserDefaults or skip the field in `reload(from:)`.
- [ ] `LiveActivityManager` not `@MainActor`-isolated.
  ([LiveActivityManager.swift](Crumbcoach/Shared/LiveActivityManager.swift))
  Today's callers are all main; Swift 6 strict concurrency will
  flag this.
- [ ] Share extension accepts any URL the system hands it; non-
  `http(s)` schemes pass through and fail later in the importer.
  ([ShareViewController.swift:52](../CrumbcoachShareExtension/ShareViewController.swift:52))
  Validate `url.scheme` before encoding the deep link.
- [ ] `cloudSyncStatusLine` shows `Date()` (now) as "Last synced"
  after a pull, hiding the cloud file's real mtime.
  ([SettingsScreen.swift](Crumbcoach/Features/Settings/SettingsScreen.swift))

### Confirmed clean

- No TODO / FIXME / XXX / HACK comments anywhere in the Swift
  sources.
- No empty-closure buttons (Stage 6's audit survives).
- No broken image references.
- Sample data correctly scoped behind "Load demo data" + first-
  launch seeding paths.

---

## Working on a stage

1. Open this file. Read the preamble.
2. Open the stage section. Read the "Where the stubs live today" and
   "Implementation" subsections.
3. Read the linked source files in full before editing.
4. Implement, test, commit.
5. Update this file's status section at the bottom.

## Status

### Tier 1 — shipped

| Stage | Status   | Owner | Notes |
|-------|----------|-------|-------|
| 1     | done     |       | Camera & photo picker. See "Stage 1 — completion notes". |
| 2     | done     |       | Local notifications. See "Stage 2 — completion notes". |
| 3     | done     |       | Start-a-bake flow. See "Stage 3 — completion notes". |
| 4     | done     |       | Recipe editor. See "Stage 4 — completion notes". |
| 5     | done     |       | Onboarding & settings. See "Stage 5 — completion notes". |

### Phase A — pre-1.0 ship-readiness (blocking)

| Stage | Status   | Owner | Notes |
|-------|----------|-------|-------|
| 6     | done     |       | Stub-button cleanup. See "Stage 6 — completion notes". |
| 7     | done     |       | Empty & error states. See "Stage 7 — completion notes". |
| 8     | done     |       | Notification rescheduling on advance / skip. See "Stage 8 — completion notes". |
| 9     | done     |       | Crash reporting + telemetry. See "Stage 9 — completion notes". |
| 10    | done     |       | Accessibility audit. See "Stage 10 — completion notes". |

### Phase B — 1.x quality & polish

| Stage | Status   | Owner | Notes |
|-------|----------|-------|-------|
| 12    | done     |       | Multi-page onboarding + Settings units & temp-source switchers. See "Stage 12 — completion notes". |
| 13    | done     |       | Recipe editor v2. See "Stage 13 — completion notes". |
| 14    | done     |       | Haptics + animation polish. See "Stage 14 — completion notes". |
| 15    | done     |       | iCloud Drive sync (ubiquity Documents). See "Stage 15 — completion notes". |
| 16    | done     |       | Live Activity widget. See "Stage 16 — completion notes". |
| 17    | done     |       | Recipe URL import (JSON-LD). See "Stage 17 — completion notes". |
| 17.5a | done     |       | Import gap-filling — static volume-to-grams table + duration parsing + egg counts + parens/"and" fixes. See "Stage 17.5a — completion notes". |
| 17.5b | sketched |       | Import gap-filling — Foundation Models fallback. |
| 18    | done     |       | Share & export. See "Stage 18 — completion notes". |
| 18.5a | done     |       | Duration ranges captured + displayed. See "Stage 18.5a — completion notes". |
| 18.5b | sketched |       | Kitchen-learned timings from journal data. |

### Phase C — platform expansion (1.x → 2.0)

| Stage | Status   | Owner | Notes |
|-------|----------|-------|-------|
| 19    | not started |    | iOS widgets (Home Screen + Lock Screen). |
| 20    | not started |    | HomeKit / Matter kitchen-temperature integration. |
| 21    | not started |    | Apple Watch companion. |
| 22    | not started |    | Localization — first non-English language. |

### Phase D — commercial / Pro tier

| Stage | Status   | Owner | Notes |
|-------|----------|-------|-------|
| 23    | not started |    | Cloud Pro subscription tier (StoreKit 2). |
| 24    | not started |    | On-device AI crumb diagnostic (Core ML VLM). |
| 25    | not started |    | Sourdough Sidekick BLE integration (gated on partnership). |

### Phase E — content & growth

| Stage | Status   | Owner | Notes |
|-------|----------|-------|-------|
| 26    | not started |    | Recipe library expansion to ~50. |
| 27    | not started |    | Native iPad citizenship — Spotlight, Handoff, drag-and-drop. |
| 28    | not started |    | iPhone target decision (support iPhone or stay iPad-exclusive). |

### Phase F — final ship prep

| Stage | Status   | Owner | Notes |
|-------|----------|-------|-------|
| 11    | not started |    | App Store assets + privacy policy + privacy questionnaire. |
