import Foundation

// Baker's-percentage math.  Flour = 100%.  Every other ingredient is expressed
// as a percentage of total flour.  Hydration = water / flour.  Salt = salt /
// flour.  Pre-ferment flour counts toward total flour.
//
// Mirrors the algorithmic intent of crumbcoach-core/recipe/percentages.rs.

struct BakersPercentages: Hashable {
    var totalFlourGrams: Double
    var totalDoughGrams: Double
    var hydrationPct: Double
    var saltPct: Double
    var leavenPct: Double
    var fatPct: Double
    var sweetPct: Double
    var prefermentFlourPct: Double
}

/// Severity-graded message about a recipe transformation. Bakers want to know
/// when a change pushes the dough outside what the original recipe assumed.
enum HydrationWarning: Equatable {
    case none
    case higher  // bulk will run longer
    case lower   // expect tighter crumb

    var message: String? {
        switch self {
        case .none:   return nil
        case .higher: return "Higher hydration than recipe target — bulk will run longer."
        case .lower:  return "Drier than recipe target — expect tighter crumb."
        }
    }
}

enum BakersMath {
    /// Compute the baker's percentages for a recipe by summing across the main
    /// ingredients and any preferment sub-ingredients.
    static func computePercentages(for recipe: Recipe) -> BakersPercentages {
        var allIngredients: [Ingredient] = recipe.ingredients
        for pf in recipe.preferments {
            allIngredients.append(contentsOf: pf.ingredients)
        }

        let totalFlour = allIngredients
            .filter { $0.category == .flour }
            .reduce(0.0) { $0 + $1.weightGrams }
        let totalWeight = allIngredients.reduce(0.0) { $0 + $1.weightGrams }

        func sumPct(_ cat: IngredientCategory) -> Double {
            let w = allIngredients
                .filter { $0.category == cat }
                .reduce(0.0) { $0 + $1.weightGrams }
            return totalFlour > 0 ? (w / totalFlour) * 100.0 : 0
        }

        let prefermentFlour = recipe.preferments
            .flatMap(\.ingredients)
            .filter { $0.category == .flour }
            .reduce(0.0) { $0 + $1.weightGrams }

        return BakersPercentages(
            totalFlourGrams: totalFlour,
            totalDoughGrams: totalWeight,
            hydrationPct: sumPct(.liquid),
            saltPct: sumPct(.salt),
            leavenPct: sumPct(.leaven),
            fatPct: sumPct(.fat),
            sweetPct: sumPct(.sweet),
            prefermentFlourPct: totalFlour > 0 ? (prefermentFlour / totalFlour) * 100.0 : 0
        )
    }

    /// Re-scale a recipe's ingredient weights to a target total dough weight.
    /// Percentages stay constant; absolute grams change.
    static func scale(_ recipe: Recipe, toTotalGrams target: Double) -> Recipe {
        let current = recipe.ingredients.reduce(0.0) { $0 + $1.weightGrams }
            + recipe.preferments.flatMap(\.ingredients).reduce(0.0) { $0 + $1.weightGrams }
        guard current > 0 else { return recipe }
        let factor = target / current

        var out = recipe
        out.ingredients = out.ingredients.map { ing in
            var i = ing
            i.weightGrams = round(ing.weightGrams * factor)
            return i
        }
        out.preferments = out.preferments.map { pf in
            var p = pf
            p.ingredients = pf.ingredients.map {
                var i = $0
                i.weightGrams = round($0.weightGrams * factor)
                return i
            }
            return p
        }
        out.totalDoughGrams = round(target)
        return out
    }

    /// Adjust hydration: re-scale the main-dough liquid ingredients so the
    /// total liquid-to-flour ratio matches `newHydrationPct`. Preferment
    /// ratios are fixed (changing them turns a tangzhong into something else).
    static func adjustHydration(_ recipe: Recipe, to newHydrationPct: Double) -> Recipe {
        let percentages = computePercentages(for: recipe)
        let totalFlour = percentages.totalFlourGrams
        guard totalFlour > 0 else { return recipe }

        let prefermentLiquid = recipe.preferments
            .flatMap(\.ingredients)
            .filter { $0.category == .liquid }
            .reduce(0.0) { $0 + $1.weightGrams }
        let targetTotalLiquid = totalFlour * (newHydrationPct / 100.0)
        let targetMainLiquid = max(0, targetTotalLiquid - prefermentLiquid)
        let currentMainLiquid = recipe.ingredients
            .filter { $0.category == .liquid }
            .reduce(0.0) { $0 + $1.weightGrams }
        guard currentMainLiquid > 0 else { return recipe }
        let factor = targetMainLiquid / currentMainLiquid

        var out = recipe
        out.ingredients = out.ingredients.map { ing in
            var i = ing
            if ing.category == .liquid {
                i.weightGrams = round(ing.weightGrams * factor)
                i.bakersPct = (i.weightGrams / totalFlour) * 100.0
            }
            return i
        }
        out.hydrationPct = newHydrationPct
        out.totalDoughGrams = out.ingredients.reduce(0.0) { $0 + $1.weightGrams }
            + out.preferments.flatMap(\.ingredients).reduce(0.0) { $0 + $1.weightGrams }
        return out
    }

    /// Severity of a hydration change vs. the recipe's stated target.
    /// ±5 pp is the threshold above which we surface a warning to the baker.
    static func warning(originalHydration: Double, newHydration: Double) -> HydrationWarning {
        let delta = newHydration - originalHydration
        if delta > 5 { return .higher }
        if delta < -5 { return .lower }
        return .none
    }
}
