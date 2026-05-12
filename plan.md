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
- Bundle id: `com.crumbcoach.app` (this repo) / users override in their fork.
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

---

## Tier 2 stages (do after Tier 1 ships)

### Stage 6 — iCloud sync

Replace `PersistenceController`'s file-based store with
`NSPersistentCloudKitContainer` or migrate to SwiftData with CloudKit.
Spec §11.

Considerations:
- SwiftData migration is a larger rewrite (every value-type model
  becomes a `@Model` class with `@Relationship`).
- `NSPersistentCloudKitContainer` is the lower-risk path — Core Data
  underneath but minimal API changes.
- Either way, requires the iCloud capability in `project.yml`:
  ```yaml
  entitlements:
    com.apple.developer.icloud-services:
      - CloudKit
    com.apple.developer.icloud-container-identifiers:
      - iCloud.com.crumbcoach.app
  ```

### Stage 7 — Live Activity

`ActivityKit` widget showing the active bake's current stage, fold
count, and time-to-next-action. Visual matches the preview in
`ActiveBakeScreen.liveActivityCard`.

### Stage 8 — Recipe URL import (Recipe JSON-LD)

Implement spec §6.1. Most major bread sites (King Arthur, The Perfect
Loaf, Foodgeek) publish Recipe schema in JSON-LD. Parse it server-side
or with a `URLSession` + light HTML parsing on-device. Extract formula
only (ingredients + weights); don't copy prose.

### Stage 9 — Share & export

- Share a recipe via deep link + markdown.
- Export bakes to CSV (currently "Export to Markdown" button in Journal
  is a no-op).
- iOS Share Sheet integration for incoming recipes from Safari.

### Stage 10 — Accessibility audit

- VoiceOver labels on every interactive element.
- Dynamic Type rollout beyond the sidebar (already done).
- High-contrast mode pass.
- Reduced motion: gate `.fade-up` animations.

---

## Tier 3 stages (months, possibly partnerships)

### Stage 11 — On-device AI diagnostic

Train a 4 B-parameter vision-language model on bread imagery, quantize
to int4, export to Core ML, bundle in the app (2–4 GB). Implement spec
§4.5 and §10. This is a separate ML project, not an app-engineering
task.

### Stage 12 — Cloud Pro tier

StoreKit 2 subscription ($30/year). Stateless cloud inference service.
Receipt validation. Spec §7 and §9.

### Stage 13 — Sourdough Sidekick BLE

Requires partnership with FirstBuild for the API. Until then this is
blocked. Spec §4.7 and §8.

### Stage 14 — HomeKit / Matter sensors

Read real kitchen temperature from a HomeKit accessory; replace the
static `state.kitchenTempC`.

### Stage 15 — Apple Watch companion

WatchKit / SwiftUI for watchOS showing next-action prompts and the bake
timer.

---

## Tier 4 — Infrastructure & growth

### Stage 16 — Crash reporting & telemetry

Sentry or equivalent. Privacy-friendly. Spec §13.

### Stage 17 — App Store screenshots & description

iPad 12.9" landscape screenshots. Description, keywords, privacy
questionnaire.

### Stage 18 — Localization

English-only at launch (per spec). Phase 4.

### Stage 19 — Recipe library expansion

Bring the seed library to 50 originals across all bread types per spec
§4.1.

---

## Working on a stage

1. Open this file. Read the preamble.
2. Open the stage section. Read the "Where the stubs live today" and
   "Implementation" subsections.
3. Read the linked source files in full before editing.
4. Implement, test, commit.
5. Update this file's status section at the bottom.

## Status

| Stage | Status   | Owner | Notes |
|-------|----------|-------|-------|
| 1     | not started |       |       |
| 2     | not started |       |       |
| 3     | not started |       |       |
| 4     | not started |       |       |
| 5     | not started |       |       |
| 6+    | not started |       |       |
