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
        } else {
            // Differentiate "nothing parsed" vs "some parsed, some didn't"
            // so the warning tells the user exactly what they need to fix.
            let unfilled = stages.filter { $0.durationMin == 0 }.count
            if unfilled == stages.count {
                warnings.append("Stage durations weren't recognized in the source — fill them in.")
            } else if unfilled > 0 {
                warnings.append("\(unfilled) of \(stages.count) stages had no explicit duration — fill those in.")
            }
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

    /// Try to pull a gram weight + name out of an ingredient string. Three
    /// patterns we handle, in order:
    ///
    /// 1. **Leading-unit** (Stage 17): `"500 g bread flour"`, `"0.5 kg
    ///    bread flour"`, `"17.6 oz bread flour"` — string starts with the
    ///    weight.
    /// 2. **Parenthesized** (Stage 17): `"1 1/4 cups (284g) lukewarm
    ///    water"` — common on King Arthur, Foodgeek, etc., where the
    ///    volume measurement is primary and grams is the metric annotation.
    /// 3. **Table lookup** (Stage 17.5a): `"2 1/4 teaspoons instant
    ///    yeast"` — no gram value in the source at all. The
    ///    `IngredientWeightTable` matches keyword + volume unit and
    ///    multiplies through. Tagged in warnings as "estimated from table
    ///    — verify" so the user knows to double-check.
    ///
    /// Anything that still falls through gets the raw string as the name
    /// and grams = 0, with a "couldn't parse" warning.
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
            } else if let (grams, name, keyword) = parseFromTable(trimmed) {
                out.append(Ingredient(
                    name: name,
                    category: categoryGuess(for: name),
                    weightGrams: grams,
                    bakersPct: 0,
                    section: "main"
                ))
                warnings.append(
                    "Estimated \(Int(grams.rounded()))g for \"\(trimmed)\" using the standard weight for \(keyword) — verify before baking."
                )
            } else if let (grams, sizeLabel) = parseEggCount(trimmed) {
                out.append(Ingredient(
                    name: "egg",
                    category: categoryGuess(for: "egg"),
                    weightGrams: grams,
                    bakersPct: 0,
                    section: "main"
                ))
                warnings.append(
                    "Estimated \(Int(grams.rounded()))g for \"\(trimmed)\" using the standard weight for a \(sizeLabel) (~50 g each) — verify before baking."
                )
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

    // MARK: - Table-based parser (Stage 17.5a)

    private static let leadingQuantityUnitRegex: NSRegularExpression? = try? NSRegularExpression(
        // Mixed numbers are accepted with either a space or the word "and"
        // as the join: "1 1/2 cups" and "1 and 1/2 cups" both capture as
        // the same quantity group. Sally's Baking Addiction and several
        // older blog templates use the "and" form.
        pattern: #"^\s*(\d+(?:\s+(?:and\s+)?\d+/\d+)?(?:[.,]\d+)?|\d+/\d+)\s*(cups?|tablespoons?|tbsp\.?|tbs\.?|teaspoons?|tsp\.?)\b\s*(.*)$"#,
        options: [.caseInsensitive]
    )

    /// Pattern 3: extract quantity + volume unit + name, then look up grams
    /// via the static `IngredientWeightTable`. Returns the matched keyword
    /// alongside grams + name so the caller can attribute the estimate in
    /// the warnings list.
    private static func parseFromTable(_ input: String) -> (Double, String, String)? {
        guard let regex = leadingQuantityUnitRegex else { return nil }
        let ns = input as NSString
        guard let match = regex.firstMatch(in: input,
                                            range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges == 4 else { return nil }
        let quantityStr = ns.substring(with: match.range(at: 1))
        let unitStr = ns.substring(with: match.range(at: 2)).lowercased()
        let rest = ns.substring(with: match.range(at: 3))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let quantity = parseQuantity(quantityStr),
              let unit = mapVolumeUnit(unitStr),
              !rest.isEmpty,
              let estimate = IngredientWeightTable.estimate(
                    name: rest,
                    quantity: quantity,
                    unit: unit
              ) else {
            return nil
        }
        // Clean the name the same way the parenthesized path does so
        // table-sourced rows look the same in the editor.
        let name = cleanIngredientName(rest)
        return (estimate.grams, name.isEmpty ? rest : name, estimate.matchedKeyword)
    }

    /// Parse "2", "1.5", "1/2", "2 1/4", "1 and 1/2", and the unicode
    /// vulgar fractions (½ ¼ ¾ ⅓ ⅔ ⅛ ⅜ ⅝ ⅞). Decimal comma normalized
    /// to a period; the word "and" between whole and fraction normalized
    /// to a space.
    private static func parseQuantity(_ raw: String) -> Double? {
        let trimmed = raw
            .replacingOccurrences(of: "\u{00BD}", with: " 1/2")  // ½
            .replacingOccurrences(of: "\u{00BC}", with: " 1/4")  // ¼
            .replacingOccurrences(of: "\u{00BE}", with: " 3/4")  // ¾
            .replacingOccurrences(of: "\u{2153}", with: " 1/3")  // ⅓
            .replacingOccurrences(of: "\u{2154}", with: " 2/3")  // ⅔
            .replacingOccurrences(of: "\u{215B}", with: " 1/8")  // ⅛
            .replacingOccurrences(of: "\u{215C}", with: " 3/8")  // ⅜
            .replacingOccurrences(of: "\u{215D}", with: " 5/8")  // ⅝
            .replacingOccurrences(of: "\u{215E}", with: " 7/8")  // ⅞
            .replacingOccurrences(of: " and ", with: " ", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        // Mixed number "2 1/4"
        if let spaceIdx = trimmed.firstIndex(of: " ") {
            let whole = String(trimmed[..<spaceIdx])
            let frac = String(trimmed[trimmed.index(after: spaceIdx)...])
                .trimmingCharacters(in: .whitespaces)
            if let w = Double(whole), let f = parseFraction(frac) {
                return w + f
            }
        }
        if let f = parseFraction(trimmed) { return f }
        return Double(trimmed)
    }

    private static func parseFraction(_ s: String) -> Double? {
        let parts = s.split(separator: "/")
        guard parts.count == 2,
              let num = Double(parts[0]),
              let den = Double(parts[1]),
              den != 0 else { return nil }
        return num / den
    }

    private static func mapVolumeUnit(_ raw: String) -> IngredientWeightTable.Unit? {
        let lower = raw.lowercased().replacingOccurrences(of: ".", with: "")
        switch lower {
        case "cup", "cups":                            return .cup
        case "tbsp", "tbs", "tablespoon", "tablespoons": return .tablespoon
        case "tsp", "teaspoon", "teaspoons":           return .teaspoon
        default:                                       return nil
        }
    }

    // MARK: - Egg-count parser

    private static let eggCountRegex: NSRegularExpression? = try? NSRegularExpression(
        // "3 large eggs", "1 jumbo egg", "2 medium eggs, room temperature".
        // Size word is optional and defaults to "large" — by convention an
        // unqualified "1 egg" in a recipe is a large egg.
        pattern: #"^\s*(\d+)\s*(?:(large|extra[-\s]large|jumbo|medium|small)\s+)?eggs?\b"#,
        options: [.caseInsensitive]
    )

    /// USDA standard egg weights (whole egg, in shell-removed grams):
    /// jumbo 63, extra-large 56, large 50, medium 44, small 38. Recipes
    /// almost always assume "large" when the size is unwritten.
    private static func parseEggCount(_ input: String) -> (Double, String)? {
        guard let regex = eggCountRegex else { return nil }
        let ns = input as NSString
        guard let match = regex.firstMatch(in: input,
                                            range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2,
              let count = Int(ns.substring(with: match.range(at: 1))) else { return nil }
        // Size group is optional; range.location == NSNotFound when absent.
        let sizeRaw: String
        if match.range(at: 2).location != NSNotFound {
            sizeRaw = ns.substring(with: match.range(at: 2))
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
        } else {
            sizeRaw = "large"
        }
        let perEgg: Double
        switch sizeRaw {
        case "jumbo":       perEgg = 63
        case "extra-large": perEgg = 56
        case "medium":      perEgg = 44
        case "small":       perEgg = 38
        default:            perEgg = 50  // "large" or unspecified
        }
        return (Double(count) * perEgg, "\(sizeRaw) egg")
    }

    private static let leadingWeightRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^\s*([0-9]+(?:[.,][0-9]+)?)\s*(kg|kilograms?|g|grams?|oz|ounces?)\b\s*(.*)$"#,
        options: [.caseInsensitive]
    )

    private static let parenthesizedWeightRegex: NSRegularExpression? = try? NSRegularExpression(
        // `\b` after the unit prevents matching "g" inside "gallon". The
        // `[^)]*` tail consumes whatever else is in the parens after the
        // gram value — Sally's Baking Addiction publishes "(113g; 8 Tbsp)"
        // and the old `\s*\)` anchor refused to match that shape.
        pattern: #"\(\s*([0-9]+(?:[.,][0-9]+)?)\s*(kg|kilograms?|g|grams?|oz|ounces?)\b[^)]*\)"#,
        options: [.caseInsensitive]
    )

    private static func parseGramsAndName(from input: String) -> (Double, String)? {
        if let result = parseLeadingWeight(input) { return result }
        if let result = parseParenthesizedWeight(input) { return result }
        return nil
    }

    /// Pattern 1: "500 g flour".
    private static func parseLeadingWeight(_ input: String) -> (Double, String)? {
        guard let regex = leadingWeightRegex else { return nil }
        let ns = input as NSString
        guard let match = regex.firstMatch(in: input,
                                            range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges == 4 else { return nil }
        let valueStr = ns.substring(with: match.range(at: 1))
            .replacingOccurrences(of: ",", with: ".")
        let unitStr = ns.substring(with: match.range(at: 2)).lowercased()
        let nameStr = ns.substring(with: match.range(at: 3))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(valueStr),
              let grams = convertToGrams(value: value, unit: unitStr) else { return nil }
        return (grams, nameStr.isEmpty ? input : nameStr)
    }

    /// Pattern 2: "1 1/4 cups (284g) lukewarm water".
    private static func parseParenthesizedWeight(_ input: String) -> (Double, String)? {
        guard let regex = parenthesizedWeightRegex else { return nil }
        let ns = input as NSString
        guard let match = regex.firstMatch(in: input,
                                            range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges == 3 else { return nil }
        let valueStr = ns.substring(with: match.range(at: 1))
            .replacingOccurrences(of: ",", with: ".")
        let unitStr = ns.substring(with: match.range(at: 2)).lowercased()
        guard let value = Double(valueStr),
              let grams = convertToGrams(value: value, unit: unitStr) else { return nil }
        let name = cleanIngredientName(input)
        return (grams, name.isEmpty ? input : name)
    }

    private static func convertToGrams(value: Double, unit: String) -> Double? {
        switch unit {
        case "g", "gram", "grams":      return value
        case "kg", "kilogram", "kilograms": return value * 1000
        case "oz", "ounce", "ounces":   return value * Units.gramsPerOunce
        default: return nil
        }
    }

    /// Best-effort cleanup of an ingredient string into a noun phrase, used
    /// after pattern-2 weight extraction. Strips:
    ///   - all parenthesized blocks ("(284g)", "(2 cups), divided")
    ///   - the leading volume quantity ("1 1/4 cups", "2 tablespoons")
    ///   - an optional "to N units" range continuation
    ///     ("to 1 1/2 cups")
    ///   - trailing footnote markers and stray punctuation
    static func cleanIngredientName(_ input: String) -> String {
        var name = stripAllParenBlocks(from: input)
        name = stripLeadingVolume(from: name)
        // "1 1/4 cups (284g) to 1 1/2 cups (340g) lukewarm water" — after
        // the first volume strip we're left with "to 1 1/2 cups …". Drop
        // the "to" + a second volume.
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("to ") {
            name = stripLeadingVolume(from: String(trimmed.dropFirst(3)))
        }
        return name
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.*"))
            .replacingOccurrences(of: "  ", with: " ")
    }

    private static let parenBlockRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: #"\([^)]*\)"#)
    private static let leadingVolumeRegex: NSRegularExpression? =
        try? NSRegularExpression(
            pattern: #"^\s*(?:\d+(?:\s+\d+/\d+)?(?:[.,]\d+)?|\d+/\d+)\s*(?:cups?|teaspoons?|tablespoons?|tsp\.?|tbsp\.?|pints?|quarts?|pounds?|lbs?\.?|sticks?|ounces?|oz\.?)\.?"#,
            options: [.caseInsensitive]
        )

    private static func stripAllParenBlocks(from input: String) -> String {
        guard let regex = parenBlockRegex else { return input }
        let ns = input as NSString
        return regex.stringByReplacingMatches(
            in: input,
            range: NSRange(location: 0, length: ns.length),
            withTemplate: " "
        )
    }

    private static func stripLeadingVolume(from input: String) -> String {
        guard let regex = leadingVolumeRegex else { return input }
        let ns = input as NSString
        return regex.stringByReplacingMatches(
            in: input,
            range: NSRange(location: 0, length: ns.length),
            withTemplate: ""
        )
    }

    /// Best-effort category guess from the ingredient name. Wrong guesses
    /// are cheap — the user picks the right category in the editor row's
    /// menu. We err on the side of `.flour` for unknowns because the
    /// "needs at least one flour" validator is the only one that uses it.
    ///
    /// Note on "dry milk": the keyword "milk" triggers `.liquid`, which is
    /// wrong for nonfat dry milk solids. Acceptable trade-off — full-fat
    /// liquid milk is the far more common ingredient.
    static func categoryGuess(for name: String) -> IngredientCategory {
        let lower = name.lowercased()
        if lower.contains("salt") { return .salt }
        if lower.contains("starter") || lower.contains("levain")
            || lower.contains("poolish") || lower.contains("biga")
            || lower.contains("yeast") { return .leaven }
        // Liquid keywords are parenthesized as a group so the `&&` for
        // melted-butter doesn't gobble the trailing `||` chain. Oils stay
        // out of the liquid chain entirely — oil is a fat in bread math.
        if lower.contains("water") || lower.contains("milk")
            || lower.contains("egg") || lower.contains("juice")
            || (lower.contains("butter") && lower.contains("melted")) {
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
    /// instruction text becomes the stage note; duration is best-effort
    /// extracted via `parseDurationMinutes` (range → lower bound, compound
    /// "1 hour 30 minutes" supported, "overnight" → 8h). Duration stays at
    /// 0 when the instruction doesn't carry a recognizable time — e.g.
    /// "Bake until golden brown" — so we don't invent ferment times.
    static func mapStages(from instructions: [String]) -> [Stage] {
        instructions.map { text in
            Stage(
                kind: stageKindGuess(for: text),
                durationMin: parseDurationMinutes(from: text) ?? 0,
                temperatureC: nil,
                note: text
            )
        }
    }

    // MARK: - Stage duration parsing

    private static let durationCompoundRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(\d+)\s*(?:hour|hr)s?\s*(?:and\s*)?(\d+)\s*(?:minute|min)s?\b"#,
        options: [.caseInsensitive]
    )

    private static let durationRangeRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?)\s*(?:to|-|–|—)\s*(\d+(?:\.\d+)?)\s*(hour|hr|minute|min)s?\b"#,
        options: [.caseInsensitive]
    )

    private static let durationSingleRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?)\s*(hour|hr|minute|min)s?\b"#,
        options: [.caseInsensitive]
    )

    /// Pull the first explicit duration out of an instruction string. Three
    /// patterns tried in priority order:
    ///
    /// 1. Compound: `"1 hour 30 minutes"` → 90.
    /// 2. Range: `"60 to 90 minutes"` → 60 (lower bound — bakers expect
    ///    the timer to fire early so they can check).
    /// 3. Single: `"20 minutes"`, `"1.5 hours"` → 20 / 90.
    ///
    /// Plus a special case: `"overnight"` → 480 (8 hours, conservative).
    /// Returns nil when no recognizable time appears in the text (e.g.
    /// `"Bake until golden brown"` — the user fills it in).
    static func parseDurationMinutes(from text: String) -> Int? {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)

        // Pattern 1: compound "X hours Y minutes" (must come before single
        // so we don't lose the minutes half).
        if let regex = durationCompoundRegex,
           let m = regex.firstMatch(in: text, range: range),
           m.numberOfRanges == 3,
           let h = Int(ns.substring(with: m.range(at: 1))),
           let mins = Int(ns.substring(with: m.range(at: 2))) {
            return h * 60 + mins
        }

        // Pattern 2: range "X to Y units". Lower bound wins.
        if let regex = durationRangeRegex,
           let m = regex.firstMatch(in: text, range: range),
           m.numberOfRanges == 4,
           let low = Double(ns.substring(with: m.range(at: 1))) {
            let unit = ns.substring(with: m.range(at: 3)).lowercased()
            let perUnit: Double = unit.hasPrefix("h") ? 60 : 1
            return Int((low * perUnit).rounded())
        }

        // Pattern 3: single "X units".
        if let regex = durationSingleRegex,
           let m = regex.firstMatch(in: text, range: range),
           m.numberOfRanges == 3,
           let value = Double(ns.substring(with: m.range(at: 1))) {
            let unit = ns.substring(with: m.range(at: 2)).lowercased()
            let perUnit: Double = unit.hasPrefix("h") ? 60 : 1
            return Int((value * perUnit).rounded())
        }

        // Special case: "overnight" / "overnight in the fridge" → 8h.
        // Conservative — many cold retards run 12h+ but starting timer at
        // 8 lets the baker hit it on the early end.
        if text.range(of: "overnight", options: .caseInsensitive) != nil {
            return 8 * 60
        }
        return nil
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
