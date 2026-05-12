# CrumbCoach (iPad)

One iPad app for every bread you bake. Starter management, recipe library,
scheduling, AI diagnostics — combining the **functions from the CrumbCoach
spec** (`/crumbcoach`) with the **design language from `bread-remix`** into a
native SwiftUI app for iPad.

## What's here

- **`Crumbcoach/Models/`** — Swift versions of the Rust core types from the
  Code Spec: `Recipe`, `Stage`, `Ingredient`, `Preferment`, `Starter`,
  `Schedule`, `ActiveBake`, `JournalEntry`.
- **`Crumbcoach/Core/`** — algorithms:
  - `BakersPercentages` — flour-relative percentage math, scaling, hydration
    adjustment.
  - `Conversion` — tangzhong, yudane, yeasted → sourdough conversion.
  - `Scheduler` — forward + reverse scheduling with Q10 temperature
    adjustment and history bias.
  - `StarterPrediction` — feed-to-peak time prediction, levain build planning.
  - `Analytics` — bulk/rating correlation, kitchen-temp trend, insight
    generation.
- **`Crumbcoach/Data/`** — seed catalog (9 recipes, 2 starters, 6 bake
  journal entries) ported directly from `bread-remix/project/data.jsx`.
- **`Crumbcoach/DesignSystem/`** — design tokens (colors, typography, shadows)
  and primitives (`Card`, `Kicker`, `StatusPill`, `TagPill`, `RingProgress`,
  `Sparkline`, `BreadPhoto`, `CCButtonStyle`).
- **`Crumbcoach/Features/`** — one folder per screen, each a single SwiftUI
  file:
  - `Shell/AppShell.swift` — 232-wide sidebar + sticky header layout.
  - `Home/HomeScreen.swift` — active bake banner, 3-up cards, insights.
  - `Library/LibraryScreen.swift` + `RecipeDetailScreen.swift` — grid +
    detail with live scale/hydration sliders wired to `BakersMath`.
  - `ActiveBake/ActiveBakeScreen.swift` — fold counter, proofing-oven
    override, live timeline with photo strips.
  - `Scheduler/SchedulerScreen.swift` — forward/reverse mode, kitchen temp,
    Sidekick toggle, live timeline preview from `Scheduler.generate*`.
  - `Starter/StarterScreen.swift` — switcher + rise chart + AI check.
  - `Diagnostic/DiagnosticScreen.swift` — photo panel with annotation
    overlay, four-state machine (idle → analyzing → result).
  - `Journal/JournalScreen.swift` — list + bulk-time-vs-rating scatter.

## Build and run

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from `project.yml`.

```bash
# Regenerate the .xcodeproj after editing project.yml
xcodegen generate

# Open in Xcode
open Crumbcoach.xcodeproj
```

Targets iOS 17, iPad only, landscape preferred. AppKit / Catalyst not
supported.

> Note on the build environment in this checkout: the AI diagnostic and the
> Sidekick integration are stubs (the spec calls for a 4 B-parameter VLM and
> BLE / Wi-Fi LAN respectively — neither is feasible in a SwiftUI prototype).
> Everything else is real: scheduling, recipe math, conversion, starter
> prediction, and bake-history analytics all run through the `Core/` modules.

## Scope, in one paragraph

This is a faithful native build of the design (`/bread-remix/project/*.jsx`)
with the algorithmic spec (`/crumbcoach/CrumbCoach_*.md`) underneath.  Where
the spec describes a Rust shared core, on-device VLM, BLE-paired hardware,
and CloudKit sync, the iPad app implements the **same data model and the same
math in Swift**, leaves the AI and hardware integration as stubs that match
the design's UX, and stores everything in memory.  Porting the math up into a
Rust core via `uniffi-rs` later is the natural next step described in §3 of
the Code Spec.
