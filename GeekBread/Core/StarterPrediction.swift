import Foundation

// Starter peak prediction: a simple temperature-sensitive model.
// Real version (Code Spec §4.4) would fit per-starter regression to actual
// observed rise data; here we apply a baseline + Q10-style adjustment.

enum StarterPrediction {

    /// Predicted minutes from feed → peak at the given ambient temperature.
    /// Baseline 5h at 24°C; doubles per 10°C cooler.
    static func minutesToPeak(forStarter starter: Starter, ambientC: Double) -> Int {
        let baseline: Double = 300   // 5h at 24°C
        let q10 = pow(2.0, (24.0 - ambientC) / 10.0)
        return Int((baseline * q10).rounded())
    }

    /// Suggested levain build to peak exactly when `mixTime` rolls around.
    /// Returns the build start time + ratio recommendation.
    struct LevainBuild {
        var feedAt: Date
        var ratio: String           // "1:5:5"
        var ambientC: Double
        var minutesToPeak: Int
    }

    static func levainBuild(for starter: Starter, mixTime: Date, ambientC: Double) -> LevainBuild {
        let mins = minutesToPeak(forStarter: starter, ambientC: ambientC)
        let feedAt = Calendar.current.date(byAdding: .minute, value: -mins, to: mixTime) ?? mixTime
        let ratio: String
        if mins > 360 { ratio = "1:3:3" }    // slow rise
        else if mins > 240 { ratio = "1:5:5" }
        else { ratio = "1:10:10" }           // very active starter
        return LevainBuild(feedAt: feedAt, ratio: ratio, ambientC: ambientC, minutesToPeak: mins)
    }

    /// Vacation / fridge planning — return a string description of next steps.
    static func storagePlan(for starter: Starter, awayDays: Int) -> String {
        switch awayDays {
        case 0...3:
            return "Counter-rest is fine. Feed normally before next bake."
        case 4...14:
            return "Refrigerate after a full feed. Pull out 24h before next bake and feed twice."
        default:
            return "Dry a backup or freeze 1:1:1 stiff portions. Revive over 3–4 days."
        }
    }
}
