import Foundation

// Recipe conversions: tangzhong / yudane / sourdough-from-yeasted.
// Algorithmic intent mirrors crumbcoach-core/conversion/* in the Rust spec.

enum Conversion {

    // MARK: Tangzhong (cooked roux pre-ferment)
    //
    // Take 5–8% of the main-dough flour, combine with liquid at a 1:5 flour:liquid
    // ratio, cook to ~65°C until pudding-thick. Add to main dough.
    // Boosts hydration capacity; recipe should be at >=65% target hydration.

    static func convertToTangzhong(_ recipe: Recipe,
                                   flourPctOfTotal: Double = 6,
                                   ratio: Double = 5) -> (Recipe, warning: String?) {
        let percentages = BakersMath.computePercentages(for: recipe)
        let totalFlour = percentages.totalFlourGrams
        guard totalFlour > 0 else { return (recipe, nil) }

        let tFlour = totalFlour * (flourPctOfTotal / 100.0)
        let tLiquid = tFlour * ratio

        // Choose the liquid for the tangzhong — prefer milk if present, else water.
        let mainLiquids = recipe.ingredients.filter { $0.category == .liquid }
        let liquidName = mainLiquids.first(where: { $0.name.lowercased().contains("milk") })?.name
            ?? mainLiquids.first?.name
            ?? "Water"

        // Subtract from main-dough flour + liquid
        let primaryFlour = recipe.ingredients.first(where: { $0.category == .flour })?.name ?? "Bread flour"

        var out = recipe

        // Find main-dough flour and liquid, subtract amounts
        if let idx = out.ingredients.firstIndex(where: { $0.category == .flour }) {
            out.ingredients[idx].weightGrams = max(0, out.ingredients[idx].weightGrams - tFlour)
            out.ingredients[idx].bakersPct = (out.ingredients[idx].weightGrams / totalFlour) * 100.0
        }
        if let idx = out.ingredients.firstIndex(where: { $0.category == .liquid }) {
            out.ingredients[idx].weightGrams = max(0, out.ingredients[idx].weightGrams - tLiquid)
            out.ingredients[idx].bakersPct = (out.ingredients[idx].weightGrams / totalFlour) * 100.0
        }

        // Add the tangzhong preferment
        let pf = Preferment(
            id: "tangzhong",
            name: "Tangzhong",
            technique: "1:\(Int(ratio)) cook to 65°C",
            prep: "Whisk \(primaryFlour) + \(liquidName.lowercased()) in a saucepan over medium heat to 65°C until pudding-thick. Cool to room temp before adding.",
            flourPct: flourPctOfTotal,
            ingredients: [
                Ingredient(name: primaryFlour, category: .flour,  weightGrams: round(tFlour),  bakersPct: flourPctOfTotal, section: "tangzhong"),
                Ingredient(name: liquidName,   category: .liquid, weightGrams: round(tLiquid), bakersPct: flourPctOfTotal * ratio, section: "tangzhong"),
            ]
        )
        if let idx = out.preferments.firstIndex(where: { $0.id == "tangzhong" }) {
            out.preferments[idx] = pf
        } else {
            out.preferments.append(pf)
        }

        // Add a "Cook tangzhong" stage at the front if not already present
        if !out.stages.contains(where: { $0.kind == .cookTangzhong }) {
            out.stages.insert(
                Stage(kind: .cookTangzhong, durationMin: 15, temperatureC: 65,
                      note: "Whisk flour + liquid to 65°C, cool to room temp",
                      scaldRef: "tangzhong"),
                at: 0
            )
        }

        let warning: String? = recipe.hydrationPct < 65
            ? "Recipe hydration is low — tangzhong is best at ≥65%. Consider raising hydration first."
            : nil

        return (out, warning)
    }

    // MARK: Yudane (cold-soaked scald)
    //
    // 1:1 flour:boiling-water, rest 8–12h. Use 15–25% of total flour.

    static func convertToYudane(_ recipe: Recipe,
                                flourPctOfTotal: Double = 20) -> (Recipe, warning: String?) {
        let percentages = BakersMath.computePercentages(for: recipe)
        let totalFlour = percentages.totalFlourGrams
        guard totalFlour > 0 else { return (recipe, nil) }

        let yFlour = totalFlour * (flourPctOfTotal / 100.0)
        let yWater = yFlour    // 1:1

        let primaryFlour = recipe.ingredients.first(where: { $0.category == .flour })?.name ?? "Bread flour"

        var out = recipe
        if let idx = out.ingredients.firstIndex(where: { $0.category == .flour }) {
            out.ingredients[idx].weightGrams = max(0, out.ingredients[idx].weightGrams - yFlour)
            out.ingredients[idx].bakersPct = (out.ingredients[idx].weightGrams / totalFlour) * 100.0
        }
        if let idx = out.ingredients.firstIndex(where: { $0.category == .liquid }) {
            out.ingredients[idx].weightGrams = max(0, out.ingredients[idx].weightGrams - yWater)
            out.ingredients[idx].bakersPct = (out.ingredients[idx].weightGrams / totalFlour) * 100.0
        }

        let pf = Preferment(
            id: "yudane",
            name: "Yudane",
            technique: "1:1 scald · rest 12h",
            prep: "Pour boiling water over flour, mix to a paste, cover, rest overnight (≥8h) in fridge.",
            flourPct: flourPctOfTotal,
            ingredients: [
                Ingredient(name: primaryFlour,      category: .flour,  weightGrams: round(yFlour), bakersPct: flourPctOfTotal, section: "yudane"),
                Ingredient(name: "Boiling water",   category: .liquid, weightGrams: round(yWater), bakersPct: flourPctOfTotal, section: "yudane"),
            ]
        )
        if let idx = out.preferments.firstIndex(where: { $0.id == "yudane" }) {
            out.preferments[idx] = pf
        } else {
            out.preferments.append(pf)
        }
        if !out.stages.contains(where: { $0.kind == .prepYudane }) {
            out.stages.insert(
                Stage(kind: .prepYudane, durationMin: 720, temperatureC: 4,
                      note: "Scald, mix, cover, rest in fridge overnight",
                      scaldRef: "yudane"),
                at: 0
            )
        }

        return (out, nil)
    }

    // MARK: Yeasted → sourdough
    //
    // Replace commercial yeast with 20% levain at 100% hydration. Adjust the
    // main-dough flour and liquid to compensate.

    static func yeastedToSourdough(_ recipe: Recipe,
                                   levainPct: Double = 20,
                                   levainHydrationPct: Double = 100) -> Recipe {
        let percentages = BakersMath.computePercentages(for: recipe)
        let totalFlour = percentages.totalFlourGrams
        guard totalFlour > 0 else { return recipe }

        let levainTotal = totalFlour * (levainPct / 100.0)
        // levain hydration is liquid/flour, so flour share = total / (1 + hyd/100)
        let levainFlour = levainTotal / (1 + levainHydrationPct / 100.0)
        let levainLiquid = levainTotal - levainFlour

        var out = recipe
        // Remove all leaven entries (commercial yeast)
        out.ingredients.removeAll { $0.category == .leaven }

        // Subtract levain's flour + liquid from main dough
        if let idx = out.ingredients.firstIndex(where: { $0.category == .flour }) {
            out.ingredients[idx].weightGrams = max(0, out.ingredients[idx].weightGrams - levainFlour)
            out.ingredients[idx].bakersPct = (out.ingredients[idx].weightGrams / totalFlour) * 100.0
        }
        if let idx = out.ingredients.firstIndex(where: { $0.category == .liquid }) {
            out.ingredients[idx].weightGrams = max(0, out.ingredients[idx].weightGrams - levainLiquid)
            out.ingredients[idx].bakersPct = (out.ingredients[idx].weightGrams / totalFlour) * 100.0
        }

        // Add the levain as a leaven ingredient (treated as the active leavening agent)
        out.ingredients.append(
            Ingredient(name: "Levain (\(Int(levainHydrationPct))% hyd.)",
                       category: .leaven,
                       weightGrams: round(levainTotal),
                       bakersPct: levainPct)
        )

        out.breadType = .sourdough
        out.leavenPct = levainPct

        // Prepend a "Feed levain" stage
        if !out.stages.contains(where: { $0.kind == .feedLevain }) {
            out.stages.insert(
                Stage(kind: .feedLevain, durationMin: 360, temperatureC: 24,
                      note: "Build levain 6h ahead at 1:5:5 ratio"),
                at: 0
            )
        }
        return out
    }
}
