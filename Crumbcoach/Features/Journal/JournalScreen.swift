import SwiftUI

// Journal — filter chips + bulk-time scatter chart + journal list +
// month-summary stats on the right rail.

struct JournalScreen: View {
    @Bindable var state: AppState
    @State private var filter: String = "All bakes"

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            // LEFT
            VStack(spacing: 16) {
                filtersRow
                trendCard
                ForEach(state.journal) { entry in
                    JournalCard(entry: entry, recipe: state.recipe(entry.recipeId))
                }
            }
            .frame(maxWidth: .infinity)

            // RIGHT
            VStack(spacing: 16) {
                monthSummaryCard
                ForEach(Array(state.insights.enumerated()), id: \.offset) { i, ins in
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                CCIconView(icon: .sparkle, size: 14, color: Theme.accent)
                                Kicker("Insight \(i + 1)", color: Theme.accent)
                            }
                            Text(ins.headline)
                                .font(Typography.ui(13.5, weight: .medium))
                                .foregroundStyle(Theme.slate900)
                            Text(ins.detail)
                                .font(Typography.ui(11.5))
                                .foregroundStyle(Theme.slate500)
                        }
                    }
                }
                Button(action: {}) {
                    Label("Export to Markdown", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }.ccSecondary()
            }
            .frame(width: 360)
        }
    }

    // MARK: Filters

    private var filtersRow: some View {
        HStack {
            FlowLayout(spacing: 8) {
                ForEach(["All bakes", "Country sourdough", "Last month", "5-star only", "Underproofed"], id: \.self) { f in
                    TagPill(label: f, active: f == filter) { filter = f }
                }
            }
            Spacer()
            Text("\(state.journal.count) entries · ")
                .font(Typography.ui(12)).foregroundStyle(Theme.slate500)
            + Text(String(format: "%.1f", Analytics.avgRating(in: state.journal) ?? 0))
                .font(Typography.mono(12, weight: .semibold))
                .foregroundStyle(Theme.slate700)
            + Text(" avg rating").font(Typography.ui(12)).foregroundStyle(Theme.slate500)
        }
    }

    // MARK: Trend card

    private var trendCard: some View {
        SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker("Country Sourdough · bulk time vs. rating")
                        Text("Longer bulks correlate with better bakes")
                            .font(Typography.display(18, weight: .medium))
                            .foregroundStyle(Theme.slate900)
                    }
                    Spacer()
                    StatusPill(kind: .info, text: "Pattern detected")
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)

                BulkTimeChart(journal: state.journal)
                    .frame(height: 200)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: Month summary

    private var monthSummaryCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 0) {
                Kicker("This month")
                VStack(spacing: 12) {
                    summaryRow("Bakes", "\(state.journal.count)", "+2 vs last month")
                    summaryRow("Avg rating",
                                String(format: "%.1f", Analytics.avgRating(in: state.journal) ?? 0),
                                "↑ 0.4")
                    summaryRow("Avg kitchen temp",
                                String(format: "%.1f°C", Analytics.avgKitchenC(in: state.journal) ?? 0),
                                "1.2°C cooler")
                    summaryRow("Flour used", "5.4kg", "King Arthur 70%")
                }
                .padding(.top, 12)
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String, _ sub: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(Typography.ui(13)).foregroundStyle(Theme.slate700)
                Text(sub).font(Typography.ui(11)).foregroundStyle(Theme.slate500)
            }
            Spacer()
            Text(value)
                .font(Typography.mono(18, weight: .semibold))
                .foregroundStyle(Theme.slate900)
        }
    }
}

// MARK: - Journal card

private struct JournalCard: View {
    let entry: JournalEntry
    let recipe: Recipe?

    var body: some View {
        SurfaceCard(padding: EdgeInsets()) {
            HStack(alignment: .top, spacing: 0) {
                BreadPhoto(assetName: entry.photoAsset, kind: .crumb, height: 96)
                    .frame(width: 120, height: 96)
                    .clipped()
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(entry.date).font(Typography.mono(11.5)).foregroundStyle(Theme.slate500)
                        Text("·").foregroundStyle(Theme.slate500)
                        Text(recipe?.title ?? entry.recipeId)
                            .font(Typography.display(16, weight: .medium))
                            .foregroundStyle(Theme.slate900)
                    }
                    Text(entry.note)
                        .font(Typography.ui(13))
                        .foregroundStyle(Theme.slate600)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 18) {
                        stat("\(Int(entry.hydrationPct))%", "hyd.")
                        stat(CCFormat.duration(entry.bulkMinutes), "bulk")
                        stat("\(Int(entry.kitchenC))°C", "kitchen")
                        Text(entry.diagnosis)
                            .font(Typography.ui(10.5, weight: .medium))
                            .foregroundStyle(Theme.pillNeutFg)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.pillNeutBg, in: Capsule())
                    }
                    .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                Spacer()
                VStack(alignment: .trailing) {
                    StarRating(rating: entry.rating)
                    Spacer()
                    CCIconView(icon: .arrowRight, size: 16, color: Theme.slate400)
                }
                .padding(16)
            }
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        HStack(spacing: 2) {
            Text(v).font(Typography.mono(12, weight: .semibold)).foregroundStyle(Theme.slate700)
            Text(l).font(Typography.ui(12)).foregroundStyle(Theme.slate500)
        }
    }
}

// MARK: - Bulk-time chart

private struct BulkTimeChart: View {
    let journal: [JournalEntry]

    var data: [(bulkMin: Int, rating: Int)] {
        var arr: [(Int, Int)] = journal.filter { $0.recipeId == "country" }.map { ($0.bulkMinutes, $0.rating) }
        // Synthetic priors to make the trend visible (same as the prototype)
        arr.append(contentsOf: [(240, 2), (270, 3), (290, 3),
                                (310, 4), (330, 4), (355, 5),
                                (280, 3), (245, 2)])
        return arr
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pad: CGFloat = 28
            ZStack {
                // Gridlines for rating 1-5
                ForEach(1...5, id: \.self) { r in
                    Path { p in
                        let y = h - pad - CGFloat(r - 1) * ((h - pad * 2) / 4)
                        p.move(to: CGPoint(x: pad, y: y))
                        p.addLine(to: CGPoint(x: w - 10, y: y))
                    }
                    .stroke(Theme.border1,
                            style: r == 5 ? StrokeStyle() : StrokeStyle(dash: [3, 4]))
                    Text("\(r)★")
                        .font(Typography.ui(10))
                        .foregroundStyle(Theme.slate500)
                        .position(x: pad - 14,
                                   y: h - pad - CGFloat(r - 1) * ((h - pad * 2) / 4) + 3)
                }
                ForEach([3, 4, 5, 6], id: \.self) { hr in
                    Text("\(hr)h")
                        .font(Typography.ui(10))
                        .foregroundStyle(Theme.slate500)
                        .position(x: pad + CGFloat(hr - 3) * ((w - pad - 10) / 4),
                                   y: h - 8)
                }
                // Trend line
                Path { p in
                    p.move(to: CGPoint(x: pad + 30, y: h - pad - 5))
                    p.addLine(to: CGPoint(x: w - 40, y: pad + 10))
                }
                .stroke(Theme.primary.opacity(0.6),
                        style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                // Points
                ForEach(Array(data.enumerated()), id: \.offset) { _, d in
                    let x = pad + (CGFloat(d.bulkMin) / 60 - 3) * ((w - pad - 10) / 4)
                    let y = h - pad - CGFloat(d.rating - 1) * ((h - pad * 2) / 4)
                    Circle().fill(Theme.primary.opacity(0.7))
                        .frame(width: 10, height: 10)
                        .position(x: x, y: y)
                }
                // Annotation
                Text("5h+ bulks = 5★")
                    .font(Typography.ui(11, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .position(x: w - 60, y: pad + 12)
            }
        }
    }
}
