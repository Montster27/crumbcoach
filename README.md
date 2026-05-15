# GeekBread (iPad)

One iPad app for every bread you bake. Starter management, recipe library,
scheduling, AI diagnostics — combining the **functions from the GeekBread
spec** (`/geekbread`) with the **design language from `bread-remix`** into a
native SwiftUI app for iPad. Landscape-only.

## Structure

```
GeekBread/
├── GeekBreadApp.swift              # @main, scenePhase save
├── Models/                          # Recipe, Stage, Starter, Schedule, Bake
├── Core/                            # Pure functions: BakersMath, Conversion,
│                                    # Scheduler, StarterPrediction, Analytics
├── Data/                            # AppState (Observable),
│                                    # PersistenceController (JSON to App
│                                    # Support), PersistedState (versioned
│                                    # on-disk shape), seed data
├── DesignSystem/                    # Theme tokens + SwiftUI primitives
├── Features/                        # One folder per screen
└── Resources/                       # Assets.xcassets
GeekBreadTests/                     # Unit tests for the Core algorithms
project.yml                          # XcodeGen project spec
```

## Persistence

State lives at `<Application Support>/GeekBread/state.json` and persists
across launches.

- **Saves are debounced** (1 s) so slider drags don't thrash the disk.
- **Scene phase** transitions to `.background` / `.inactive` force a flush.
- **Versioned schema** (`PersistedState.currentVersion`). Mismatched versions
  fall back to seed data and quarantine the bad file as `state.bad.<ts>.json`.
- **`AppState.resetToSamples()`** wipes everything back to the demo data.

The spec calls for **SwiftData + CloudKit** (§4.1). JSON on disk is a
pragmatic stand-in that gives durable storage today; the `PersistedState`
struct is a one-to-one shape for a future SwiftData/CloudKit migration.

## Build and run

```bash
xcodegen generate
open GeekBread.xcodeproj
```

Targets iOS 17, iPad, landscape-only. The same target also builds as a
Mac Catalyst app (`SUPPORTS_MACCATALYST: YES` in `project.yml`).

### Build script

`./build.sh` runs `xcodegen generate`, then builds iOS Simulator and
Mac Catalyst **in parallel** with code signing disabled, archives the
Mac side, and copies both `.app` bundles to a single output folder:

```
build/dist/
├── GeekBread-iOS.app          # Simulator build
├── GeekBread-Mac.app          # Mac Catalyst, extracted from the archive
└── GeekBread-Mac.xcarchive    # Full archive (Mac)
```

Flags:

```bash
./build.sh             # iOS + Mac, parallel (default)
./build.sh --ios       # iOS only
./build.sh --mac       # Mac Catalyst only
./build.sh --serial    # both, one after the other (easier to debug)
```

Logs land in `build/logs/{ios,mac,xcodegen}.log` so the parallel run
stays quiet on the terminal.

Parallel isolation: before each build the source tree (sources +
generated `.xcodeproj`) is APFS-cloned into `build/clone-{ios,mac}/`
via `cp -cR`. That's a copy-on-write block clone — essentially free
on the same volume — so the two xcodebuild processes own fully
independent project files and never lock each other. Each platform
also gets its own `-derivedDataPath` (`build/derived-{ios,mac}`).

Quick launch:

```bash
open build/dist/GeekBread-Mac.app
xcrun simctl install booted build/dist/GeekBread-iOS.app
```

For a signed Mac Catalyst release, drop `CODE_SIGNING_ALLOWED=NO` from
the `xcodebuild archive` call and let Xcode provision a Mac profile —
iCloud + App Group entitlements need a one-time setup in your Apple
Developer account on first signed build.

### Tests

```bash
xcodebuild test \
  -project GeekBread.xcodeproj \
  -scheme GeekBread \
  -destination 'platform=iOS Simulator,name=iPad Pro (12.9-inch)'
```

The `GeekBreadTests` target covers the four Core modules:

- `BakersMathTests` — percentages, scaling, hydration adjustment, warning
  thresholds.
- `ConversionTests` — tangzhong / yudane / yeasted→sourdough flour
  conservation; proportional flour subtraction across multiple flours.
- `SchedulerTests` — forward and reverse scheduling, Q10 temperature
  adjustment, cold-retard skip.
- `PersistenceTests` — Codable round-trip and graceful corrupt-file handling.

## What's real vs. stubbed

| Feature                 | Status                                                       |
|-------------------------|--------------------------------------------------------------|
| Recipe library + math   | Real. Bakers’ percentages and conversions live in `Core/`.   |
| Scheduling (fwd + rev)  | Real. Q10 temperature adjustment + history bias.             |
| Starter management      | Data persisted; rise chart + AI status are stubbed.          |
| Recipe scaling / hyd.   | Real. Slider drives `BakersMath.scale` + `adjustHydration`.  |
| Bake journal + filters  | Real. Date-based filters wired up.                           |
| Persistence             | Real. JSON on disk, scene-phase aware, versioned.            |
| AI Crumb Diagnostic     | UI-only stub. 4 B-parameter VLM is not bundled.              |
| Sourdough Sidekick      | UI-only stub. No BLE.                                        |
| Live Activities / Watch | Visual preview only. No `ActivityKit`.                       |
| Photos / fonts          | Fall back to gradients / SF Pro. Bundle assets to enable.    |
