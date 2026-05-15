import Foundation

// Markdown serialization for recipes and journal entries. The output goes
// through the iOS share sheet as a plain `String` activity item — Mail and
// Messages render it as text, Files saves it as a .md attachment, and
// markdown-aware apps (Bear, Obsidian) preserve the formatting.
//
// We export FORMULA + STAGES, not narrative prose. GeekBread is the user's
// formula tracker; if they want narrative they keep it in the source URL.

enum RecipeExporter {

    /// Build a self-contained Markdown blob for one recipe. Includes the
    /// deep-link footer so the receiver can tap it back into the app.
    static func markdown(for recipe: Recipe, units: Units = .grams) -> String {
        var lines: [String] = []
        lines.append("# \(recipe.title)")
        lines.append("")
        lines.append("- **Type:** \(recipe.breadType.rawValue)")
        lines.append("- **Hydration:** \(formattedPct(recipe.hydrationPct))")
        lines.append("- **Salt:** \(formattedPct(recipe.saltPct))")
        lines.append("- **Leaven:** \(formattedPct(recipe.leavenPct))")
        lines.append("- **Total dough:** \(CCFormat.weight(grams: recipe.totalDoughGrams, units: units))")
        lines.append("- **Loaves:** \(recipe.loafCount)")
        lines.append("")

        if !recipe.preferments.isEmpty {
            for pf in recipe.preferments {
                lines.append("## Preferment — \(pf.name)")
                lines.append("")
                lines.append("> \(pf.technique)")
                if !pf.prep.isEmpty {
                    lines.append(">")
                    lines.append("> \(pf.prep)")
                }
                lines.append("")
                lines.append(ingredientsTable(pf.ingredients, units: units))
                lines.append("")
            }
        }

        lines.append("## Ingredients")
        lines.append("")
        lines.append(ingredientsTable(recipe.ingredients, units: units))
        lines.append("")

        lines.append("## Stages")
        lines.append("")
        for (i, stage) in recipe.stages.enumerated() {
            let durLabel = stage.durationMin > 0
                ? " · \(CCFormat.stageDuration(stage))"
                : ""
            let tempLabel = stage.temperatureC.map { " · \(Int($0))°C" } ?? ""
            lines.append("\(i + 1). **\(stage.kind.rawValue)**\(durLabel)\(tempLabel)")
            if let note = stage.note, !note.isEmpty {
                lines.append("   \(note)")
            }
        }
        lines.append("")
        lines.append("---")
        lines.append("")
        lines.append("Open in GeekBread: \(deepLink(for: recipe).absoluteString)")
        return lines.joined(separator: "\n")
    }

    /// Build a Markdown summary of the journal. Headline table + one block
    /// per entry with rating, note, and key formula numbers.
    static func markdown(forJournal entries: [JournalEntry],
                          recipeLookup: (String) -> Recipe?,
                          units: Units = .grams) -> String {
        var lines: [String] = []
        lines.append("# Bake journal")
        lines.append("")
        lines.append("- **Entries:** \(entries.count)")
        if let avg = Analytics.avgRating(in: entries) {
            lines.append("- **Average rating:** \(String(format: "%.1f", avg)) ★")
        }
        if let temp = Analytics.avgKitchenC(in: entries) {
            lines.append("- **Average kitchen temp:** \(String(format: "%.1f", temp))°C")
        }
        lines.append("")

        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        for entry in entries {
            let recipe = recipeLookup(entry.recipeId)
            let title = recipe?.title ?? entry.recipeId
            lines.append("## \(title) — \(formatter.string(from: entry.bakedAt))")
            lines.append("")
            lines.append("- **Rating:** \(stars(entry.rating))")
            lines.append("- **Hydration:** \(formattedPct(entry.hydrationPct))")
            lines.append("- **Bulk:** \(CCFormat.duration(entry.bulkMinutes))")
            lines.append("- **Kitchen:** \(String(format: "%.1f", entry.kitchenC))°C")
            lines.append("- **Diagnosis:** \(entry.diagnosis)")
            if !entry.note.isEmpty {
                lines.append("")
                lines.append(entry.note)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Build the deep-link URL the share sheet receiver can tap to open the
    /// recipe inside GeekBread. Format: `geekbread://recipe/<id>`.
    static func deepLink(for recipe: Recipe) -> URL {
        URL(string: "geekbread://recipe/\(recipe.id)")
            ?? URL(string: "geekbread://recipe")!
    }

    /// Deep link used by the share extension to hand a Safari page URL back
    /// to the main app's recipe importer. Format:
    /// `geekbread://import?url=<percent-encoded>`.
    static func importDeepLink(sourceURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "geekbread"
        components.host = "import"
        components.queryItems = [URLQueryItem(name: "url", value: sourceURL.absoluteString)]
        return components.url
    }

    // MARK: Helpers

    private static func ingredientsTable(_ ings: [Ingredient], units: Units) -> String {
        guard !ings.isEmpty else { return "_(no ingredients listed)_" }
        var rows: [String] = []
        rows.append("| Ingredient | Weight | Baker's % | Category |")
        rows.append("|------------|--------|-----------|----------|")
        for ing in ings {
            let weight = CCFormat.weight(grams: ing.weightGrams, units: units)
            let pct = String(format: "%.1f%%", ing.bakersPct)
            rows.append("| \(ing.name) | \(weight) | \(pct) | \(ing.category.rawValue) |")
        }
        return rows.joined(separator: "\n")
    }

    private static func formattedPct(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private static func stars(_ rating: Int) -> String {
        String(repeating: "★", count: max(0, min(5, rating)))
            + String(repeating: "☆", count: 5 - max(0, min(5, rating)))
    }
}
