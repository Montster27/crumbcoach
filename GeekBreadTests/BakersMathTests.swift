import XCTest
@testable import GeekBread

final class BakersMathTests: XCTestCase {

    // Country Sourdough: 800 BF + 200 WW + 750 water + 200 levain + 20 salt.
    // With levain stored as a single `.leaven` (not decomposed), expected:
    //   totalFlour = 1000
    //   hydration  = 750 / 1000 = 75%
    //   salt       = 20 / 1000 = 2%
    func testCountrySourdoughPercentages() {
        let recipe = SampleRecipes.country
        let p = BakersMath.computePercentages(for: recipe)
        XCTAssertEqual(p.totalFlourGrams, 1000, accuracy: 0.01)
        XCTAssertEqual(p.hydrationPct,    75,   accuracy: 0.1)
        XCTAssertEqual(p.saltPct,         2.0,  accuracy: 0.05)
        XCTAssertEqual(p.leavenPct,       20,   accuracy: 0.5)
    }

    // Hokkaido has a yudane (8% flour) + tangzhong (6% flour) preferment block.
    // Total flour across preferment + main = 800g; preferment flour = 14% = 112g.
    func testHokkaidoPrefermentFlour() {
        let recipe = SampleRecipes.hokkaido
        let p = BakersMath.computePercentages(for: recipe)
        XCTAssertEqual(p.totalFlourGrams,      800, accuracy: 0.5)
        XCTAssertEqual(p.prefermentFlourPct,   14,  accuracy: 0.5)
    }

    // Scaling to a different total weight should preserve every percentage.
    func testScalePreservesPercentages() {
        let recipe = SampleRecipes.country
        let target: Double = 2730     // 1.5×
        let scaled = BakersMath.scale(recipe, toTotalGrams: target)
        let before = BakersMath.computePercentages(for: recipe)
        let after  = BakersMath.computePercentages(for: scaled)
        XCTAssertEqual(after.hydrationPct, before.hydrationPct, accuracy: 0.5)
        XCTAssertEqual(after.saltPct,      before.saltPct,      accuracy: 0.05)
        XCTAssertEqual(after.totalDoughGrams, target,           accuracy: 5)
    }

    // Adjusting hydration to a new % should make the computed hydration match.
    func testAdjustHydration() {
        let recipe = SampleRecipes.country
        let adjusted = BakersMath.adjustHydration(recipe, to: 80)
        let p = BakersMath.computePercentages(for: adjusted)
        XCTAssertEqual(p.hydrationPct, 80, accuracy: 0.5)
    }

    // Hydration warnings flip at ±5 pp from the original target.
    func testHydrationWarningThresholds() {
        XCTAssertEqual(BakersMath.warning(originalHydration: 75, newHydration: 75), .none)
        XCTAssertEqual(BakersMath.warning(originalHydration: 75, newHydration: 80), .none)
        XCTAssertEqual(BakersMath.warning(originalHydration: 75, newHydration: 81), .higher)
        XCTAssertEqual(BakersMath.warning(originalHydration: 75, newHydration: 70), .none)
        XCTAssertEqual(BakersMath.warning(originalHydration: 75, newHydration: 69), .lower)
    }
}
