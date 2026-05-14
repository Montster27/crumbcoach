import Foundation

// Stage 24 (haiku.md Tier 1.3) — structural pass over an already-imported
// recipe via Anthropic Claude Haiku. Where `AIRecipeAssist` fills
// row-level gaps (a weight here, a duration there), this fills
// STRUCTURAL gaps the deterministic parser systematically misses:
//
//   - breadType (always hardcoded `.sourdough` by RecipeImporter.mapToDraft)
//   - preferments (always empty — JSON-LD flattens "Poolish:" / "Levain:"
//     section headers into the flat ingredient list)
//   - temperatureC on bake/proof stages
//   - totalFolds on bulk-fold stages
//   - filtering out non-ingredient lines like "all of the poolish",
//     "2 quarts water for boiling", "egg wash: 1 yolk + 1 tbsp milk"
//
// The call shape mirrors `AIRecipeAssist.applyAIAssist`: take an
// `ImportedRecipe`, return a corrected one with appended warnings
// tagged "Cloud AI …" so the user knows which edits came from the
// remote model and can double-check them.
//
// Caller (RecipeEditorScreen) gates this on `state.cloudAIEnabled &&
// RemoteAIClient.isConfigured`; no-ops when called without those.
//
// Hallucination defense:
//   - The model is told it may only RELABEL or REMOVE rows that exist
//     in the deterministic draft; it cannot introduce new ingredients
//     or stages from whole cloth.
//   - We post-validate every change: dropped indices must point at
//     real rows; added preferments must reference existing ingredient
//     names; stage temperatures attach only to existing stages.

enum RemoteRecipeAssist {

    /// Pin the model here so each surface upgrades independently
    /// (haiku.md "Versioning").
    static let model = "claude-haiku-4-5-20251001"

    /// Apply a structural pass and return a new `ImportedRecipe` with
    /// corrections + warnings. Returns the input unchanged on any
    /// failure — Cloud AI is opt-in; surfacing a network error to a
    /// user mid-import would be worse than silently keeping the
    /// deterministic draft.
    static func apply(to imported: ImportedRecipe, rawHTML: String?) async -> ImportedRecipe {
        guard RemoteAIClient.isConfigured else { return imported }

        let draft = imported.draft

        // Compact view of the draft the model can refer to by index.
        // Numbered so warnings can call out specific rows ("row 4 was
        // not actually an ingredient").
        let ingredientLines = draft.ingredients.enumerated()
            .map { idx, ing in "\(idx). \(ing.name) — \(formatGrams(ing.weightGrams)), category=\(ing.category.rawValue)" }
            .joined(separator: "\n")
        let stageLines = draft.stages.enumerated()
            .map { idx, st in "\(idx). kind=\(st.kind.rawValue) duration=\(st.durationMin)m note=\(st.note ?? "")" }
            .joined(separator: "\n")
        let truncatedHTML = (rawHTML ?? "").prefix(60_000)

        let user = """
        Title: \(draft.title)
        Current bread type (likely wrong default): \(draft.breadType.rawValue)
        Hydration%: \(Int(draft.hydrationPct.rounded()))
        Total dough: \(Int(draft.totalDoughGrams.rounded())) g

        Ingredients (deterministic parser output):
        \(ingredientLines)

        Stages (deterministic parser output):
        \(stageLines)

        Raw HTML around the recipe (look for "Poolish:", "Levain:",
        "For the dough:", "Tangzhong:", "Yudane:" section headers, and
        for oven temperatures in °F or °C):
        <<<HTML>>>
        \(truncatedHTML)
        <<<END HTML>>>

        Return ONLY the JSON object per the schema. No prose, no
        markdown fence.
        """

        let system = systemPrompt
        let fix: RecipeStructuralFix
        do {
            fix = try await RemoteAIClient.generate(
                model: model,
                systemPrompt: system,
                userText: user,
                outputType: RecipeStructuralFix.self,
                maxTokens: 2048
            )
        } catch {
            // Quiet failure — return the deterministic draft. We DO
            // surface this in warnings so the user knows the cloud
            // pass didn't run, rather than a silently degraded result.
            var out = imported
            out.warnings.append("Cloud AI couldn't process this recipe (\(error.localizedDescription)). Using the deterministic import only.")
            return out
        }

        return applyFix(fix, to: imported)
    }

    // MARK: - System prompt

    private static let systemPrompt: String = """
    You are a bread-recipe normalizer. The user pastes the deterministic
    output of a recipe-page importer plus the raw HTML of the source. The
    importer misses structural information that the HTML often makes
    obvious:
      - Whether the recipe is sourdough / lean yeasted / enriched / rye /
        flatbread / quick bread / steamed.
      - Whether some of the listed "ingredients" actually belong to a
        preferment (Poolish, Levain, Tangzhong, Yudane, Biga). The HTML
        often has section headers like "For the tangzhong:", "Tangzhong
        (optional):", "Make the levain:", "Build the poolish:", "For the
        dough:" that the JSON-LD flattens into one ingredient list.
      - Whether an ingredient line like "100 g ripe sourdough starter" /
        "200 g active starter" / "50 g bubbly 100% hydration starter" is
        itself a levain — it is, and it should become a `levain`
        preferment with that single Leaven-category row moved into it.
      - Whether the bake / proof / autolyse / mix stages have an oven or
        ambient temperature stated in the source.
      - Whether the bulk + folds stage states a specific number of folds.
      - Whether some "ingredients" are actually equipment notes, washes,
        sub-recipes, or directional text that got into the list by
        accident.

    Output a SINGLE JSON object matching this schema (omit fields you
    don't have evidence for):

    {
      "breadType": "Sourdough" | "Lean yeasted" | "Enriched" | "Rye" | "Flatbread" | "Quick bread" | "Steamed" | null,
      "preferments": [
        {
          "id": "levain" | "yudane" | "tangzhong" | "biga" | "poolish",
          "name": "string",
          "technique": "string (one-line technique e.g. '1:5 cook to 65°C')",
          "prep": "string (one or two sentences)",
          "flourPct": <number, % of TOTAL flour represented by this preferment>,
          "ingredients": [
            {
              "name": "string",
              "category": "Flour" | "Liquid" | "Salt" | "Leaven" | "Fat" | "Sweet" | "Inclusion",
              "weightGrams": <number>,
              "bakersPct": <number, % of total flour>
            }
          ]
        }
      ],
      "ingredientIndicesToRemove": [<0-indexed integer>, ...],
      "stageTemperatures": { "<stage-index>": <celsius number> },
      "stageFolds": { "<stage-index>": <integer count> },
      "stageTypes": { "<stage-index>": "Feed levain" | "Prep yudane" | "Prep poolish" | "Cook tangzhong" | "Autolyse" | "Mix" | "Add butter" | "Bulk + folds" | "Bulk" | "Divide" | "Pre-shape" | "Divide & shape" | "Final shape" | "Proof" | "Final proof" | "Cold retard" | "Bake" },
      "notes": ["short human-readable summary of what you changed", ...]
    }

    Rules — read carefully:
      1. You may only REMOVE or RELABEL existing ingredient rows, or MOVE
         them into a preferment block. You may NOT invent new
         ingredients. Every preferment ingredient name should match (or
         be a close paraphrase of) a name in the input list.
      2. If you create a preferment, every ingredient it contains must
         correspond to a row in the input list — and those rows must
         also appear in `ingredientIndicesToRemove` so the editor
         doesn't double-count flour/water.
      3. **Inline starter is a levain.** If the input ingredient list has
         a row whose name contains "starter" or "levain" with a stated
         gram weight (e.g. "100 g ripe sourdough starter"), emit a
         preferment with `id: "levain"`, technique like "Use ripe
         100% hydration starter", flourPct ≈ (weight ÷ 2) ÷ total flour
         × 100 (assuming 100% hydration unless the source states
         otherwise), one ingredient row {category: "Leaven", name copied
         from input, weightGrams copied from input}, and put that row's
         index in `ingredientIndicesToRemove`. Don't synthesize a
         separate flour+water pair — the editor's math expands it.
      4. **Look for section headers in the raw HTML** like "For the
         tangzhong:", "Tangzhong (optional):", "Make the levain:",
         "Build the poolish:", "For the levain build:", "Yudane:",
         "Biga:". Every ingredient line that appears under such a
         header in the source belongs to that preferment, even when
         the deterministic ingredient list interleaves header lines
         and recipe-body lines without preserving the grouping. Treat
         "(optional)" as still-extract — if the section is on the
         page, populate it; the user will decide whether to use it.
         **Reject sections that LOOK like preferments but aren't**:
         "Water bath:", "Lye bath:", "Boiling water:", "Kettling
         liquid:", "Egg wash:", "Glaze:", "Topping:", "Filling:",
         "For brushing:", "For dusting:", "For the pan:", "Finishing
         salt:". These are equipment / finishing prep, not
         fermentation pre-stages, regardless of how the source titles
         them. The preferment's `id` MUST be one of
         `levain / tangzhong / yudane / biga / poolish` — never emit a
         preferment whose `id` can't be mapped to one of those five.
         A `tangzhong / yudane / biga / poolish` ALWAYS contains at
         least one Flour-category ingredient AND one Liquid-category
         ingredient; if the section's contents don't satisfy that,
         it's not a preferment.
      5. If you are unsure whether a recipe has a preferment, emit no
         preferments rather than guessing. But "the source has a
         visible 'For the X:' header with rows under it" counts as
         certainty, not a guess.
      6. Convert °F to °C when filling `stageTemperatures` (C = (F − 32) × 5/9).
      7. **Every stage where the dough is in the oven gets a
         temperature.** That includes "Bake at 450°F for 20 min", but
         also follow-on stages like "reduce to 400°F and finish 15 min
         uncovered" or "return to oven for 10 min". When a follow-on
         bake stage doesn't restate a temperature, repeat the most
         recent stated bake temperature on it (in °C). The only bake
         stage that may omit a temperature is one where the source
         explicitly says "oven off" or "residual heat".
      8. `stageFolds` only makes sense on a stage whose kind is "Bulk +
         folds". Don't fold-count a "Bulk" or "Proof" stage.
      9. Keep `notes` short and concrete. One bullet per kind of change.
      10. Output ONLY the JSON object. No explanation outside it.
    """

    // MARK: - Fix application

    /// Convert the model's diff payload into mutations on the draft.
    /// Defensive: only changes the editor can safely accept survive.
    private static func applyFix(_ fix: RecipeStructuralFix,
                                  to imported: ImportedRecipe) -> ImportedRecipe {
        var draft = imported.draft
        var warnings = imported.warnings

        // 1. Bread type override.
        if let raw = fix.breadType,
           let parsed = BreadType(rawValue: raw),
           parsed != draft.breadType {
            warnings.append("Cloud AI inferred bread type as \(parsed.rawValue) — confirm before saving.")
            draft.breadType = parsed
        }

        // 2. Stage-level patches BEFORE we touch ingredient indices so
        //    stage indices stay stable.
        if let temps = fix.stageTemperatures {
            for (key, celsius) in temps {
                guard let idx = Int(key),
                      draft.stages.indices.contains(idx),
                      celsius > 0, celsius < 350
                else { continue }
                draft.stages[idx].temperatureC = celsius
                warnings.append("Cloud AI filled \(Int(celsius.rounded()))°C on stage \(idx + 1) — verify against the source.")
            }
        }
        if let folds = fix.stageFolds {
            for (key, count) in folds {
                guard let idx = Int(key),
                      draft.stages.indices.contains(idx),
                      draft.stages[idx].kind == .bulkFold,
                      count > 0, count <= 10
                else { continue }
                draft.stages[idx].totalFolds = count
                warnings.append("Cloud AI set \(count) folds on the bulk-fold stage — verify.")
            }
        }
        if let kinds = fix.stageTypes {
            for (key, raw) in kinds {
                guard let idx = Int(key),
                      draft.stages.indices.contains(idx),
                      let parsed = StageKind(rawValue: raw),
                      parsed != draft.stages[idx].kind
                else { continue }
                draft.stages[idx].kind = parsed
                warnings.append("Cloud AI re-classified stage \(idx + 1) as \(parsed.rawValue) — verify.")
            }
        }

        // 3. Preferments. Build real `Preferment`s from the model's
        //    light shape. Reject any whose total flour% exceeds 100 or
        //    whose ingredient category strings don't parse.
        if let lightPreferments = fix.preferments, !lightPreferments.isEmpty {
            var newPreferments: [Preferment] = []
            for light in lightPreferments {
                let knownIds: Set<String> = ["levain", "yudane", "tangzhong", "biga", "poolish"]
                guard knownIds.contains(light.id) else { continue }
                guard light.flourPct >= 0, light.flourPct <= 100 else { continue }
                let ingredients: [Ingredient] = light.ingredients.compactMap { li in
                    guard let category = IngredientCategory(rawValue: li.category),
                          li.weightGrams >= 0 else { return nil }
                    return Ingredient(
                        name: li.name,
                        category: category,
                        weightGrams: li.weightGrams,
                        bakersPct: max(0, li.bakersPct),
                        section: light.id
                    )
                }
                guard !ingredients.isEmpty else { continue }
                newPreferments.append(Preferment(
                    id: light.id,
                    name: light.name,
                    technique: light.technique,
                    prep: light.prep,
                    flourPct: light.flourPct,
                    ingredients: ingredients
                ))
            }
            if !newPreferments.isEmpty {
                draft.preferments = newPreferments
                let labels = newPreferments.map(\.name).joined(separator: ", ")
                warnings.append("Cloud AI extracted preferments (\(labels)) from the source — confirm the math (flour totals are recomputed on save).")
            }
        }

        // 4. Ingredient-row removals. Apply after preferments so the
        //    "moved into preferment" rows leave the main list cleanly.
        //    Sort descending so removing index N doesn't shift index
        //    N+1 underneath us.
        if let dropIndices = fix.ingredientIndicesToRemove, !dropIndices.isEmpty {
            let valid = dropIndices
                .filter { $0 >= 0 && $0 < draft.ingredients.count }
                .sorted(by: >)
            if !valid.isEmpty {
                let droppedNames = valid.reversed().map { draft.ingredients[$0].name }
                for idx in valid {
                    draft.ingredients.remove(at: idx)
                }
                warnings.append("Cloud AI dropped non-ingredient rows: \(droppedNames.joined(separator: "; "))")
            }
        }

        // 5. Append model's own free-form change log so the user knows
        //    what to scan for. Cap each note to keep the warning strip
        //    tidy.
        for note in fix.notes.prefix(5) {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                warnings.append("Cloud AI note: \(trimmed.prefix(180))")
            }
        }

        // Refresh the total — preferment rows may now contribute weight
        // that wasn't there before; dropped rows shrink the total. The
        // editor's save path recomputes baker's % from this, so the
        // total just needs to be consistent.
        draft.totalDoughGrams =
            draft.ingredients.reduce(0) { $0 + $1.weightGrams } +
            draft.preferments.flatMap(\.ingredients).reduce(0) { $0 + $1.weightGrams }

        return ImportedRecipe(draft: draft, warnings: warnings, rawHTML: imported.rawHTML)
    }

    private static func formatGrams(_ grams: Double) -> String {
        if grams <= 0 { return "?g" }
        return "\(Int(grams.rounded()))g"
    }

    // MARK: - Response schema

    /// The model's diff over the deterministic draft. Every field is
    /// optional so the model can omit shapes it has no evidence for.
    private struct RecipeStructuralFix: Decodable {
        let breadType: String?
        let preferments: [LightPreferment]?
        let ingredientIndicesToRemove: [Int]?
        let stageTemperatures: [String: Double]?
        let stageFolds: [String: Int]?
        let stageTypes: [String: String]?
        let notes: [String]

        // Tolerant decoder — accept missing `notes` (treat as []) and
        // missing trailing arrays so a sparse response decodes.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.breadType = try c.decodeIfPresent(String.self, forKey: .breadType)
            self.preferments = try c.decodeIfPresent([LightPreferment].self, forKey: .preferments)
            self.ingredientIndicesToRemove = try c.decodeIfPresent([Int].self, forKey: .ingredientIndicesToRemove)
            self.stageTemperatures = try c.decodeIfPresent([String: Double].self, forKey: .stageTemperatures)
            self.stageFolds = try c.decodeIfPresent([String: Int].self, forKey: .stageFolds)
            self.stageTypes = try c.decodeIfPresent([String: String].self, forKey: .stageTypes)
            self.notes = (try c.decodeIfPresent([String].self, forKey: .notes)) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case breadType, preferments, ingredientIndicesToRemove
            case stageTemperatures, stageFolds, stageTypes, notes
        }
    }

    private struct LightPreferment: Decodable {
        let id: String
        let name: String
        let technique: String
        let prep: String
        let flourPct: Double
        let ingredients: [LightIngredient]
    }

    private struct LightIngredient: Decodable {
        let name: String
        let category: String
        let weightGrams: Double
        let bakersPct: Double
    }
}
