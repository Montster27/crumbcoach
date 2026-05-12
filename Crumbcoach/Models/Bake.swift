import Foundation

// Journal / bake history records — every completed bake gets one entry.
// Mirrors the design's JOURNAL array; structure inspired by Code Spec §4.6.

struct JournalEntry: Identifiable, Codable, Hashable {
    var id: String
    var recipeId: String
    var date: String           // "Tue", "3 days ago"
    var rating: Int            // 1...5
    var hydrationPct: Double
    var bulkMinutes: Int
    var kitchenC: Double
    var note: String
    var photoAsset: String?
    var diagnosis: String      // "Well proofed" | "Underproofed bulk" | "On target"
}

// MARK: - Insights / patterns

enum InsightKind: String, Codable {
    case trend, flour, temp
}

struct Insight: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: InsightKind
    var headline: String
    var detail: String
}
