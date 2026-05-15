import Foundation

// Stage 24 (haiku.md Tier 1.2) — structured output of the cloud
// starter-health check. Today's `StarterScreen.aiCheckCard` renders
// hardcoded "State: post-peak…" text for every starter regardless of
// input; this replaces it with a real model verdict when the user is
// opted in and has uploaded a photo.

enum StarterState: String, Codable, CaseIterable, Hashable {
    case peak       // at peak rise — best for an active bake
    case prePeak    // still rising — wait
    case postPeak   // falling — use soon, refrigerate, or feed
    case hungry     // very low activity, needs feeding
    case sluggish   // slow rise (cold kitchen, weak culture)
    case unknown    // photo or context didn't support a call

    var displayLabel: String {
        switch self {
        case .peak:     return "Peak"
        case .prePeak:  return "Pre-peak"
        case .postPeak: return "Post-peak"
        case .hungry:   return "Hungry"
        case .sluggish: return "Sluggish"
        case .unknown:  return "Inconclusive"
        }
    }
}

/// Concrete action the model thinks the baker should take next. The
/// UI defaults the primary CTA to this — the other action stays
/// available as a secondary, so the user can still override.
enum StarterAction: String, Codable, Hashable {
    case useNow         // bake with it
    case refrigerate    // park it
    case feedNow        // refresh
    case wait           // pair with `waitHours`
    case bringToCounter // wake from fridge
}

struct StarterAssessment: Codable, Hashable {
    var state: StarterState
    var suggestedAction: StarterAction
    /// Only meaningful when `suggestedAction == .wait`. Hours until
    /// the model expects peak. Nil for any other action.
    var waitHours: Double?
    var explanation: String
    var confidence: Double
    var producedAt: Date

    /// 0.7 mirrors the crumb-diagnosis threshold. Below this the
    /// StarterScreen card falls back to neutral copy rather than a
    /// confident-sounding line driven by a soft guess.
    var isConfident: Bool { confidence >= 0.7 }
}

/// Per-starter context the model uses to ground its assessment. Time
/// since last feed and ambient temperature are the two strongest
/// non-visual signals.
struct StarterContext: Codable, Hashable {
    var hoursSinceFeed: Double?
    var kitchenTempC: Double?
    var storage: String?   // counter / fridge / vacation
    var feedRatio: String?

    var promptSummary: String {
        var parts: [String] = []
        if let v = hoursSinceFeed {
            parts.append(String(format: "fed %.1fh ago", v))
        }
        if let v = kitchenTempC {
            parts.append("kitchen \(Int(v.rounded()))°C")
        }
        if let v = storage { parts.append("storage: \(v.lowercased())") }
        if let v = feedRatio { parts.append("ratio: \(v)") }
        return parts.isEmpty ? "(no recent-feed context)" : parts.joined(separator: " · ")
    }
}
