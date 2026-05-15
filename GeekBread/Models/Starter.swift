import Foundation

// Starter management — mirrors the design's STARTERS array and the spec's
// starter state machine (Counter / Fridge / Vacation).

enum StarterStorage: String, Codable, CaseIterable {
    case counter   = "Counter"
    case fridge    = "Fridge"
    case vacation  = "Vacation"
}

enum StarterStateKind: String, Codable {
    case good, warn, info, bad, neutral
}

struct StarterFeeding: Identifiable, Codable, Hashable {
    var id = UUID()
    var when: String         // "Today 8:14 AM" — display string for now
    var ratio: String        // "1:5:5"
    var ambientC: Double
}

struct Starter: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var flourType: String        // "White wheat" | "Whole rye"
    var hydrationPct: Double     // 100% etc.
    var ageDesc: String          // "2y 4mo"
    var weightGrams: Double
    var state: String            // "Peaked 2h ago", "Resting · fridge"
    var stateKind: StarterStateKind
    var storage: StarterStorage
    var lastFeed: String         // "8h ago"
    var peakAt: String           // "-2h 14m" or "—"
    var nextFeed: String         // "In 4h 12m"
    var peakHeightPct: Int       // 162 — peak as % of feed volume
    var riseHistory: [Double]    // last-N samples for sparkline
    var feedings: [StarterFeeding]
    /// Latest user-captured photo of this starter — bundled asset name or
    /// a `<uuid>.jpg` filename written to PersistenceController.photosDirectory.
    var lastPhoto: String? = nil
    var lastPhotoTime: String? = nil
    /// Stage 24 (haiku.md Tier 1.2) — latest Cloud AI starter
    /// assessment, when one was produced. Optional + default so
    /// pre-Stage-24 persisted starters decode cleanly. The
    /// StarterScreen's aiCheckCard reads this; older fields like
    /// `state` / `stateKind` continue to drive the switcher chip so
    /// the chip stays consistent for users without Cloud AI.
    var assessment: StarterAssessment? = nil
}
