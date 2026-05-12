import ActivityKit
import WidgetKit
import SwiftUI

// Lock-screen + Dynamic Island UI for the in-progress bake. Mirrors the
// `liveActivityCard` preview on the in-app Active Bake screen (recipe title,
// stage, fold progress, time-to-next-action) so users see the same shape
// inside and outside the app.
//
// iPad doesn't have a Dynamic Island, but iOS 17+ shares the lock-screen +
// StandBy presentation with iPhone, and Apple's contract requires every
// region to be implemented even if a given device won't render it. We keep
// each region tight so future iPhone visitors get a useful compact glance.

struct ActiveBakeLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ActiveBakeAttributes.self) { context in
            // Lock-screen presentation — what most users will glance at on
            // the iPad. Mirrors the in-app live-activity preview card.
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded — when the user taps the island.
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeading(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailing(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    expandedCenter(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottom(context: context)
                }
            } compactLeading: {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                Text(compactTrailing(context.state))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
            }
            .keylineTint(.orange)
        }
    }

    // MARK: Lock-screen view

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<ActiveBakeAttributes>) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Brand mark — matches the in-app live-activity preview chip.
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.orange)
                .frame(width: 36, height: 36)
                .overlay(
                    Text("cc")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .kerning(-0.4)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.recipeTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(subtitleText(context.state))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(timeToNextLabel(context.state))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                Text(context.state.isComplete ? "Ready to log" : "Bake out")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    // MARK: Dynamic Island regions

    @ViewBuilder
    private func expandedLeading(context: ActivityViewContext<ActiveBakeAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(context.attributes.recipeTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(context.state.stageName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func expandedTrailing(context: ActivityViewContext<ActiveBakeAttributes>) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(timeToNextLabel(context.state))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
            Text(context.state.isComplete ? "Ready to log" : "Next action")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func expandedCenter(context: ActivityViewContext<ActiveBakeAttributes>) -> some View {
        EmptyView()
    }

    @ViewBuilder
    private func expandedBottom(context: ActivityViewContext<ActiveBakeAttributes>) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<context.state.totalFolds, id: \.self) { i in
                Capsule()
                    .fill(i < context.state.foldsDone ? Color.orange : Color.secondary.opacity(0.25))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Copy helpers

    private func subtitleText(_ state: ActiveBakeAttributes.ContentState) -> String {
        if state.isComplete { return "Ready to log" }
        if state.totalFolds > 0 && state.foldsDone < state.totalFolds {
            return "\(state.stageName) · fold \(state.foldsDone + 1) of \(state.totalFolds)"
        }
        return state.stageName
    }

    private func timeToNextLabel(_ state: ActiveBakeAttributes.ContentState) -> String {
        if state.isComplete { return "Done" }
        let m = state.minutesToNextAction
        if m <= 0 { return "now" }
        if m < 60 { return "\(m)m" }
        let h = m / 60
        let rem = m % 60
        return rem == 0 ? "\(h)h" : "\(h)h \(rem)m"
    }

    private func compactTrailing(_ state: ActiveBakeAttributes.ContentState) -> String {
        if state.isComplete { return "✓" }
        return timeToNextLabel(state)
    }
}
