# CrumbCoach (iPad)

One iPad app for every bread you bake. Starter management, recipe library,
scheduling, AI diagnostics — combining the **functions from the CrumbCoach
spec** (`/crumbcoach`) with the **design language from `bread-remix`** into a
native SwiftUI app for iPad. Landscape-only.

## Structure

```
Crumbcoach/
├── CrumbcoachApp.swift              # @main, scenePhase save
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
CrumbcoachTests/                     # Unit tests for the Core algorithms
project.yml                          # XcodeGen project spec
```

## Persistence

State lives at `<Application Support>/Crumbcoach/state.json` and persists
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
open Crumbcoach.xcodeproj
```

Targets iOS 17, iPad, landscape-only.

### Tests

```bash
xcodebuild test \
  -project Crumbcoach.xcodeproj \
  -scheme Crumbcoach \
  -destination 'platform=iOS Simulator,name=iPad Pro (12.9-inch)'
```

The `CrumbcoachTests` target covers the four Core modules:

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
