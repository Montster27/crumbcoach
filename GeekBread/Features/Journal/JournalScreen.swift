import SwiftUI

// Journal — filter chips + bulk-time scatter chart + journal list +
// month-summary stats on the right rail.

struct JournalScreen: View {
    var state: AppState
    @State private var filter: String = "All bakes"
    @State private var shareItems: [Any]? = nil

    private var filteredEntries: [JournalEntry] {
        switch filter {
        case "Country sourdough":
            return state.journal.filter { $0.recipeId == "country" }
        case "Last month":
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            return state.journal.filter { $0.bakedAt >= cutoff }
        case "5-star only":
            return state.journal.filter { $0.rating == 5 }
        case "Underproofed":
            return state.journal.filter { $0.diagnosis.lowercased().contains("underproof") }
        default:
            return state.journal
        }
    }

    /// Country Sourdough is the only recipe whose bulk-time-vs-rating trend
    /// the BulkTimeChart knows how to plot. Hide the card until the user has
    /// enough of those bakes (3) for the trend to mean something.
    private var hasCountryTrend: Bool {
        state.journal.filter { $0.recipeId == "country" }.count >= 3
    }

    var body: some View {
        if state.journal.isEmpty {
            EmptyJournalView { state.goTo(.scheduler) }
        } else {
            HStack(alignment: .top, spacing: 24) {
                // LEFT
                VStack(spacing: 16) {
                    filtersRow
                    if hasCountryTrend { trendCard }
                    ForEach(filteredEntries) { entry in
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
                    Button {
                        let md = RecipeExporter.markdown(
                            forJournal: state.journal,
                            recipeLookup: { state.recipe($0) },
                            units: state.units
                        )
                        shareItems = [md]
                    } label: {
                        Label("Export to Markdown", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }.ccSecondary()
                }
                .frame(width: 360)
            }
            .sheet(isPresented: Binding(
                get: { shareItems != nil },
                set: { if !$0 { shareItems = nil } }
            )) {
                if let items = shareItems {
                    ShareActivitySheet(items: items)
                }
            }
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
                    summaryRow("Bakes", "\(state.journal.count)")
                    summaryRow("Avg rating",
                                String(format: "%.1f", Analytics.avgRating(in: state.journal) ?? 0))
                    summaryRow("Avg kitchen temp",
                                String(format: "%.1f°C", Analytics.avgKitchenC(in: state.journal) ?? 0))
                }
                .padding(.top, 12)
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(Typography.ui(13)).foregroundStyle(Theme.slate700)
            Spacer()
            Text(value)
                .font(Typography.mono(18, weight: .semibold))
                .foregroundStyle(Theme.slate900)
        }
    }
}

// MARK: - Empty state

private struct EmptyJournalView: View {
    let onScheduler: () -> Void
    var body: some View {
        SurfaceCard {
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.primaryTint).frame(width: 64, height: 64)
                    CCIconView(icon: .graph, size: 24, color: Theme.primary)
                }
                VStack(spacing: 4) {
                    Text("No bakes logged yet")
                        .font(Typography.display(20, weight: .medium))
                        .foregroundStyle(Theme.slate900)
                    Text("Finish a bake and log it from the Active Bake screen — patterns, ratings, and insights will appear here.")
                        .font(Typography.ui(13))
                        .foregroundStyle(Theme.slate600)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                Button(action: onScheduler) {
                    Label("Open Scheduler", systemImage: "clock")
                }.ccPrimary()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
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
                BreadPhoto(assetName: entry.photoAsset, kind: .crumb, height: 120)
                    .frame(width: 120)
                    .frame(maxHeight: .infinity)
                    .clipped()
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(entry.dateDisplay).font(Typography.mono(11.5)).foregroundStyle(Theme.slate500)
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
        journal.filter { $0.recipeId == "country" }.map { ($0.bulkMinutes, $0.rating) }
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

#Preview("Journal") {
    JournalScreen(state: AppState(persistence: PersistenceController(filename: "preview-journal.json")))
        .padding()
        .background(Theme.surface1)
        .frame(width: 1100, height: 800)
}
