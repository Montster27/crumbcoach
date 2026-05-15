import Foundation

// Display formatters used across screens.

/// Weight unit the user picks in Settings. All persistent ingredient
/// weights stay in grams under the hood — `Units` only flips the display +
/// editor-input layer.
enum Units: String, Codable, CaseIterable {
    case grams, ounces

    var shortLabel: String {
        switch self {
        case .grams:   return "g"
        case .ounces:  return "oz"
        }
    }

    var inputLabel: String {
        switch self {
        case .grams:   return "Grams"
        case .ounces:  return "Ounces"
        }
    }

    /// 1 gram = 0.035274 ounces. Constant inlined here so callers don't
    /// reach into Measurement for every label render.
    static let gramsPerOunce: Double = 28.349523125
}

/// Source the kitchen-temperature reading comes from. `manual` is the v1
/// shipping path (user slides the Scheduler value); `homeKit` is a stub
/// surfaced in Settings — Stage 20 wires the actual data path.
enum KitchenTempSource: String, Codable, CaseIterable {
    case manual, homeKit

    var displayLabel: String {
        switch self {
        case .manual:  return "Manual"
        case .homeKit: return "HomeKit"
        }
    }
}

enum CCFormat {
    /// "270 → 4h 30m", "45 → 45m"
    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// "60 → 60m", "(60, 90) → 60m – 90m". Used everywhere a stage's
    /// duration is displayed so ranged stages (Stage 18.5a) render the
    /// window the source actually published rather than collapsing to the
    /// lower bound. Pass `Stage` directly so callers don't have to know
    /// the two fields.
    static func stageDuration(_ stage: Stage) -> String {
        if let upper = stage.durationMaxMin, upper > stage.durationMin {
            return "\(duration(stage.durationMin))–\(duration(upper))"
        }
        return duration(stage.durationMin)
    }

    /// "12h end-to-end"
    static func endToEndHours(_ minutes: Int) -> String {
        "\(Int(round(Double(minutes) / 60.0)))h end-to-end"
    }

    /// Date → "Sat 4:12 PM"
    static let clockShort: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return f
    }()

    /// Date → "10:30 AM"
    static let clockTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    /// Date → "Sun 10:30 AM"
    static func relativeClock(_ date: Date) -> String {
        clockShort.string(from: date)
    }

    /// Offset minutes → "+4h 15m"
    static func relativeOffset(_ minutes: Int) -> String {
        "+\(duration(minutes))"
    }

    // MARK: - Weight display

    /// "500 g" or "17.6 oz". Caller passes the source grams; we convert
    /// when the user has picked ounces. Rounding: integer grams,
    /// one-decimal ounces — bakers expect a precise gram and a friendly
    /// ounce reading.
    static func weight(grams: Double, units: Units) -> String {
        switch units {
        case .grams:
            return "\(Int(grams.rounded())) g"
        case .ounces:
            let oz = grams / Units.gramsPerOunce
            return String(format: "%.1f oz", oz)
        }
    }

    /// Editor variant — value-only, used inside number inputs where the
    /// unit label sits beside the field rather than inside it.
    static func weightValue(grams: Double, units: Units) -> String {
        switch units {
        case .grams:   return "\(Int(grams.rounded()))"
        case .ounces:  return String(format: "%.2f", grams / Units.gramsPerOunce)
        }
    }

    /// Parse user editor input (the chosen units) back to grams for
    /// persistence. Bad input falls back to 0.
    static func grams(from input: String, units: Units) -> Double {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed) else { return 0 }
        switch units {
        case .grams:   return value
        case .ounces:  return value * Units.gramsPerOunce
        }
    }
}
