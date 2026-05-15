import Foundation

// Forward and reverse scheduling.  Q10 rule: fermentation roughly doubles per
// 10 °C — applied across all "fermenting" stages.  Bake / scalds / mix stages
// keep their baseline duration regardless of ambient temp.

struct ScheduleParams {
    var startTime: Date?            // forward mode: now
    var targetEndTime: Date?        // reverse mode: bread out of oven at...
    var kitchenTempC: Double
    var coldRetard: Bool            // optional cold retard overnight
    var useSidekick: Bool
    var historyAdjustmentPct: Double = 0   // e.g. +15% if user history shows slower kitchen
}

enum Scheduler {

    static let fermentingStages: Set<StageKind> = [
        .feedLevain, .prepPoolish, .autolyse, .mix, .bulkFold, .bulk, .preShape,
        .divide, .divideShape, .finalShape, .proof, .finalProof,
    ]
    static let fixedStages: Set<StageKind> = [
        .prepYudane, .cookTangzhong, .addButter, .coldRetard, .bake,
    ]

    /// Apply Q10 + history adjustment to a stage's baseline duration in minutes.
    static func adjustedDuration(for stage: Stage,
                                 ambientC: Double,
                                 historyPct: Double = 0) -> Int {
        let baseline = Double(stage.durationMin)
        if fixedStages.contains(stage.kind) {
            return Int(baseline)
        }
        // Q10 = 2 per 10°C of ambient deviation from a 22°C reference.
        // 1°C cooler ≈ +7% time; 1°C warmer ≈ −7% time.
        let q10Factor = pow(2.0, (22.0 - ambientC) / 10.0)
        let historyFactor = 1.0 + historyPct / 100.0
        return Int((baseline * q10Factor * historyFactor).rounded())
    }

    /// Forward schedule — start at `params.startTime` (or now), generate stages.
    static func generateForward(for recipe: Recipe, params: ScheduleParams) -> Schedule {
        let start = params.startTime ?? Date()
        var steps: [ScheduleStep] = []
        var cursor = start

        for (i, stage) in recipe.stages.enumerated() {
            // Optionally skip cold retard if user didn't opt in
            if !params.coldRetard && stage.kind == .coldRetard { continue }

            let dur = adjustedDuration(for: stage, ambientC: params.kitchenTempC,
                                       historyPct: params.historyAdjustmentPct)
            let end = Calendar.current.date(byAdding: .minute, value: dur, to: cursor) ?? cursor
            steps.append(ScheduleStep(
                stageIndex: i,
                kind: stage.kind,
                start: cursor,
                end: end,
                status: .pending,
                note: stage.note
            ))
            cursor = end
        }

        return Schedule(
            recipeId: recipe.id,
            startTime: start,
            endTime: cursor,
            kitchenTempC: params.kitchenTempC,
            starterId: nil,
            steps: steps
        )
    }

    /// Reverse schedule — work backwards from `params.targetEndTime`.
    /// Returns the implied start time + the same step list as `generateForward`.
    static func generateReverse(for recipe: Recipe, params: ScheduleParams) -> Schedule {
        let target = params.targetEndTime ?? Date()

        var revSteps: [ScheduleStep] = []
        var cursor = target

        for (i, stage) in recipe.stages.enumerated().reversed() {
            if !params.coldRetard && stage.kind == .coldRetard { continue }
            let dur = adjustedDuration(for: stage, ambientC: params.kitchenTempC,
                                       historyPct: params.historyAdjustmentPct)
            let start = Calendar.current.date(byAdding: .minute, value: -dur, to: cursor) ?? cursor
            revSteps.append(ScheduleStep(
                stageIndex: i,
                kind: stage.kind,
                start: start,
                end: cursor,
                status: .pending,
                note: stage.note
            ))
            cursor = start
        }

        return Schedule(
            recipeId: recipe.id,
            startTime: cursor,                   // earliest start
            endTime: target,
            kitchenTempC: params.kitchenTempC,
            starterId: nil,
            steps: Array(revSteps.reversed())    // chronological order
        )
    }

    /// Re-flow remaining stages if the user is running late / early on the
    /// current stage.  Done stages stay fixed; remaining stages slide.
    static func rebalance(_ schedule: Schedule, currentStageIndex idx: Int,
                          newCurrentEnd: Date,
                          ambientC: Double,
                          historyPct: Double = 0,
                          recipe: Recipe) -> Schedule {
        var out = schedule
        guard idx >= 0 && idx < out.steps.count else { return out }
        out.steps[idx].end = newCurrentEnd
        var cursor = newCurrentEnd
        for i in (idx + 1)..<out.steps.count {
            let stage = recipe.stages[out.steps[i].stageIndex]
            let dur = adjustedDuration(for: stage, ambientC: ambientC, historyPct: historyPct)
            out.steps[i].start = cursor
            out.steps[i].end = Calendar.current.date(byAdding: .minute, value: dur, to: cursor) ?? cursor
            cursor = out.steps[i].end
        }
        out.endTime = cursor
        return out
    }
}
