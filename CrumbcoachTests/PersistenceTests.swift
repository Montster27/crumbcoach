import XCTest
@testable import Crumbcoach

/// PersistenceController round-trip: write state → re-read it → identical.
final class PersistenceTests: XCTestCase {

    private var tempController: PersistenceController!

    override func setUp() {
        super.setUp()
        // Isolate each test in its own scratch file.
        let unique = "test-\(UUID().uuidString.prefix(8)).json"
        tempController = PersistenceController(filename: String(unique))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempController.fileURL)
        super.tearDown()
    }

    func testSaveAndLoadRoundTrip() {
        let original = PersistedState(
            recipes: SampleRecipes.all,
            starters: SampleStarters.all,
            journal: SampleJournal.all,
            activeBake: nil,
            kitchenTempC: 21.5,
            kitchenHumidityPct: 60,
            ovenStatus: "Off",
            userName: "Test Baker",
            selectedRecipeId: "country"
        )
        tempController.save(original)

        guard let loaded: PersistedState = tempController.load() else {
            XCTFail("Failed to load persisted state")
            return
        }

        XCTAssertEqual(loaded.recipes.count,  original.recipes.count)
        XCTAssertEqual(loaded.starters.count, original.starters.count)
        XCTAssertEqual(loaded.journal.count,  original.journal.count)
        XCTAssertEqual(loaded.userName,       original.userName)
        XCTAssertEqual(loaded.kitchenTempC,   original.kitchenTempC, accuracy: 0.001)
        XCTAssertEqual(loaded.selectedRecipeId, original.selectedRecipeId)
    }

    /// A corrupt file should not crash; load() returns nil and quarantines it.
    func testCorruptFileFallsBack() throws {
        try "not json".write(to: tempController.fileURL, atomically: true, encoding: .utf8)
        let loaded: PersistedState? = tempController.load()
        XCTAssertNil(loaded)
        // The bad file should have been renamed.
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempController.fileURL.path))
    }
}
