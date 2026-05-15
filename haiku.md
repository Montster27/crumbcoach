# Haiku integration plan

Where Claude Haiku (`claude-haiku-4-5-20251001`) would slot into GeekBread, ranked by value-per-week-of-work. Each entry lists the specific files, models, and existing patterns it would touch so the implementation isn't speculative.

Context this doc assumes the reader has:
- The recipe-import audit in this conversation thread (Stage 17 / 17.5b parsers handle row-level gaps but miss structural ones — preferment sectioning, `breadType`, temperatures, junk-row filtering, stage classification).
- The plan-doc framing: Stage 23 is the Cloud Pro tier, Stage 24 is the on-device VLM crumb diagnostic, Stage 24a is the shipped Apple Vision similarity card.
- The existing AI scaffolding: [`AIRecipeAssist`](GeekBread/Shared/AIRecipeAssist.swift) (Apple Foundation Models, opt-in via `state.aiAssistEnabled`), and the [`VisionFeaturePrint`](GeekBread/Shared/VisionFeaturePrint.swift) wrapper underneath [`DiagnosticScreen`](GeekBread/Features/Diagnostic/DiagnosticScreen.swift).

A cross-cutting decision section at the bottom covers the once-per-app concerns (API key strategy, single client, single toggle, fallback contract).

---

## Tier 1 — clear wins

The three surfaces where the gap between "what the marketing copy promises" and "what ships today" is largest.

### 1.1 Crumb diagnostic (replaces Stage 24's on-device VLM plan)

Today's surface is Stage 24a — [`DiagnosticScreen.startAnalysis`](GeekBread/Features/Diagnostic/DiagnosticScreen.swift) computes Apple Vision feature prints and shows the closest journal photo. Honest, but not a diagnosis. The planned Stage 24 (custom-trained VLM, 4–6 months of ML work, 2-GB bundle) is replaced by a Haiku vision call.

**Touches:**

- **New** `GeekBread/Shared/CrumbDiagnosis.swift` — async wrapper with the signature the existing Stage 24 plan already designed: `diagnose(image: UIImage, context: BakeContext) async -> Diagnosis?`. `BakeContext` is a small value type pulling `hydrationPct`, `bulkHours`, `ambientTempC`, `retardHours` from the active bake or the linked journal entry.
- **New** `GeekBread/Shared/RemoteAIClient.swift` — the single HTTP/SDK seam every Tier 1 + Tier 2 surface shares. See "Cross-cutting" below.
- **New** `GeekBread/Models/Diagnosis.swift` — `Codable` struct: `primaryLabel: DiagnosisLabel`, `explanation: String`, `confidence: Double`, `suggestions: [String]`, `secondaryLabels: [DiagnosisLabel: Double]`. Persists on `JournalEntry` so the diagnosis appears in the markdown export and survives re-opens.
- **Modified** `GeekBread/Features/Diagnostic/DiagnosticScreen.swift` — `startAnalysis()` calls `CrumbDiagnosis.diagnose` first; on success, the new Diagnosis card sits above the existing match card. On low confidence (<70%) or any error, the diagnosis card hides and the 24a similarity card promotes to primary — the existing match-card code path is unchanged. Honesty card text rewritten: "GeekBread sends your crumb photo and bake context to Claude (Anthropic)…".
- **Modified** `GeekBread/Features/Settings/SettingsScreen.swift` — new "Cloud AI" section below the existing `AIRecipeAssist` block (around line 157). Single toggle gates all Tier 1 + Tier 2 surfaces, not just diagnosis.
- **Modified** `GeekBread/Models/Journal.swift` (or wherever `JournalEntry` lives) — optional `diagnosis: Diagnosis?` field. Decodes nil for older entries.

**Kept untouched (the offline fallback):** [`VisionFeaturePrint.swift`](GeekBread/Shared/VisionFeaturePrint.swift) and the 24a match-card UI. Free-tier users and offline users see the same Stage 24a experience as today.

**Effort:** 3–4 weeks. The bulk is prompt + schema design + an eval harness against the team's existing journal photos — not Swift work.

### 1.2 Starter health check

Today's [`StarterScreen.aiCheckCard`](GeekBread/Features/Starter/StarterScreen.swift) line 131 renders hardcoded text claiming "State: post-peak. Surface flattening, large open bubbles. Use now for an active bake, refrigerate, or feed within 4h." for every starter regardless of input. It looks like a working AI feature and isn't. Spec §4.4 is explicit about what it should do.

**Touches:**

- **New** `GeekBread/Shared/StarterAssessment.swift` — same shape as `CrumbDiagnosis`: `assess(image: UIImage, context: StarterContext) async -> StarterAssessment?`. `StarterContext` carries `hoursSinceFeed`, `kitchenTempC`, `storage` (counter/fridge), recent `lastPhoto` references so the model can reason about "more active than last feed" type observations.
- **New** `GeekBread/Models/StarterAssessment.swift` — `state: StarterState` (peak / pre-peak / post-peak / hungry / sluggish), `hoursToPeak: Double?` (predicted), `suggestedAction: StarterAction` (.useNow / .refrigerate / .feedNow / .waitFor(hours)), `confidence: Double`.
- **Modified** `GeekBread/Features/Starter/StarterScreen.swift:131` — `aiCheckCard` reads `starter.assessment` instead of hardcoded text. The "Feed now" / "Refrigerate" buttons stay; their default action is now driven by `suggestedAction`. Photo-picker plumbing already exists at line 158 — when a new photo is saved, kick off `StarterAssessment.assess` and persist the result on the `Starter` model.
- **Modified** `GeekBread/Models/Starter.swift` (or wherever `Starter` is defined) — add `assessment: StarterAssessment?` field. Existing `state: String` becomes derived (`assessment?.state.displayLabel ?? "Unknown"`) and the seed data gets the assessment field as nil.
- Reuses the same `RemoteAIClient` and the same single Settings toggle as 1.1.

**Effort:** 1–2 weeks on top of 1.1. The model + UI are almost a copy of the crumb diagnostic; the differences are the prompt and the action enum.

### 1.3 Recipe import — structural pass

The audit on six real recipes showed:
- `breadType` always hardcoded `.sourdough` ([`RecipeImporter.swift:251`](GeekBread/Shared/RecipeImporter.swift:251))
- `preferments` always empty ([`RecipeImporter.swift:264`](GeekBread/Shared/RecipeImporter.swift:264)) even when source HTML has "Poolish:" / "Levain:" / "Tangzhong:" sections
- Stage classification keyword-only — "Place in oven" becomes `.bake` for preheat; "Let it rise" becomes `.bulk` even when it's the final proof; score/slash/boil/store all fall through to `.mix`
- `temperatureC` always nil even when text says "450°F"
- `totalFolds` never set even when text says "6 sets of stretch and folds"
- Non-ingredient lines ("all of the poolish", "egg wash: …", "2 quarts water for boiling") get added as ingredient rows

The existing [`AIRecipeAssist`](GeekBread/Shared/AIRecipeAssist.swift) Apple Foundation Models pass fixes *row-level* gaps (weightGrams=0, durationMin=0). It cannot fix the structural ones — by design it's prompted single-row, and the on-device model is too small for holistic reasoning.

**Touches:**

- **New** `GeekBread/Shared/RemoteRecipeAssist.swift` — public surface mirrors `AIRecipeAssist`: `static func apply(to imported: ImportedRecipe, rawHTML: String?) async -> ImportedRecipe`. Sends the deterministic draft + the JSON-LD payload + (optionally) extracted HTML fragments around section headers ("Poolish:", "For the dough:", "For the levain:") to Haiku with a structured-output schema matching `Recipe`. Returns a corrected `ImportedRecipe` with warnings tagged "Cloud AI corrected ingredients sectioning into preferments — verify before baking", "Cloud AI inferred bread type as `.enriched` — confirm", etc.
- **Modified** [`GeekBread/Features/Library/RecipeEditorScreen.swift:353`](GeekBread/Features/Library/RecipeEditorScreen.swift:353) — after the existing `applyAIAssist` call:
  ```swift
  if state.cloudAIEnabled {
      imported = await RemoteRecipeAssist.apply(to: imported, rawHTML: html)
  }
  ```
  The existing warnings UI in [`RecipeEditorScreen.swift:290–308`](GeekBread/Features/Library/RecipeEditorScreen.swift:290) already handles the tagged-warning pattern.
- **Modified** [`GeekBread/Shared/RecipeImporter.swift`](GeekBread/Shared/RecipeImporter.swift) — `import(from:)` needs to additionally return the raw HTML alongside the dict so the remote pass can reference section headers the JSON-LD flattened. Small signature change: returns `(ImportedRecipe, rawHTML: String)` and the editor threads `rawHTML` into the remote call.
- **No model changes.** `Recipe`, `Preferment`, `Stage`, `Ingredient` are all already-correct types — the remote pass just populates them better than the deterministic + on-device passes do.

**Effort:** 1–2 weeks. The schema is exactly the existing `Recipe` Codable; most of the work is the system prompt and a small eval harness across the seven seeded linked recipes.

---

## Tier 2 — high value, more product design needed

The next three surfaces. Each reuses `RemoteAIClient` from Tier 1 — incremental work, not green-field.

### 2.1 Pre-bake photo checks

Spec §4.5 lists "mixed dough", "during bulk", "pre-shape / final proof", "crust" as core diagnostic surfaces alongside crumb. Today's [`ActiveBakeScreen`](GeekBread/Features/ActiveBake/ActiveBakeScreen.swift) has photo-per-stage capture already (the [`plan.md:125`](plan.md:125) reference to `ActiveBake.stagePhotos`), but those photos go nowhere — they're not analyzed.

**Touches:**

- **Reuses** `CrumbDiagnosis` from 1.1 with a different prompt + label set per stage kind. Sketch: `StageDiagnosis.assess(image: UIImage, stage: Stage, context: BakeContext)` switches the system prompt on `stage.kind` (.bulkFold gets a gluten-development prompt; .finalProof gets a "poke-test from a photo" prompt; .bake gets a crust prompt).
- **Modified** `GeekBread/Features/ActiveBake/ActiveBakeScreen.swift` — each stage's photo capture gets a "Check this stage" CTA underneath. Tap → spinner → small inline diagnosis card. Mirrors the [`DiagnosticScreen`](GeekBread/Features/Diagnostic/DiagnosticScreen.swift) result-card layout.
- **Models** — `BakePhoto` (already exists per [`plan.md:205`](plan.md:205)) gains an optional `stageDiagnosis: StageDiagnosis?` field so the per-stage assessment persists with the bake.

**Effort:** 1 week after 1.1 lands. Mostly prompt-per-stage work + a small UI for the inline check.

### 2.2 OCR recipe import

Apple Vision's `VNRecognizeTextRequest` runs on-device for free and is reliable — but the OCR output is noisy text, not structured Recipe data. Haiku is the natural bridge.

**Touches:**

- **New** `GeekBread/Shared/RecipeOCR.swift` — `extractText(from: UIImage) async -> String?` wrapping `VNRecognizeTextRequest`.
- **Reuses** `RemoteRecipeAssist` from 1.3 (generalized — takes raw text instead of HTML).
- **Modified** [`GeekBread/Features/Library/RecipeEditorScreen.swift`](GeekBread/Features/Library/RecipeEditorScreen.swift) — adds a "Scan recipe" entry point alongside the existing Paste-URL and Choose-Photo paths. The photo flow already exists at [`RecipeEditorScreen.swift:204–246`](GeekBread/Features/Library/RecipeEditorScreen.swift:204).
- **Modified** `GeekBread/Models/Recipe.swift` — `RecipeSource.photoScanned(label: String)` already exists at line 30; the OCR path sets the source to this case so the recipe-detail surface shows "Scanned from photo" rather than a fake URL.

**Effort:** 1–2 weeks. The OCR call is small; most of the time is on prompt robustness across messy cookbook page layouts (two-column, ingredient sidebars, recipe-on-an-angle).

### 2.3 Conversational recipe Q&A

Spec §5.1 lists "Recipe Q&A and explanations" as an on-device target. Haiku is a more honest implementation than the on-device 3B-param target would be — questions about technique, substitutions, "why does this recipe call for autolyse" are open-ended and benefit from a frontier model.

**Touches:**

- **New** `GeekBread/Shared/RecipeChat.swift` — `ask(question: String, recipe: Recipe, history: [Message]) async -> String`. System prompt carries the full Recipe as context. Conversation history in-session only, no persistence in v1.
- **New** `GeekBread/Features/Library/RecipeChatSheet.swift` — sheet presented from the recipe-detail screen. Standard chat UI: scrolling message list, text input at the bottom.
- **Modified** [`GeekBread/Features/Library/RecipeDetailScreen.swift`](GeekBread/Features/Library/RecipeDetailScreen.swift) — adds an "Ask about this recipe" button in the toolbar or hero area.

**Effort:** 1–2 weeks. Most of the time is chat-UI polish; the model call itself is a few dozen lines.

---

## Tier 3 — defer until Tier 1 + 2 prove value

Items worth flagging in the roadmap but not worth shipping until the foundation is paying off.

### 3.1 Free-text recipe import
Paste a recipe from Reddit, Notes, a Discord message, anywhere. **Reuses** `RemoteRecipeAssist` (generalized to take raw text). **Touches** [`RecipeEditorScreen.swift`](GeekBread/Features/Library/RecipeEditorScreen.swift) — adds "Paste text" alongside "Paste URL". Low effort once 1.3 ships; the question is whether enough users want it to justify the surface.

### 3.2 Journal pattern-recognition explanations
Spec §4.6 examples: "Your last 5 country bakes: 4 underproofed, 1 perfect — the perfect one had a 5h45m bulk." **Pattern detection should stay deterministic** — a new `GeekBread/Shared/JournalPatterns.swift` does the stats (averages, correlations across recipes). Haiku writes the natural-language summary on top of the structured output. **Touches** [`GeekBread/Features/Home/HomeScreen.swift:353`](GeekBread/Features/Home/HomeScreen.swift:353) (`InsightsStrip`) — the strip is currently fed by `state.insights` which appears to be stubbed; this replaces the stub.

### 3.3 Recipe variation generation
"Add 20% whole rye", "halve this but keep the levain ratio", "make a multigrain version", "convert to gluten-free". Existing [`Conversion.swift`](GeekBread/Core/Conversion.swift) covers the deterministic conversions (yeasted → sourdough, add tangzhong, add yudane) — Haiku covers free-form variations. **Touches** [`RecipeDetailScreen.swift`](GeekBread/Features/Library/RecipeDetailScreen.swift) — new "Generate variation" CTA. **Risk:** correctness. Surface as "draft for your review, do not bake without checking" not as a one-tap operation. Gluten-free conversion is the hardest case and should be explicitly out of scope for v1.

### 3.4 Onboarding intake
[`OnboardingScreen.swift`](GeekBread/Features/Onboarding/OnboardingScreen.swift) could collapse a multi-page intake into a free-text "tell me about your kitchen and what you bake" step processed by Haiku into initial preferences (units, kitchen temperature default, starter age, experience level). Low risk, modest value. Probably not worth shipping in v1 — the existing structured onboarding is already short.

---

## Don't use Haiku for these

Listed for completeness so future contributors don't ask:

- **Baker's-percent math, Q10 scheduling, hydration normalization, preferment flour-share math.** [`BakersMath`](GeekBread/Core) and [`Scheduler`](GeekBread/Core/Scheduler.swift) are deterministic, tested, and correct. AI here introduces nondeterminism with no upside.
- **Notification grouping, Sidekick BLE protocol, iCloud sync, Live Activities.** No language surface.
- **YouTube video → recipe** (mentioned in spec §4.2). The signal in YouTube descriptions/transcripts is too thin and inconsistent for a good user experience. Skip or defer indefinitely.

---

## Cross-cutting decisions

Six call sites (Tier 1 + Tier 2 + Tier 3.1) means these decisions should be made once, up front.

### API key strategy
Three real options:

1. **BYOK** — user pastes their own Anthropic API key in Settings. No operating cost. Trivial to ship. Friction: users have to create an account at console.anthropic.com.
2. **Backend proxy** — we run a thin proxy and charge Pro subscribers $30/yr (the existing [`Stage 23 Pro tier`](plan.md:2701) price). Covers operating cost at modest usage. Adds backend infrastructure to the project.
3. **Hybrid** — Pro subscribers go through the proxy; free-tier users can BYOK to unlock the same features without subscribing. Most flexible; aligns with the spec's existing free/Pro split.

**Recommendation:** start with BYOK to ship Tier 1 fast without backend work, add the hybrid proxy when Stage 23 stands up.

### Single shared client
`GeekBread/Shared/RemoteAIClient.swift` is the only file that knows about the Anthropic SDK or HTTP requests. Every Tier 1 + Tier 2 + Tier 3 feature builds on top:

```swift
enum RemoteAIClient {
    static func generate<Output: Decodable>(
        prompt: String,
        images: [UIImage] = [],
        outputSchema: Output.Type
    ) async throws -> Output
}
```

Avoids each feature growing its own networking + retry + cancellation code. Tests can mock this one type and exercise every feature deterministically.

### Single toggle, not many
One Settings option ("Cloud AI features — uses Anthropic Claude · explainer link") gates all six call sites at once. Avoids the "Settings has eight AI toggles" failure mode and gives users one decision. The explainer link expands a sheet listing exactly which features the toggle enables and what data each one sends.

### Honest fallback contract
Every Haiku-powered feature ships with a deterministic / on-device fallback path the UI degrades to on network failure, opt-out, or low-confidence. The fallback contract:

| Surface | Fallback when remote unavailable |
| --- | --- |
| 1.1 Crumb diagnostic | Stage 24a similarity card |
| 1.2 Starter health | Rule-based ("last fed 6h ago at 24°C → likely peak now"). The card surfaces "unknown" rather than guessing. |
| 1.3 Recipe import | The existing deterministic + Apple Foundation Models pipeline; warnings just stay tagged as "deterministic" instead of "cloud-corrected" |
| 2.1 Pre-bake checks | CTA hides |
| 2.2 OCR import | OCR'd text goes into a free-text editor field for the user to clean up by hand |
| 2.3 Recipe Q&A | Sheet hides |

The default failure mode is **never** a fake response. A diagnosis the model didn't actually make is worse than no diagnosis.

### Privacy posture per surface
Each call site states in one line what data leaves the device. Surfaced both in Settings (the explainer sheet) and in the surface itself (a small caption below the result card on first use):

| Surface | Data sent |
| --- | --- |
| 1.1 Crumb diagnostic | Crumb photo + bake context (hydration%, bulk hours, ambient temp, retard hours). No recipe title, no user identifier. |
| 1.2 Starter health | Starter photo + structured starter context (hours since feed, kitchen temp, storage). No recipe title, no user identifier. |
| 1.3 Recipe import | The publicly-fetched recipe page's JSON-LD + HTML fragments. No user data. |
| 2.1 Pre-bake checks | Stage photo + the stage's recipe context. Same as 1.1. |
| 2.2 OCR import | The OCR'd text of the user's photographed page. No metadata. |
| 2.3 Recipe Q&A | The recipe text + the user's question. No journal data unless the user explicitly asks about a past bake. |
| 3.1 Free-text import | The user-pasted text. |
| 3.2 Journal patterns | Structured journal summary (counts, averages, recipe IDs). No photos. |

Anthropic's zero-data-retention setting is named in the explainer so users know the constraint.

### Versioning
Pin the model version (`claude-haiku-4-5-20251001`) at the API call site, not as a global. Lets each surface upgrade independently with its own eval-set regression check. Upgrades behind a feature flag, with rollback if the eval set regresses.

---

## Sequencing

A realistic order assuming one engineer:

1. **Cross-cutting plumbing** — `RemoteAIClient.swift` + the Settings toggle. 1 week.
2. **Tier 1.3 (recipe import)** — smallest scope, no new UI, immediate value, easy to eval against the seven seeded linked recipes. 1–2 weeks.
3. **Tier 1.1 (crumb diagnostic)** — the headline feature; opens Stage 24 to a real implementation. 3–4 weeks (most of which is prompt + eval against the team's own journal photos).
4. **Tier 1.2 (starter health)** — copy of 1.1's plumbing with a different prompt. 1–2 weeks.
5. **Tier 2.1 (pre-bake checks)** — extension of 1.1 with per-stage prompts. 1 week.
6. **Tier 2.2 (OCR import)** — natural follow-on to 1.3. 1–2 weeks.
7. **Tier 2.3 (recipe Q&A)** — new UI surface; ship after the diagnostics prove value. 1–2 weeks.

Total to ship Tier 1: **6–9 weeks** for one engineer, vs. 4–6 months for the original on-device VLM plan.

If Tier 1 ships and users actually use it, Tier 2 + 3 follow naturally on the same scaffolding. If users don't engage with Tier 1, Tier 2 + 3 are also wrong — the project's stuck and that's good information.
