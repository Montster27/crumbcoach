import XCTest
@testable import Crumbcoach

final class ConversionTests: XCTestCase {

    /// Tangzhong conversion should preserve total flour weight: anything we
    /// remove from the main dough should land in the preferment.
    func testTangzhongPreservesTotalFlour() {
        // Shokupan already has a tangzhong; strip it first so the "before"
        // baseline reflects the recipe the conversion will actually
        // operate on (otherwise we'd be comparing post-conversion total
        // against the original-recipe total that already included a
        // tangzhong's worth of flour).
        var stripped = SampleRecipes.shokupan
        stripped.preferments.removeAll()
        stripped.stages.removeAll { $0.kind == .cookTangzhong }
        let totalBefore = BakersMath.computePercentages(for: stripped).totalFlourGrams

        let (converted, _) = Conversion.convertToTangzhong(stripped, flourPctOfTotal: 6)
        let totalAfter = BakersMath.computePercentages(for: converted).totalFlourGrams
        XCTAssertEqual(totalAfter, totalBefore, accuracy: 1.0)
    }

    /// Yudane conversion at 20% should remove 20% of flour from the main dough
    /// and add it back as a preferment.
    func testYudaneAt20Percent() {
        let recipe = SampleRecipes.brioche
        let (converted, _) = Conversion.convertToYudane(recipe, flourPctOfTotal: 20)
        XCTAssertTrue(converted.preferments.contains(where: { $0.id == "yudane" }))
        let p = BakersMath.computePercentages(for: converted)
        XCTAssertEqual(p.prefermentFlourPct, 20, accuracy: 1)
    }

    /// Multi-flour recipes should have the preferment flour taken
    /// proportionally from each flour, not entirely from the first.
    func testProportionalFlourSubtraction() {
        let recipe = SampleRecipes.country
        // Country has 80% bread flour + 20% whole wheat.
        let (converted, _) = Conversion.convertToTangzhong(recipe, flourPctOfTotal: 10)
        let breadFlour = converted.ingredients.first { $0.name.lowercased().contains("bread flour") }!
        let wwFlour    = converted.ingredients.first { $0.name.lowercased().contains("whole-wheat") }!
        // After taking 10% of total (100g), bread should be 720g and WW 180g.
        XCTAssertEqual(breadFlour.weightGrams, 720, accuracy: 1)
        XCTAssertEqual(wwFlour.weightGrams,    180, accuracy: 1)
    }

    /// Yeasted → sourdough swaps the yeast for a levain and adds a feed stage.
    func testYeastedToSourdough() {
        let recipe = SampleRecipes.baguette
        let converted = Conversion.yeastedToSourdough(recipe)
        XCTAssertEqual(converted.breadType, .sourdough)
        XCTAssertFalse(converted.ingredients.contains { $0.name.lowercased().contains("yeast") })
        XCTAssertTrue(converted.ingredients.contains { $0.name.lowercased().contains("levain") })
        XCTAssertTrue(converted.stages.contains(where: { $0.kind == .feedLevain }))
    }
}
