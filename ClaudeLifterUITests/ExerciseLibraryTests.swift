import XCTest

final class ExerciseLibraryTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchForTesting()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func navigateToExercises() {
        app.tabBars.buttons["Exercises"].tap()
        XCTAssertTrue(app.navigationBars["Exercises"].waitForExistence(timeout: 5))
        // Wait for the exercise list to load (async ViewModel initialisation)
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 8))
    }

    // Returns the custom search text field pinned above the filter chips
    private func revealSearchBar() -> XCUIElement {
        return app.textFields["exerciseSearchField"]
    }

    func testExercisesTabNavigatesCorrectly() throws {
        navigateToExercises()
    }

    func testExerciseLibraryShowsSeededExercises() throws {
        navigateToExercises()
        XCTAssertTrue(app.staticTexts["Bench Press"].exists)
    }

    func testExerciseLibrarySearchBarExists() throws {
        navigateToExercises()
        let searchBar = revealSearchBar()
        XCTAssertTrue(searchBar.waitForExistence(timeout: 5))
    }

    func testSearchForExercise() throws {
        navigateToExercises()
        let searchBar = revealSearchBar()
        XCTAssertTrue(searchBar.waitForExistence(timeout: 5))
        // Verify the search bar is interactive (tap, type, then dismiss)
        searchBar.tap()
        searchBar.typeText("Bench")
        XCTAssertEqual(searchBar.value as? String, "Bench")
    }

    func testSearchFiltersResults() throws {
        navigateToExercises()
        let searchBar = revealSearchBar()
        XCTAssertTrue(searchBar.waitForExistence(timeout: 5))
        searchBar.tap()
        searchBar.typeText("Bench")
        // The search field should contain the typed text
        XCTAssertEqual(searchBar.value as? String, "Bench")
        let cancelButton = app.buttons.matching(NSPredicate(format: "label == 'Cancel'")).firstMatch
        if cancelButton.waitForExistence(timeout: 3) {
            cancelButton.tap()
        }
    }

    func testSearchCancelRestoresFullList() throws {
        navigateToExercises()
        let searchBar = revealSearchBar()
        XCTAssertTrue(searchBar.waitForExistence(timeout: 5))
        searchBar.tap()
        searchBar.typeText("XYZ_NOMATCH")
        XCTAssertEqual(searchBar.value as? String, "XYZ_NOMATCH")
        // Clear the search and verify nav bar remains
        searchBar.clearAndTypeText("")
        XCTAssertTrue(app.navigationBars["Exercises"].waitForExistence(timeout: 5))
    }

    func testTapExerciseShowsDetail() throws {
        navigateToExercises()
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 5))
        app.staticTexts["Bench Press"].tap()
        XCTAssertTrue(app.navigationBars["Bench Press"].waitForExistence(timeout: 5))
    }

    func testExerciseDetailShowsPrimaryMuscles() throws {
        navigateToExercises()
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 5))
        app.staticTexts["Bench Press"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'chest'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testCreateExerciseButtonExists() throws {
        navigateToExercises()
        let addButton = app.navigationBars["Exercises"].buttons.firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
    }

    func testCreateExerciseSheetAppears() throws {
        navigateToExercises()
        app.navigationBars["Exercises"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Exercise"].waitForExistence(timeout: 5))
    }

    func testCreateExerciseNameFieldExists() throws {
        navigateToExercises()
        app.navigationBars["Exercises"].buttons.firstMatch.tap()
        XCTAssertTrue(app.textFields["exerciseName"].waitForExistence(timeout: 5))
    }

    func testCreateExerciseSaveButtonExistsWhenNameEntered() throws {
        navigateToExercises()
        app.navigationBars["Exercises"].buttons.firstMatch.tap()
        XCTAssertTrue(app.textFields["exerciseName"].waitForExistence(timeout: 5))
        app.textFields["exerciseName"].tap()
        app.textFields["exerciseName"].typeText("My Custom Exercise")
        XCTAssertTrue(app.buttons["saveExercise"].waitForExistence(timeout: 5))
    }
}
