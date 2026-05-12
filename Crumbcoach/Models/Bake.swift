import Foundation

// Journal / bake history records — every completed bake gets one entry.
// Mirrors the design's JOURNAL array; structure inspired by Code Spec §4.6.

struct JournalEntry: Identifiable, Codable, Hashable {
    var id: String
    var recipeId: String
    var bakedAt: Date              // real Date — enables filtering / sorting
    var rating: Int                // 1...5
    var hydrationPct: Double
    var bulkMinutes: Int
    var kitchenC: Double
    var note: String
    var photoAsset: String?
    var diagnosis: String          // "Well proofed" | "Underproofed bulk" | ...

    /// "Tue" or "3 days ago" style display string, computed from `bakedAt`.
    var dateDisplay: String {
        let now = Date()
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: bakedAt, to: now).day ?? 0
        if days < 1 {
            return "Today"
        } else if days < 7 {
            let f = DateFormatter()
            f.dateFormat = "EEE"
            return f.string(from: bakedAt)
        } else if days < 31 {
            let weeks = days / 7
            return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
        } else {
            let months = days / 30
            return months == 1 ? "1 month ago" : "\(months) months ago"
        }
    }
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
