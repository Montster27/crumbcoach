import SwiftUI

// iPhone Journal — single scrollable feed: summary → filters → optional
// trend chart → entry list → insights. Export action lives in the
// toolbar overflow menu so the action button doesn't crowd the cards.

struct PhoneJournalScreen: View {
    var state: AppState
    @State private var filter: String = "All bakes"
    @State private var shareItems: [Any]? = nil

    private let filters = ["All bakes", "Country sourdough", "Last month", "5-star only", "Underproofed"]

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

    private var hasCountryTrend: Bool {
        state.journal.filter { $0.recipeId == "country" }.count >= 3
    }

    var body: some View {
        Group {
            if state.journal.isEmpty {
                PhoneEmptyJournalView { state.goTo(.scheduler) }
            } else {
                ScrollView {
                    VStack(spacing: PhoneTheme.cardSpacing) {
                        summaryCard

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(filters, id: \.self) { f in
                                    TagPill(label: f, active: f == filter) { filter = f }
                                }
                            }
                            .padding(.horizontal, PhoneTheme.screenHPad)
                            .padding(.vertical, 2)
                        }
                        .padding(.horizontal, -PhoneTheme.screenHPad)

                        if hasCountryTrend && filter == "All bakes" {
                            trendCard
                        }

                        ForEach(filteredEntries) { entry in
                            PhoneJournalCard(entry: entry, recipe: state.recipe(entry.recipeId)) {
                                state.openRecipe(entry.recipeId)
                            }
                        }

                        if !state.insights.isEmpty {
                            insightsSection
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, PhoneTheme.screenHPad)
                    .padding(.top, PhoneTheme.screenVPad)
                    .padding(.bottom, PhoneTheme.sectionSpacing)
                }
            }
        }
        .background(Theme.surface1)
        .toolbar {
            if !state.journal.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let md = RecipeExporter.markdown(
                            forJournal: state.journal,
                            recipeLookup: { state.recipe($0) },
                            units: state.units
                        )
                        shareItems = [md]
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export journal")
                }
            }
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

    // MARK: Compact "this month" summary

    private var summaryCard: some View {
        SurfaceCard(padding: EdgeInsets()) {
            HStack(spacing: 0) {
                summaryColumn(label: "Bakes",
                               value: "\(state.journal.count)")
                Rectangle().fill(Theme.border1).frame(width: 1)
                summaryColumn(label: "Avg rating",
                               value: String(format: "%.1f", Analytics.avgRating(in: state.journal) ?? 0))
                Rectangle().fill(Theme.border1).frame(width: 1)
                summaryColumn(label: "Kitchen °C",
                               value: String(format: "%.1f", Analytics.avgKitchenC(in: state.journal) ?? 0))
            }
            .frame(height: 76)
        }
    }

    private func summaryColumn(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Typography.mono(20, weight: .semibold))
                .foregroundStyle(Theme.slate900)
                .lineLimit(1)
            Kicker(label, size: 9.5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Trend card (compact portrait-friendly chart)

    private var trendCard: some View {
        SurfaceCard(padding: EdgeInsets()) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker("Country sourdough · bulk vs rating")
                        Text("Longer bulks correlate with better bakes")
                            .font(Typography.display(15, weight: .medium))
                            .foregroundStyle(Theme.slate900)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(.horizontal, PhoneTheme.cardPad)
                .padding(.vertical, 12)

                PhoneBulkTimeChart(journal: state.journal)
                    .frame(height: 160)
                    .padding(.horizontal, PhoneTheme.cardPad)
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: Insights

    private var insightsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Kicker("Insights", color: Theme.accent)
                Spacer()
            }
            ForEach(Array(state.insights.enumerated()), id: \.offset) { _, ins in
                SurfaceCard {
                    HStack(alignment: .top, spacing: 10) {
                        CCIconView(icon: .sparkle, size: 14, color: Theme.accent)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ins.headline)
                                .font(Typography.ui(13, weight: .medium))
                                .foregroundStyle(Theme.slate900)
                            Text(ins.detail)
                                .font(Typography.ui(11.5))
                                .foregroundStyle(Theme.slate500)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

// MARK: - Journal entry card (compact)

private struct PhoneJournalCard: View {
    let entry: JournalEntry
    let recipe: Recipe?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            SurfaceCard(padding: EdgeInsets()) {
                HStack(alignment: .top, spacing: 0) {
                    BreadPhoto(assetName: entry.photoAsset, kind: .crumb, height: 96)
                        .frame(width: 96, height: 96)
                        .clipped()

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(entry.dateDisplay)
                                .font(Typography.mono(10.5))
                                .foregroundStyle(Theme.slate500)
                            StarRating(rating: entry.rating, size: 9)
                        }
                        Text(recipe?.title ?? entry.recipeId)
                            .font(Typography.display(15, weight: .medium))
                            .foregroundStyle(Theme.slate900)
                            .lineLimit(1)
                        Text(entry.note.isEmpty ? "No notes" : entry.note)
                            .font(Typography.ui(11.5))
                            .foregroundStyle(Theme.slate600)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 10) {
                            stat("\(Int(entry.hydrationPct))%", "hyd")
                            stat(CCFormat.duration(entry.bulkMinutes), "bulk")
                            stat("\(Int(entry.kitchenC))°", "kit")
                        }
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func stat(_ v: String, _ l: String) -> some View {
        HStack(spacing: 2) {
            Text(v)
                .font(Typography.mono(10.5, weight: .semibold))
                .foregroundStyle(Theme.slate700)
            Text(l)
                .font(Typography.ui(10))
                .foregroundStyle(Theme.slate500)
        }
    }
}

// MARK: - Empty state

private struct PhoneEmptyJournalView: View {
    let onScheduler: () -> Void
    var body: some View {
        ScrollView {
            SurfaceCard {
                VStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Theme.primaryTint).frame(width: 56, height: 56)
                        CCIconView(icon: .graph, size: 22, color: Theme.primary)
                    }
                    VStack(spacing: 4) {
                        Text("No bakes logged yet")
                            .font(Typography.display(20, weight: .medium))
                            .foregroundStyle(Theme.slate900)
                        Text("Finish a bake and log it from the Bake tab — patterns and insights will appear here.")
                            .font(Typography.ui(13))
                            .foregroundStyle(Theme.slate600)
                            .multilineTextAlignment(.center)
                    }
                    Button(action: onScheduler) {
                        Label("Open Scheduler", systemImage: "clock")
                            .frame(maxWidth: .infinity)
                    }
                    .ccPrimary()
                }
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, PhoneTheme.screenHPad)
            .padding(.top, 36)
        }
    }
}

// MARK: - Compact bulk-time chart (portrait variant of iPad's BulkTimeChart)

private struct PhoneBulkTimeChart: View {
    let journal: [JournalEntry]

    private var data: [(bulkMin: Int, rating: Int)] {
        journal.filter { $0.recipeId == "country" }.map { ($0.bulkMinutes, $0.rating) }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let padL: CGFloat = 22
            let padB: CGFloat = 22
            ZStack {
                ForEach(1...5, id: \.self) { r in
                    Path { p in
                        let y = h - padB - CGFloat(r - 1) * ((h - padB - 6) / 4)
                        p.move(to: CGPoint(x: padL, y: y))
                        p.addLine(to: CGPoint(x: w - 6, y: y))
                    }
                    .stroke(Theme.border1,
                            style: r == 5 ? StrokeStyle() : StrokeStyle(dash: [3, 4]))
                    Text("\(r)★")
                        .font(Typography.ui(9))
                        .foregroundStyle(Theme.slate500)
                        .position(x: padL - 12,
                                   y: h - padB - CGFloat(r - 1) * ((h - padB - 6) / 4) + 2)
                }
                ForEach([3, 4, 5, 6], id: \.self) { hr in
                    Text("\(hr)h")
                        .font(Typography.ui(9))
                        .foregroundStyle(Theme.slate500)
                        .position(x: padL + CGFloat(hr - 3) * ((w - padL - 6) / 4),
                                   y: h - 8)
                }
                Path { p in
                    p.move(to: CGPoint(x: padL + 24, y: h - padB - 4))
                    p.addLine(to: CGPoint(x: w - 32, y: 12))
                }
                .stroke(Theme.primary.opacity(0.6),
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                ForEach(Array(data.enumerated()), id: \.offset) { _, d in
                    let x = padL + (CGFloat(d.bulkMin) / 60 - 3) * ((w - padL - 6) / 4)
                    let y = h - padB - CGFloat(d.rating - 1) * ((h - padB - 6) / 4)
                    Circle().fill(Theme.primary.opacity(0.75))
                        .frame(width: 8, height: 8)
                        .position(x: x, y: y)
                }
            }
        }
    }
}

#Preview("Phone Journal") {
    NavigationStack {
        PhoneJournalScreen(state: AppState(persistence: PersistenceController(filename: "preview-phone-journal.json")))
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.large)
    }
}
