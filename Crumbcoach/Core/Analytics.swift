import Foundation

// Bake-history pattern recognition.  Mirrors §4.6 / §7.3 of the Code Spec:
//   - regress bulk-time → rating per recipe
//   - look for flour-brand correlations
//   - month-over-month temperature trends
// All math here is deliberately simple — production version would use ridge or
// Bayesian regression with proper confidence intervals.

enum Analytics {

    /// Average bulk minutes for a recipe in the user's history.
    static func avgBulkMinutes(for recipeId: String, in journal: [JournalEntry]) -> Int? {
        let rows = journal.filter { $0.recipeId == recipeId }
        guard !rows.isEmpty else { return nil }
        return rows.reduce(0) { $0 + $1.bulkMinutes } / rows.count
    }

    /// Average kitchen temp across recent bakes.
    static func avgKitchenC(in journal: [JournalEntry]) -> Double? {
        guard !journal.isEmpty else { return nil }
        return journal.reduce(0.0) { $0 + $1.kitchenC } / Double(journal.count)
    }

    /// Average rating across all bakes (or for a recipe if filtered).
    static func avgRating(in journal: [JournalEntry]) -> Double? {
        guard !journal.isEmpty else { return nil }
        return journal.reduce(0.0) { $0 + Double($1.rating) } / Double(journal.count)
    }

    /// Correlation between bulk minutes and rating for a recipe.  Returns
    /// Pearson r in -1...1 (rough proxy: "do longer bulks rate better?").
    static func bulkRatingCorrelation(for recipeId: String, in journal: [JournalEntry]) -> Double? {
        let rows = journal.filter { $0.recipeId == recipeId }
        guard rows.count >= 3 else { return nil }
        let xs = rows.map { Double($0.bulkMinutes) }
        let ys = rows.map { Double($0.rating) }
        let mx = xs.reduce(0, +) / Double(xs.count)
        let my = ys.reduce(0, +) / Double(ys.count)
        var num = 0.0, dx2 = 0.0, dy2 = 0.0
        for i in 0..<xs.count {
            let a = xs[i] - mx
            let b = ys[i] - my
            num += a * b
            dx2 += a * a
            dy2 += b * b
        }
        let denom = (dx2 * dy2).squareRoot()
        guard denom > 0 else { return nil }
        return num / denom
    }

    /// Produce a short list of plain-English insights from the user's recent
    /// bakes.  Returns at most `limit` insights, ordered by what we think is
    /// most actionable. Returns an empty list when there's no journal to read
    /// — callers gate the UI on `isEmpty` rather than rendering a fake card.
    static func generateInsights(from journal: [JournalEntry], limit: Int = 3) -> [Insight] {
        guard !journal.isEmpty else { return [] }
        var out: [Insight] = []

        // 1. Trend on the most-baked recipe
        let counts = Dictionary(grouping: journal, by: \.recipeId).mapValues(\.count)
        if let topId = counts.max(by: { $0.value < $1.value })?.key,
           let avg = avgBulkMinutes(for: topId, in: journal),
           let _ = bulkRatingCorrelation(for: topId, in: journal) {
            let rows = journal.filter { $0.recipeId == topId }
            let best = rows.max(by: { $0.rating < $1.rating })
            let worst = rows.min(by: { $0.rating < $1.rating })
            let h = avg / 60, m = avg % 60
            let detailParts: [String?] = [
                best.map { "Your \($0.rating)-star bake was \(formatMinutes($0.bulkMinutes))." },
                worst.map { "Your \($0.rating)-star bake was \(formatMinutes($0.bulkMinutes))." }
            ]
            out.append(Insight(
                kind: .trend,
                headline: "Your last \(rows.count) bakes of this recipe averaged \(h)h\(m > 0 ? " \(m)m" : "") bulk.",
                detail: detailParts.compactMap { $0 }.joined(separator: " ")
            ))
        }

        // 2. Temperature trend
        if let avgT = avgKitchenC(in: journal) {
            let rounded = (avgT * 10).rounded() / 10
            out.append(Insight(
                kind: .temp,
                headline: "Kitchen averaged \(String(format: "%.1f", rounded))°C across these bakes.",
                detail: avgT < 22
                    ? "Consider warming proofs to 24°C or extending bulks by ~30%."
                    : "Right in the sweet spot for most recipes."
            ))
        }

        return Array(out.prefix(limit))
    }

    static func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
