import WidgetKit
import SwiftUI

// Stage 19 — Home Screen + Lock Screen widget for the in-progress bake.
// Reads from the App Group snapshot the main app writes on every state
// change. Three Home Screen sizes (small / medium / large) and the
// `accessoryRectangular` Lock Screen / StandBy widget.
//
// The widget extension can't reach the main app's bundled fonts or asset
// catalog, so the UI uses system fonts + a fixed orange accent that
// matches Theme.primary.

struct ActiveBakeWidget: Widget {
    let kind: String = "ActiveBakeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BakeProvider()) { entry in
            ActiveBakeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Active Bake")
        .description("Current stage, fold counter, and time to the next action.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryInline,
        ])
    }
}

// MARK: - Timeline provider

struct BakeEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct BakeProvider: TimelineProvider {
    /// Placeholder shown in the gallery while the widget loads. A fixed
    /// "rise" stage with a single fold so the layout looks like the real
    /// thing instead of empty bars.
    func placeholder(in context: Context) -> BakeEntry {
        BakeEntry(date: Date(), snapshot: WidgetSnapshot.preview)
    }

    /// Returned to iOS for the widget gallery preview + first paint.
    func getSnapshot(in context: Context, completion: @escaping (BakeEntry) -> Void) {
        completion(BakeEntry(
            date: Date(),
            snapshot: SharedContainer.readWidgetSnapshot() ?? WidgetSnapshot.preview
        ))
    }

    /// Build a timeline with a single entry — the widget body uses
    /// `Text(_:style: .timer)` for the countdown so SwiftUI re-renders the
    /// time without a fresh entry. We re-pin a new entry every 15 minutes
    /// as a safety net for stage transitions that the main app may have
    /// missed (cold launches, killed app, etc.).
    func getTimeline(in context: Context, completion: @escaping (Timeline<BakeEntry>) -> Void) {
        let now = Date()
        let snapshot = SharedContainer.readWidgetSnapshot()
        let entry = BakeEntry(date: now, snapshot: snapshot)
        let refreshAfter = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now
        completion(Timeline(entries: [entry], policy: .after(refreshAfter)))
    }
}

extension WidgetSnapshot {
    /// Static preview data used by the widget gallery + `placeholder`.
    /// Never written back; only ever read.
    static let preview = WidgetSnapshot(
        generatedAt: Date(),
        activeBake: ActiveBakeSummary(
            recipeTitle: "Country Sourdough",
            startedAt: Date().addingTimeInterval(-3 * 3600),
            bakeOutAt: Date().addingTimeInterval(8 * 3600),
            stageName: "Bulk + folds",
            stageIndex: 3,
            stageCount: 8,
            foldsDone: 2,
            totalFolds: 4,
            nextActionAt: Date().addingTimeInterval(14 * 60),
            nextActionLabel: "Fold 3 of 4",
            isComplete: false
        )
    )
}

// MARK: - Top-level view (delegates by family)

struct ActiveBakeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BakeEntry

    var body: some View {
        if let bake = entry.snapshot?.activeBake {
            switch family {
            case .systemSmall:
                smallView(bake: bake)
            case .systemMedium:
                mediumView(bake: bake)
            case .systemLarge:
                largeView(bake: bake)
            case .accessoryRectangular:
                lockScreenRectangular(bake: bake)
            case .accessoryInline:
                lockScreenInline(bake: bake)
            default:
                smallView(bake: bake)
            }
        } else {
            emptyView
        }
    }

    // MARK: Home Screen — small

    @ViewBuilder
    private func smallView(bake: WidgetSnapshot.ActiveBakeSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(.orange).frame(width: 6, height: 6)
                Text(bake.recipeTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(bake.stageName)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(bake.nextActionLabel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(bake.nextActionAt, style: .timer)
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.orange)
        }
        .padding(2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Home Screen — medium

    @ViewBuilder
    private func mediumView(bake: WidgetSnapshot.ActiveBakeSummary) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                    Text(bake.recipeTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(bake.stageName)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(bake.nextActionLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(bake.nextActionAt, style: .timer)
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                if bake.totalFolds > 0 {
                    FoldRing(done: bake.foldsDone, total: bake.totalFolds)
                        .frame(width: 64, height: 64)
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Bake out")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(bake.bakeOutAt, format: .dateTime.hour().minute())
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
        .padding(2)
    }

    // MARK: Home Screen — large

    @ViewBuilder
    private func largeView(bake: WidgetSnapshot.ActiveBakeSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle().fill(.orange).frame(width: 6, height: 6)
                        Text("Active bake")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                    Text(bake.recipeTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer()
                Text(bake.bakeOutAt, format: .dateTime.hour().minute())
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
            }

            Divider()

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Now")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(bake.stageName)
                        .font(.system(size: 22, weight: .semibold))
                        .lineLimit(2)
                    Text("Stage \(bake.stageIndex + 1) of \(bake.stageCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if bake.totalFolds > 0 {
                    FoldRing(done: bake.foldsDone, total: bake.totalFolds)
                        .frame(width: 72, height: 72)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text(bake.nextActionLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(bake.nextActionAt, style: .timer)
                    .font(.system(size: 28, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Lock Screen

    @ViewBuilder
    private func lockScreenRectangular(bake: WidgetSnapshot.ActiveBakeSummary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10))
                Text(bake.recipeTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            Text(bake.stageName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(bake.nextActionLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(bake.nextActionAt, style: .timer)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func lockScreenInline(bake: WidgetSnapshot.ActiveBakeSummary) -> some View {
        // Inline accessory is single-line text + an optional SF Symbol.
        Text("\(Image(systemName: "flame.fill")) \(bake.stageName) · \(bake.nextActionLabel)")
    }

    // MARK: Empty state

    @ViewBuilder
    private var emptyView: some View {
        switch family {
        case .accessoryInline:
            Text("\(Image(systemName: "flame")) No active bake")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("GeekBread")
                    .font(.system(size: 12, weight: .semibold))
                Text("No active bake")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        default:
            VStack(spacing: 6) {
                Image(systemName: "flame")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)
                Text("No active bake")
                    .font(.system(size: 13, weight: .semibold))
                Text("Start one on the Scheduler.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Fold progress ring

private struct FoldRing: View {
    let done: Int
    let total: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.orange.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: Double(done) / Double(max(1, total)))
                .stroke(.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(done)/\(total)")
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                Text("folds")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
