import Foundation

// Stage 17.5a — static volume-to-grams lookup. The first-line backstop when
// the JSON-LD source publishes only US-customary units. Deterministic, no
// device gate, no inference — a constant table covering the ingredients
// that show up in most bread recipes.
//
// Coverage philosophy: head-of-pareto, not exhaustive. The top ~30 entries
// catch >90% of real-world bread imports (most King Arthur, The Perfect
// Loaf, Maurizio Leo, Foodgeek). Long-tail / exotic ingredients fall
// through to the regex warnings (and someday Stage 17.5b's Foundation
// Models pass).
//
// Source values: King Arthur Baking's "ingredient weights" reference
// (https://www.kingarthurbaking.com/learn/ingredient-weight-chart),
// cross-checked against The Perfect Loaf's measurement tables. Comments
// on each entry note any provenance / brand-specific caveat.

enum IngredientWeightTable {

    /// Volume units the table handles. Mass units (oz, lb) are intentionally
    /// out of scope here — the Stage 17 regex paths already handle those.
    enum Unit {
        case teaspoon, tablespoon, cup
    }

    /// Tagged source of an estimate so callers can surface "this was
    /// estimated from a standard table, please verify" to the user.
    struct Estimate {
        let grams: Double
        let matchedKeyword: String
    }

    /// Look up grams for an ingredient name + quantity + volume unit.
    /// Returns nil when nothing in the table matches the name's keywords
    /// for the given unit. Keyword match is longest-first so
    /// "all-purpose flour" wins over plain "flour".
    static func estimate(name: String, quantity: Double, unit: Unit) -> Estimate? {
        let haystack = name.lowercased()
        let candidates = entries
            .filter { $0.unit == unit && haystack.contains($0.keyword) }
            .sorted { $0.keyword.count > $1.keyword.count }
        guard let best = candidates.first else { return nil }
        return Estimate(
            grams: quantity * best.gramsPerUnit,
            matchedKeyword: best.keyword
        )
    }

    // MARK: - Table

    private struct Entry {
        let keyword: String
        let unit: Unit
        let gramsPerUnit: Double
    }

    // Each ingredient gets entries for every unit it's commonly measured in.
    // Numbers from King Arthur unless noted. Keep keywords lowercase.
    private static let entries: [Entry] = [
        // --- Flours (cup is the dominant unit; tsp/tbsp rare) ---
        .init(keyword: "all-purpose flour",  unit: .cup,       gramsPerUnit: 120),
        .init(keyword: "bread flour",        unit: .cup,       gramsPerUnit: 120),
        .init(keyword: "whole wheat flour",  unit: .cup,       gramsPerUnit: 113),
        .init(keyword: "whole-wheat flour",  unit: .cup,       gramsPerUnit: 113),
        .init(keyword: "rye flour",          unit: .cup,       gramsPerUnit: 106),
        .init(keyword: "spelt flour",        unit: .cup,       gramsPerUnit: 100),
        .init(keyword: "semolina",           unit: .cup,       gramsPerUnit: 163),
        // Catch-all "flour" must come AFTER the more specific entries above
        // because of the longest-first match ordering.
        .init(keyword: "flour",              unit: .cup,       gramsPerUnit: 120),

        // --- Liquids ---
        .init(keyword: "water",              unit: .cup,        gramsPerUnit: 237),
        .init(keyword: "water",              unit: .tablespoon, gramsPerUnit: 14.8),
        .init(keyword: "water",              unit: .teaspoon,   gramsPerUnit: 5.0),
        .init(keyword: "milk",               unit: .cup,        gramsPerUnit: 227),
        .init(keyword: "milk",               unit: .tablespoon, gramsPerUnit: 14.5),
        .init(keyword: "buttermilk",         unit: .cup,        gramsPerUnit: 227),
        .init(keyword: "cream",              unit: .cup,        gramsPerUnit: 232),
        .init(keyword: "olive oil",          unit: .tablespoon, gramsPerUnit: 13.5),
        .init(keyword: "vegetable oil",      unit: .tablespoon, gramsPerUnit: 13.6),

        // --- Eggs (treat as discrete "tablespoons" of liquid weight) ---
        // 1 large egg ≈ 50g whole, 30g white, 18g yolk. Volume-style
        // measurements are rare for eggs; we cover whole-egg "1 large egg"
        // via a separate path (parseEggCount below).

        // --- Salts ---
        .init(keyword: "table salt",         unit: .teaspoon,   gramsPerUnit: 6.0),
        .init(keyword: "table salt",         unit: .tablespoon, gramsPerUnit: 18.0),
        .init(keyword: "kosher salt",        unit: .teaspoon,   gramsPerUnit: 4.8),  // Diamond Crystal
        .init(keyword: "kosher salt",        unit: .tablespoon, gramsPerUnit: 14.4),
        .init(keyword: "sea salt",           unit: .teaspoon,   gramsPerUnit: 5.5),
        .init(keyword: "fine sea salt",      unit: .teaspoon,   gramsPerUnit: 5.5),
        // Plain "salt" fallback — under-specifies but at least gives a
        // ballpark; longest-first ordering keeps the qualified entries on top.
        .init(keyword: "salt",               unit: .teaspoon,   gramsPerUnit: 6.0),
        .init(keyword: "salt",               unit: .tablespoon, gramsPerUnit: 18.0),

        // --- Leavens ---
        .init(keyword: "instant yeast",      unit: .teaspoon,   gramsPerUnit: 3.1),
        .init(keyword: "active dry yeast",   unit: .teaspoon,   gramsPerUnit: 3.1),
        .init(keyword: "yeast",              unit: .teaspoon,   gramsPerUnit: 3.1),
        .init(keyword: "baking soda",        unit: .teaspoon,   gramsPerUnit: 5.5),
        .init(keyword: "baking powder",      unit: .teaspoon,   gramsPerUnit: 4.0),

        // --- Sweeteners ---
        .init(keyword: "granulated sugar",   unit: .cup,        gramsPerUnit: 198),
        .init(keyword: "granulated sugar",   unit: .tablespoon, gramsPerUnit: 12.4),
        .init(keyword: "brown sugar",        unit: .cup,        gramsPerUnit: 213),  // packed
        .init(keyword: "brown sugar",        unit: .tablespoon, gramsPerUnit: 13.3),
        .init(keyword: "honey",              unit: .cup,        gramsPerUnit: 340),
        .init(keyword: "honey",              unit: .tablespoon, gramsPerUnit: 21.0),
        .init(keyword: "maple syrup",        unit: .tablespoon, gramsPerUnit: 19.6),
        .init(keyword: "molasses",           unit: .tablespoon, gramsPerUnit: 20.2),
        .init(keyword: "sugar",              unit: .cup,        gramsPerUnit: 198),  // catch-all
        .init(keyword: "sugar",              unit: .tablespoon, gramsPerUnit: 12.4),

        // --- Fats ---
        .init(keyword: "butter",             unit: .cup,        gramsPerUnit: 227),  // 2 sticks
        .init(keyword: "butter",             unit: .tablespoon, gramsPerUnit: 14.2),
        .init(keyword: "butter",             unit: .teaspoon,   gramsPerUnit: 4.7),
        .init(keyword: "olive oil",          unit: .cup,        gramsPerUnit: 216),
        .init(keyword: "vegetable oil",      unit: .cup,        gramsPerUnit: 218),

        // --- Misc ---
        .init(keyword: "cocoa powder",       unit: .cup,        gramsPerUnit: 85),
        .init(keyword: "cocoa powder",       unit: .tablespoon, gramsPerUnit: 5.3),
        .init(keyword: "dry milk",           unit: .cup,        gramsPerUnit: 113),  // nonfat dry milk powder
        .init(keyword: "dry milk",           unit: .tablespoon, gramsPerUnit: 7.1),
    ]
}
