import Foundation

// On-device import of recipes from third-party URLs. The shape we target is
// schema.org's `Recipe` type embedded as JSON-LD inside a `<script
// type="application/ld+json">` block — the de-facto standard for King Arthur,
// The Perfect Loaf, Foodgeek, Maurizio Leo, and most bread sites with SEO.
//
// We do NOT scrape prose narrative — only the formula:
//   - `name` → recipe title
//   - `image` → photo URL (we just record it; user pastes their own later)
//   - `recipeIngredient` → ingredient list (best-effort gram parsing)
//   - `recipeInstructions` → stages (keyword-mapped to StageKind; the
//     instruction text becomes the stage note, duration left at 0 for the
//     user to fill in)
//
// Caller hands the resulting `Imported` value to the editor. Warnings make
// the lossy parts visible — the user can decide whether to clean up.
//
// Error path: throwing helps the editor display a contextual message. The
// happy path returns warnings inline so an import with 2 unparseable
// ingredients still gives the user a starting point.

enum RecipeImporterError: LocalizedError {
    case invalidURL
    case fetchFailed(String)
    case notHTML
    case noJSONLD
    case noRecipeSchema

    var errorDescription: String? {
        switch self {
        case .invalidURL:       return "That doesn't look like a URL."
        case .fetchFailed(let m): return "Couldn't reach the recipe: \(m)"
        case .notHTML:          return "The link doesn't return an HTML page."
        case .noJSONLD:         return "No recipe data found on the page."
        case .noRecipeSchema:   return "The page didn't include schema.org Recipe data."
        }
    }
}

struct ImportedRecipe {
    /// Editor-ready draft. Source URL, title, photo, ingredients, stages
    /// are filled in best-effort. `id` is fresh, hydration/salt/leaven
    /// percentages will be recomputed by the editor's save path.
    var draft: Recipe
    /// User-visible warnings about lossy parts. The editor surfaces these
    /// so the user knows what to double-check.
    var warnings: [String]
}

enum RecipeImporter {

    /// Fetch the URL, find the first valid JSON-LD Recipe object, and map
    /// it to a `Recipe` draft. Async so the call site can show a spinner.
    static func `import`(from url: URL,
                          session: URLSession = .shared) async throws -> ImportedRecipe {
        var request = URLRequest(url: url)
        // Some sites refuse a default URLSession User-Agent. Spoofing a
        // common browser string makes the fetch succeed more often without
        // crossing into anything sketchy — we're reading the same JSON-LD
        // their SEO target consumes.
        request.setValue(
            "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 CrumbCoachImporter/0.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 20

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RecipeImporterError.fetchFailed(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw RecipeImporterError.fetchFailed("HTTP \(http.statusCode)")
        }
        let mime = (response as? HTTPURLResponse)?.mimeType ?? ""
        if !mime.isEmpty && !mime.contains("html") && !mime.contains("text") {
            throw RecipeImporterError.notHTML
        }
        guard let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw RecipeImporterError.notHTML
        }

        let blocks = extractJSONLDBlocks(from: html)
        guard !blocks.isEmpty else { throw RecipeImporterError.noJSONLD }

        guard let recipeDict = findRecipe(in: blocks) else {
            throw RecipeImporterError.noRecipeSchema
        }

        return mapToDraft(recipeDict: recipeDict, sourceURL: url)
    }

    // MARK: - JSON-LD extraction

    /// Find every `<script type="application/ld+json">…</script>` block and
    /// decode its body. Returns the decoded objects; arrays and `@graph`
    /// wrappers are flattened to top-level dictionaries.
    static func extractJSONLDBlocks(from html: String) -> [[String: Any]] {
        let nsHtml = html as NSString
        let pattern = #"<script[^>]*type=["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                    options: [.caseInsensitive]) else {
            return []
        }
        let matches = regex.matches(in: html,
                                     range: NSRange(location: 0, length: nsHtml.length))
        var out: [[String: Any]] = []
        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let body = nsHtml.substring(with: match.range(at: 1))
            guard let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data,
                                                                options: [.fragmentsAllowed]) else {
                continue
            }
            // Top-level can be: a dict, an array of dicts, or a dict with
            // `@graph: [...]`. Flatten any case to a list of dicts.
            collectDicts(from: json, into: &out)
        }
        return out
    }

    private static func collectDicts(from json: Any, into out: inout [[String: Any]]) {
        if let dict = json as? [String: Any] {
            if let graph = dict["@graph"] as? [Any] {
                graph.forEach { collectDicts(from: $0, into: &out) }
            }
            out.append(dict)
        } else if let array = json as? [Any] {
            array.forEach { collectDicts(from: $0, into: &out) }
        }
    }

    private static func findRecipe(in blocks: [[String: Any]]) -> [String: Any]? {
        for block in blocks {
            if isRecipeType(block["@type"]) {
                return block
            }
        }
        return nil
    }

    private static func isRecipeType(_ value: Any?) -> Bool {
        if let s = value as? String { return s.caseInsensitiveCompare("Recipe") == .orderedSame }
        if let arr = value as? [String] {
            return arr.contains { $0.caseInsensitiveCompare("Recipe") == .orderedSame }
        }
        return false
    }

    // MARK: - Mapping

    /// Build the editor draft + warnings from the decoded Recipe dictionary.
    /// All fields are best-effort; missing inputs produce a warning and a
    /// sensible default rather than an error.
    static func mapToDraft(recipeDict: [String: Any], sourceURL: URL) -> ImportedRecipe {
        var warnings: [String] = []

        let title = (recipeDict["name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let ingredientStrings: [String] =
            (recipeDict["recipeIngredient"] as? [String])
            ?? (recipeDict["ingredients"] as? [String])
            ?? []
        let (ingredients, ingredientWarnings) = parseIngredients(ingredientStrings)
        warnings.append(contentsOf: ingredientWarnings)

        let instructionStrings = parseInstructions(recipeDict["recipeInstructions"])
        let stages = mapStages(from: instructionStrings)
        if stages.isEmpty {
            warnings.append("No instructions were detected — add stages by hand.")
        } else if stages.allSatisfy({ $0.durationMin == 0 }) {
            warnings.append("Stage durations were not present in the source — fill them in.")
        }

        let sourceName = sourceURL.host?
            .replacingOccurrences(of: "www.", with: "") ?? "Linked recipe"

        // Build a draft skeleton — totalDoughGrams / hydrationPct etc. get
        // recomputed by the editor's save path against the actual
        // ingredients. We leave 0 for them so the math owner is clearly the
        // save step, not us.
        let draft = Recipe(
            id: UUID().uuidString,
            title: title.isEmpty ? "Imported recipe" : title,
            breadType: .sourdough,
            source: .linked(url: sourceURL.absoluteString,
                             sourceName: sourceName,
                             sourceLogo: nil),
            photo: nil,
            hydrationPct: 0,
            saltPct: 0,
            leavenPct: 0,
            totalDoughGrams: ingredients.reduce(0) { $0 + $1.weightGrams },
            loafCount: 1,
            timeToBake: "",
            tags: [],
            twinScald: false,
            preferments: [],
            ingredients: ingredients,
            stages: stages.isEmpty
                ? [Stage(kind: .mix, durationMin: 30, temperatureC: nil, note: "Imported recipe — add stages")]
                : stages,
            lastBake: nil
        )

        if title.isEmpty {
            warnings.insert("No title found — using \"Imported recipe\".", at: 0)
        }

        return ImportedRecipe(draft: draft, warnings: warnings)
    }

    // MARK: - Ingredient parsing

    /// Try to pull a gram weight + name out of an ingredient string. Common
    /// patterns we handle:
    ///   - "500 g bread flour"
    ///   - "500g bread flour"
    ///   - "0.5 kg bread flour"
    ///   - "17.6 oz bread flour"
    /// Anything else gets the raw string as the name and grams = 0, plus a
    /// warning so the user knows which rows need touch-up.
    static func parseIngredients(_ raw: [String]) -> ([Ingredient], [String]) {
        var out: [Ingredient] = []
        var warnings: [String] = []
        for line in raw {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let (grams, name) = parseGramsAndName(from: trimmed) {
                out.append(Ingredient(
                    name: name,
                    category: categoryGuess(for: name),
                    weightGrams: grams,
                    bakersPct: 0,
                    section: "main"
                ))
            } else {
                out.append(Ingredient(
                    name: trimmed,
                    category: categoryGuess(for: trimmed),
                    weightGrams: 0,
                    bakersPct: 0,
                    section: "main"
                ))
                warnings.append("Couldn't parse a weight from \"\(trimmed)\".")
            }
        }
        return (out, warnings)
    }

    private static let weightRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^\s*([0-9]+(?:[.,][0-9]+)?)\s*(kg|kilograms?|g|grams?|oz|ounces?)\b\s*(.*)$"#,
        options: [.caseInsensitive]
    )

    private static func parseGramsAndName(from input: String) -> (Double, String)? {
        guard let regex = weightRegex else { return nil }
        let ns = input as NSString
        guard let match = regex.firstMatch(in: input,
                                            range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges == 4 else { return nil }
        let valueStr = ns.substring(with: match.range(at: 1))
            .replacingOccurrences(of: ",", with: ".")
        let unitStr = ns.substring(with: match.range(at: 2)).lowercased()
        let nameStr = ns.substring(with: match.range(at: 3))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(valueStr) else { return nil }
        let grams: Double
        switch unitStr {
        case "kg", "kilogram", "kilograms":
            grams = value * 1000
        case "g", "gram", "grams":
            grams = value
        case "oz", "ounce", "ounces":
            grams = value * Units.gramsPerOunce
        default:
            return nil
        }
        return (grams, nameStr.isEmpty ? input : nameStr)
    }

    /// Best-effort category guess from the ingredient name. Wrong guesses
    /// are cheap — the user picks the right category in the editor row's
    /// menu. We err on the side of `.flour` for unknowns because the
    /// "needs at least one flour" validator is the only one that uses it.
    static func categoryGuess(for name: String) -> IngredientCategory {
        let lower = name.lowercased()
        if lower.contains("salt") { return .salt }
        if lower.contains("starter") || lower.contains("levain")
            || lower.contains("poolish") || lower.contains("biga")
            || lower.contains("yeast") { return .leaven }
        if lower.contains("water") || lower.contains("milk")
            || lower.contains("egg") || lower.contains("juice")
            || lower.contains("oil") && !lower.contains("olive oil")
            || lower.contains("butter") && lower.contains("melted") {
            return .liquid
        }
        if lower.contains("sugar") || lower.contains("honey")
            || lower.contains("syrup") || lower.contains("molasses") { return .sweet }
        if lower.contains("butter") || lower.contains("oil")
            || lower.contains("lard") || lower.contains("shortening") { return .fat }
        if lower.contains("seed") || lower.contains("nut")
            || lower.contains("raisin") || lower.contains("cheese")
            || lower.contains("chocolate") || lower.contains("cinnamon") {
            return .inclusion
        }
        return .flour
    }

    // MARK: - Instructions parsing

    /// `recipeInstructions` can be a flat string, an array of strings, or
    /// an array of `HowToStep` dictionaries with a `text` field. Flatten
    /// everything to one ordered list of strings.
    static func parseInstructions(_ value: Any?) -> [String] {
        var out: [String] = []
        func absorb(_ v: Any) {
            if let s = v as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { out.append(trimmed) }
            } else if let dict = v as? [String: Any] {
                if let text = dict["text"] as? String {
                    absorb(text)
                } else if let name = dict["name"] as? String {
                    absorb(name)
                } else if let items = dict["itemListElement"] as? [Any] {
                    items.forEach(absorb)
                }
            } else if let arr = v as? [Any] {
                arr.forEach(absorb)
            }
        }
        if let value { absorb(value) }
        return out
    }

    /// Map each instruction text to a `Stage` via keyword detection. The
    /// instruction text becomes the stage note; duration stays at 0 so the
    /// user fills it in (and so we don't lie about ferment times).
    static func mapStages(from instructions: [String]) -> [Stage] {
        instructions.map { text in
            let kind = stageKindGuess(for: text)
            return Stage(
                kind: kind,
                durationMin: 0,
                temperatureC: nil,
                note: text
            )
        }
    }

    private static func stageKindGuess(for text: String) -> StageKind {
        let lower = text.lowercased()
        if lower.contains("autolyse") { return .autolyse }
        if lower.contains("levain") || lower.contains("feed") { return .feedLevain }
        if lower.contains("yudane") { return .prepYudane }
        if lower.contains("tangzhong") { return .cookTangzhong }
        if lower.contains("butter") && lower.contains("add") { return .addButter }
        if lower.contains("fold") || lower.contains("stretch") { return .bulkFold }
        if lower.contains("bulk") || lower.contains("ferment")
            || lower.contains("rise") || lower.contains("rest") { return .bulk }
        if lower.contains("divide") && lower.contains("shape") { return .divideShape }
        if lower.contains("pre-shape") || lower.contains("preshape")
            || lower.contains("pre shape") { return .preShape }
        if lower.contains("shape") || lower.contains("form") { return .finalShape }
        if lower.contains("retard") || lower.contains("fridge")
            || lower.contains("refrigerator") || lower.contains("overnight") { return .coldRetard }
        if lower.contains("proof") || lower.contains("final rise") { return .finalProof }
        if lower.contains("bake") || lower.contains("oven") { return .bake }
        if lower.contains("mix") || lower.contains("combine")
            || lower.contains("knead") || lower.contains("stir") { return .mix }
        return .mix
    }
}
