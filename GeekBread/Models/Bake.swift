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
    /// Stage 18.5b — every stage's actual elapsed time (recipe-stage index
    /// → minutes). Captured at `completeBake` from each
    /// `ActiveBake.StageHistoryEntry`'s `enteredAt`/`exitedAt` deltas.
    /// Optional + default so pre-Stage-18.5b persisted entries decode
    /// cleanly; `Analytics.kitchenTimings` skips entries that are missing
    /// or partial.
    var stageDurations: [Int: Int]? = nil
    /// Stage 24 (haiku.md Tier 1.1) — structured crumb diagnosis from
    /// the Cloud AI surface, when one was produced and the user kept
    /// it. Optional + default nil so older journal entries decode
    /// cleanly. The legacy `diagnosis: String` above keeps the filter
    /// chips and markdown export honest while this field opt-in
    /// populates from the Diagnostic screen.
    var diagnosisResult: Diagnosis? = nil

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
