import Foundation

// Schedule + ActiveBake models. Mirrors Schedule / ScheduleStep / StepStatus
// from the Rust core spec (§3.3), with Swift-native Date types.

enum StepStatus: String, Codable, Hashable {
    case pending, active, done, skipped, adjusted, upcoming
}

struct ScheduleStep: Identifiable, Codable, Hashable {
    var id = UUID()
    var stageIndex: Int          // index into Recipe.stages
    var kind: StageKind
    var start: Date
    var end: Date
    var status: StepStatus
    var note: String?
}

struct Schedule: Identifiable, Codable, Hashable {
    var id = UUID()
    var recipeId: String
    var startTime: Date
    var endTime: Date
    var kitchenTempC: Double
    var starterId: String?
    var steps: [ScheduleStep]
}

// MARK: - Active bake (in-progress)

struct ActiveBake: Identifiable, Codable, Hashable {
    var id = UUID()
    var recipeId: String
    var startedAt: Date
    var bakeOutAt: Date
    var currentStageIndex: Int
    var stageProgress: Double    // 0...1 within the current stage
    var kitchenTempC: Double
    var starterId: String?
    var history: [StageHistoryEntry]
    var stagePhotos: [Int: [BakePhoto]] = [:]
    var foldsDone: Int = 0
    var totalFolds: Int = 4
    /// The schedule the user confirmed at startBake, rebalanced on every
    /// advance/skip so the remaining stages and their notifications stay
    /// anchored to wall-clock reality. Optional + default = nil so persisted
    /// pre-Stage-8 bakes decode cleanly; reminders for those bakes can't be
    /// rescheduled, but everything else still works.
    var schedule: Schedule? = nil

    struct StageHistoryEntry: Codable, Hashable {
        var stageIndex: Int
        var status: StepStatus
        var note: String?
        // Wall-clock entry/exit captured by AppState's stage-transition path
        // so the journal can report real elapsed times instead of the
        // recipe's baseline duration. Optional so pre-Stage-3 persisted
        // bakes decode cleanly.
        var enteredAt: Date? = nil
        var exitedAt: Date? = nil
    }

    struct BakePhoto: Identifiable, Codable, Hashable {
        var id = UUID()
        var time: String       // "7:14 PM"
        var assetName: String? // sample asset
        var note: String
    }

    /// True once every history entry is either done or explicitly skipped
    /// AND at least one stage was actually done — keeps a spam-skip from
    /// producing a journal entry for a bake the user never executed.
    var isComplete: Bool {
        guard !history.isEmpty else { return false }
        let allTerminal = history.allSatisfy { $0.status == .done || $0.status == .skipped }
        let anyDone = history.contains { $0.status == .done }
        return allTerminal && anyDone
    }
}
