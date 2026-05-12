import Foundation

// Recipe model mirroring the Rust core types from CrumbCoach_Code_Spec.md §3.3.
// All percentages are baker's-percentage style — flour weight = 100%.

enum BreadType: String, Codable, CaseIterable, Identifiable {
    case sourdough  = "Sourdough"
    case leanYeasted = "Lean yeasted"
    case enriched   = "Enriched"
    case rye        = "Rye"
    case flatbread  = "Flatbread"
    case quickBread = "Quick bread"
    case steamed    = "Steamed"
    var id: String { rawValue }
}

enum IngredientCategory: String, Codable, CaseIterable {
    case flour   = "Flour"
    case liquid  = "Liquid"
    case salt    = "Salt"
    case leaven  = "Leaven"
    case fat     = "Fat"
    case sweet   = "Sweet"
    case inclusion = "Inclusion"
}

enum RecipeSource: Codable, Hashable {
    case original                                                       // CrumbCoach-authored
    case userCreated                                                    // user-authored
    case linked(url: String, sourceName: String, sourceLogo: String?)   // third-party
    case photoScanned(label: String)                                    // user's own scan

    var label: String {
        switch self {
        case .original: return "CrumbCoach"
        case .userCreated: return "Your recipe"
        case .linked(_, let name, _): return name
        case .photoScanned(let l): return l
        }
    }
    var kindKey: String {
        switch self {
        case .original: return "original"
        case .userCreated: return "user"
        case .linked: return "linked"
        case .photoScanned: return "scanned"
        }
    }
    var isLinked: Bool {
        if case .linked = self { return true }
        return false
    }
}

struct Ingredient: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var category: IngredientCategory
    var weightGrams: Double
    var bakersPct: Double
    var notes: String? = nil
    var section: String? = nil   // "main" | "yudane" | "tangzhong" | nil

    enum CodingKeys: String, CodingKey {
        case id, name, category, weightGrams, bakersPct, notes, section
    }
}

enum StageKind: String, Codable, CaseIterable {
    case feedLevain   = "Feed levain"
    case prepYudane   = "Prep yudane"
    case cookTangzhong = "Cook tangzhong"
    case autolyse     = "Autolyse"
    case mix          = "Mix"
    case addButter    = "Add butter"
    case bulkFold     = "Bulk + folds"
    case bulk         = "Bulk"
    case divide       = "Divide"
    case preShape     = "Pre-shape"
    case divideShape  = "Divide & shape"
    case finalShape   = "Final shape"
    case proof        = "Proof"
    case finalProof   = "Final proof"
    case coldRetard   = "Cold retard"
    case bake         = "Bake"
}

struct Stage: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: StageKind
    var durationMin: Int             // typical / baseline (lower bound of a range)
    /// Optional upper bound when the source published a range
    /// ("rise 60 to 90 minutes"). When nil, this stage has a single
    /// duration. When set, UI surfaces should render "Xm–Ym" and the
    /// scheduler keeps using `durationMin` for the conservative timeline.
    /// Stage 18.5a addition; pre-existing persisted recipes decode with
    /// nil and behave as before.
    var durationMaxMin: Int? = nil
    var temperatureC: Double?        // optional ambient or oven temp
    var note: String? = nil
    var scaldRef: String? = nil      // "yudane" | "tangzhong" — links to preferment block
    var totalFolds: Int? = nil       // only meaningful for .bulkFold; otherwise nil
}

struct Preferment: Identifiable, Codable, Hashable {
    var id: String                   // "levain" | "yudane" | "tangzhong" | "biga" | "poolish"
    var name: String
    var technique: String
    var prep: String
    var flourPct: Double             // % of total flour represented by this preferment
    var ingredients: [Ingredient]
}

struct Recipe: Identifiable, Codable, Hashable {
    var id: String                   // stable string id, e.g. "country"
    var title: String
    var breadType: BreadType
    var source: RecipeSource
    var photo: String?               // asset name or hint; falls back to gradient
    var hydrationPct: Double
    var saltPct: Double
    var leavenPct: Double            // levain or yeast %
    var totalDoughGrams: Double
    var loafCount: Int
    var timeToBake: String           // human-friendly summary
    var tags: [String]
    var twinScald: Bool              // hokkaido-style: yudane + tangzhong combined
    var preferments: [Preferment]    // optional, e.g. tangzhong / yudane / levain build
    var ingredients: [Ingredient]
    var stages: [Stage]
    var lastBake: LastBake?

    struct LastBake: Codable, Hashable {
        var rating: Int      // 1...5
        var bakedAt: Date
        var note: String?

        /// "Today" / "3 days ago" / "2 weeks ago" display string.
        var whenDisplay: String {
            let now = Date()
            let cal = Calendar.current
            let days = cal.dateComponents([.day], from: bakedAt, to: now).day ?? 0
            if days < 1 { return "Today" }
            if days == 1 { return "Yesterday" }
            if days < 7 { return "\(days) days ago" }
            if days < 31 {
                let w = days / 7
                return w == 1 ? "1 week ago" : "\(w) weeks ago"
            }
            let m = days / 30
            return m == 1 ? "1 month ago" : "\(m) months ago"
        }
    }
}
