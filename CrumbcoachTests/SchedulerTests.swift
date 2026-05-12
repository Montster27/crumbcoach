import XCTest
@testable import Crumbcoach

final class SchedulerTests: XCTestCase {

    private let baseline = Recipe(
        id: "test",
        title: "Test Recipe",
        breadType: .leanYeasted,
        source: .original,
        photo: nil,
        hydrationPct: 70, saltPct: 2, leavenPct: 1,
        totalDoughGrams: 1000, loafCount: 1,
        timeToBake: "5h",
        tags: [],
        twinScald: false,
        preferments: [],
        ingredients: [],
        stages: [
            Stage(kind: .mix,      durationMin: 30,  temperatureC: 24, note: nil),
            Stage(kind: .bulkFold, durationMin: 240, temperatureC: 24, note: nil),
            Stage(kind: .bake,    durationMin: 30,  temperatureC: 230, note: nil),
        ],
        lastBake: nil
    )

    /// At the reference temperature (22°C) and no history bias, schedule
    /// duration equals the sum of stage durations.
    func testForwardScheduleAtReferenceTemp() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let params = ScheduleParams(
            startTime: start, targetEndTime: nil,
            kitchenTempC: 22, coldRetard: true, useSidekick: false,
            historyAdjustmentPct: 0
        )
        let schedule = Scheduler.generateForward(for: baseline, params: params)
        // Mix(30) + Bulk(240 fermenting at 22°C → 1.0x) + Bake(30, fixed) = 300 min
        let actualMinutes = Int(schedule.endTime.timeIntervalSince(start) / 60)
        XCTAssertEqual(actualMinutes, 300, accuracy: 2)
    }

    /// Cooler kitchen → fermenting stages take longer; fixed (bake) doesn't change.
    func testColdKitchenSlowsFermenting() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let params = ScheduleParams(
            startTime: start, targetEndTime: nil,
            kitchenTempC: 12, coldRetard: true, useSidekick: false,
            historyAdjustmentPct: 0
        )
        let schedule = Scheduler.generateForward(for: baseline, params: params)
        // At 12°C, fermenting stages run 2× baseline (Q10).
        // Bake is fixed.  Mix(60) + Bulk(480) + Bake(30) = 570 min.
        let actualMinutes = Int(schedule.endTime.timeIntervalSince(start) / 60)
        XCTAssertEqual(actualMinutes, 570, accuracy: 5)
    }

    /// Reverse schedule must produce chronologically-ordered steps.
    func testReverseScheduleIsOrdered() {
        let target = Date(timeIntervalSince1970: 1_700_000_000)
        let params = ScheduleParams(
            startTime: nil, targetEndTime: target,
            kitchenTempC: 22, coldRetard: true, useSidekick: false
        )
        let schedule = Scheduler.generateReverse(for: baseline, params: params)
        XCTAssertEqual(schedule.steps.count, 3)
        XCTAssertEqual(schedule.steps.first?.kind, .mix)
        XCTAssertEqual(schedule.steps.last?.kind,  .bake)
        // Ends exactly at the requested target.
        XCTAssertEqual(schedule.endTime.timeIntervalSince(target), 0, accuracy: 1)
        // Steps go forward in time.
        for i in 1..<schedule.steps.count {
            XCTAssertGreaterThanOrEqual(schedule.steps[i].start, schedule.steps[i - 1].end.addingTimeInterval(-1))
        }
    }

    /// Skipping cold-retard drops the stage cleanly from the timeline.
    func testColdRetardSkippedWhenDisabled() {
        let recipeWithRetard = Recipe(
            id: "retardtest", title: "Retard Test", breadType: .sourdough,
            source: .original, photo: nil,
            hydrationPct: 75, saltPct: 2, leavenPct: 20,
            totalDoughGrams: 1000, loafCount: 1, timeToBake: "12h",
            tags: [], twinScald: false, preferments: [], ingredients: [],
            stages: [
                Stage(kind: .mix,        durationMin: 30,  temperatureC: 22, note: nil),
                Stage(kind: .bulk,       durationMin: 240, temperatureC: 22, note: nil),
                Stage(kind: .coldRetard, durationMin: 720, temperatureC: 4,  note: nil),
                Stage(kind: .bake,       durationMin: 50,  temperatureC: 230, note: nil),
            ],
            lastBake: nil
        )
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let withRetard    = ScheduleParams(startTime: start, targetEndTime: nil,
                                            kitchenTempC: 22, coldRetard: true, useSidekick: false)
        let withoutRetard = ScheduleParams(startTime: start, targetEndTime: nil,
                                            kitchenTempC: 22, coldRetard: false, useSidekick: false)
        let a = Scheduler.generateForward(for: recipeWithRetard, params: withRetard)
        let b = Scheduler.generateForward(for: recipeWithRetard, params: withoutRetard)
        XCTAssertEqual(a.steps.count, 4)
        XCTAssertEqual(b.steps.count, 3)
        XCTAssertFalse(b.steps.contains(where: { $0.kind == .coldRetard }))
    }
}
