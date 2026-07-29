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

    // SwiftUI's searchable modifier exposes a search field to XCUITest.
    private func revealSearchBar() -> XCUIElement {
        return app.searchFields.firstMatch
    }

    private func search(for query: String) {
        let searchBar = revealSearchBar()
        XCTAssertTrue(searchBar.waitForExistence(timeout: 5))
        searchBar.tap()
        searchBar.typeText(query)
        XCTAssertEqual(searchBar.value as? String, query)
    }

    private func assertSearchResults(
        visible: [String],
        hidden: [String],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        for name in hidden {
            XCTAssertTrue(
                app.staticTexts[name].waitForNonExistence(timeout: 5),
                "Expected '\(name)' to be filtered out",
                file: file,
                line: line
            )
        }
        for name in visible {
            XCTAssertTrue(
                app.staticTexts[name].exists,
                "Expected '\(name)' to remain in the filtered results",
                file: file,
                line: line
            )
        }
    }

    private func cancelSearch(file: StaticString = #file, line: UInt = #line) {
        let cancelButton = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(
            cancelButton.waitForExistence(timeout: 3),
            "Expected the search Cancel button to appear",
            file: file,
            line: line
        )
        cancelButton.tap()
    }

    private func assertFullSeededListIsVisible(
        file: StaticString = #file,
        line: UInt = #line
    ) {
        for name in ["Barbell Squat", "Bench Press", "Overhead Press"] {
            XCTAssertTrue(
                app.staticTexts[name].waitForExistence(timeout: 5),
                "Expected '\(name)' to be restored after cancelling search",
                file: file,
                line: line
            )
        }
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
        searchBar.tap()
        searchBar.typeText("Squat")
        assertSearchResults(
            visible: ["Barbell Squat"],
            hidden: ["Bench Press", "Overhead Press"]
        )
        cancelSearch()
        assertFullSeededListIsVisible()
    }

    func testSearchForExercise() throws {
        navigateToExercises()
        search(for: "Bench")
        assertSearchResults(
            visible: ["Bench Press"],
            hidden: ["Barbell Squat", "Overhead Press"]
        )
    }

    func testSearchFiltersResults() throws {
        navigateToExercises()
        search(for: "Press")
        assertSearchResults(
            visible: ["Bench Press", "Overhead Press"],
            hidden: ["Barbell Squat"]
        )
    }

    func testSearchCancelRestoresFullList() throws {
        navigateToExercises()
        search(for: "XYZ_NOMATCH")
        assertSearchResults(
            visible: [],
            hidden: ["Barbell Squat", "Bench Press", "Overhead Press"]
        )
        cancelSearch()
        assertFullSeededListIsVisible()
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
