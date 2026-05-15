import Foundation

// Stage 24 (haiku.md Tier 1.1) — structured output of the cloud crumb
// diagnosis. A Claude Haiku vision call returns a labeled diagnosis +
// confidence + suggestions; this is the typed shape we decode it into.
//
// The label set is intentionally yeast/sourdough-shaped. The Stage 24
// follow-up of expanding the recipe catalogue (flatbreads, quick breads,
// pretzels, gluten-free) will need either new labels here or an
// `.outOfScope` short-circuit so we don't bluff "underproofed" on a
// banana bread.

enum DiagnosisLabel: String, Codable, CaseIterable, Hashable {
    case underproofed
    case overproofed
    case underbaked
    case overferment
    case tightCrumb
    case openCrumb
    case even
    case unknown

    /// Short, user-facing label suitable for a status pill.
    var displayLabel: String {
        switch self {
        case .underproofed: return "Underproofed"
        case .overproofed:  return "Overproofed"
        case .underbaked:   return "Underbaked"
        case .overferment:  return "Over-fermented"
        case .tightCrumb:   return "Tight crumb"
        case .openCrumb:    return "Open crumb"
        case .even:         return "Even crumb"
        case .unknown:      return "Inconclusive"
        }
    }
}

/// A single diagnostic verdict. `confidence` is the model's own
/// calibrated probability for `primaryLabel`; the UI promotes the
/// similarity-only Stage 24a card whenever this falls below 0.7
/// (the "never bluff a diagnosis" threshold from plan.md §24).
struct Diagnosis: Codable, Hashable {
    var primaryLabel: DiagnosisLabel
    var explanation: String
    var confidence: Double
    var suggestions: [String]
    /// Stored as raw-string keys so JSON round-trips cleanly. Use
    /// `secondaryLabelsTyped` to read.
    var secondaryLabels: [String: Double]
    /// When the diagnosis was produced — surfaced in markdown export
    /// and lets us age out stale diagnoses if the user re-photographs
    /// the same bake.
    var producedAt: Date

    /// True when the model's confidence is high enough to promote
    /// over the on-device similarity card. Reasoned from plan.md
    /// §24's calibration goal: "anything below ~70% as 'couldn't
    /// decide'".
    var isConfident: Bool { confidence >= 0.7 }

    var secondaryLabelsTyped: [(DiagnosisLabel, Double)] {
        secondaryLabels.compactMap { key, value in
            guard let label = DiagnosisLabel(rawValue: key) else { return nil }
            return (label, value)
        }
    }
}

/// Recipe + active-bake context the model uses to ground its
/// diagnosis. Built from the active bake or the journal entry whose
/// photo is being analyzed; nil-able fields are filled best-effort.
struct BakeContext: Codable, Hashable {
    var recipeTitle: String?
    var breadType: String?
    var hydrationPct: Double?
    var bulkMinutes: Int?
    var ambientTempC: Double?
    var retardMinutes: Int?
    var bakeTempC: Double?
    var bakeMinutes: Int?

    /// Compact human-readable summary for the user-message body. We
    /// don't send recipe titles in vain — only context that helps the
    /// diagnosis ground itself in physics (hydration, time, temp).
    var promptSummary: String {
        var parts: [String] = []
        if let v = breadType { parts.append("type: \(v)") }
        if let v = hydrationPct { parts.append("hydration: \(Int(v.rounded()))%") }
        if let v = bulkMinutes { parts.append("bulk: \(v) min") }
        if let v = ambientTempC { parts.append("kitchen: \(Int(v.rounded()))°C") }
        if let v = retardMinutes { parts.append("retard: \(v) min") }
        if let v = bakeTempC { parts.append("bake temp: \(Int(v.rounded()))°C") }
        if let v = bakeMinutes { parts.append("bake time: \(v) min") }
        return parts.isEmpty ? "(no recipe context available)" : parts.joined(separator: " · ")
    }
}
