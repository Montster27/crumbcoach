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

    struct StageHistoryEntry: Codable, Hashable {
        var stageIndex: Int
        var status: StepStatus
        var note: String?
    }

    struct BakePhoto: Identifiable, Codable, Hashable {
        var id = UUID()
        var time: String       // "7:14 PM"
        var assetName: String? // sample asset
        var note: String
    }
}
