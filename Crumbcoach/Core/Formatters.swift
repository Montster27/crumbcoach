import Foundation

// Display formatters used across screens.

enum CCFormat {
    /// "270 → 4h 30m", "45 → 45m"
    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
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
}
