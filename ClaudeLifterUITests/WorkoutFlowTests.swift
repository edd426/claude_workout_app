import XCTest

final class WorkoutFlowTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchForTesting()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testTemplatePushDayAppearsOnHome() throws {
        XCTAssertTrue(app.staticTexts["Push Day"].waitForExistence(timeout: 5))
    }

    func testStartWorkoutFromTemplate() throws {
        let pushDay = app.staticTexts["Push Day"]
        XCTAssertTrue(pushDay.waitForExistence(timeout: 5))
        pushDay.tap()
        XCTAssertTrue(app.navigationBars["Push Day"].waitForExistence(timeout: 5))
    }

    /// Regression test: tapping Start Workout on TemplatePreviewView must
    /// actually transition the UI into ActiveWorkoutView, not silently no-op
    /// because a pushed preview shadowed the root-level swap.
    func testStartWorkoutTransitionsOutOfPreview() throws {
        app.startWorkoutFromTemplate("Push Day")
        // cancelWorkout and finishWorkout toolbar buttons exist only in
        // ActiveWorkoutView. startWorkoutFromPreview exists only in the
        // preview. If we're truly in ActiveWorkoutView, we see the first
        // two and NOT the third.
        XCTAssertTrue(app.buttons["cancelWorkout"].waitForExistence(timeout: 5),
                      "Expected Cancel toolbar button (only in ActiveWorkoutView)")
        XCTAssertTrue(app.buttons["finishWorkout"].exists,
                      "Expected Finish toolbar button (only in ActiveWorkoutView)")
        XCTAssertFalse(app.buttons["startWorkoutFromPreview"].exists,
                       "Should no longer be on TemplatePreviewView")
    }

    func testActiveWorkoutShowsExercises() throws {
        app.startWorkoutFromTemplate("Push Day")
        XCTAssertTrue(app.staticTexts["Bench Press"].waitForExistence(timeout: 5))
    }

    func testActiveWorkoutShowsFinishButton() throws {
        app.startWorkoutFromTemplate("Push Day")
        XCTAssertTrue(app.buttons["finishWorkout"].waitForExistence(timeout: 5))
    }

    func testActiveWorkoutShowsAddExerciseButton() throws {
        app.startWorkoutFromTemplate("Push Day")
        XCTAssertTrue(app.buttons["addExerciseToWorkout"].waitForExistence(timeout: 5))
    }

    func testCompleteASet() throws {
        app.startWorkoutFromTemplate("Push Day")
        let completeButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'completeSet_'")
        ).element(boundBy: 0)
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))
        completeButton.tap()
        // Rest timer or completed state should appear
        XCTAssertTrue(app.buttons["finishWorkout"].exists)
    }

    func testUncompletingSetCancelsRestTimer() throws {
        app.startWorkoutFromTemplate("Push Day")
        let completeButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'completeSet_'")
        ).element(boundBy: 0)
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))

        completeButton.tap()
        let restTime = app.staticTexts["Rest time remaining"]
        XCTAssertTrue(restTime.waitForExistence(timeout: 2))

        completeButton.tap()
        let timerRemoved = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: restTime
        )
        wait(for: [timerRemoved], timeout: 2)
    }

    func testWeightFieldIsAccessible() throws {
        app.startWorkoutFromTemplate("Push Day")
        let weightField = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'weight_'")
        ).element(boundBy: 0)
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
    }

    func testRepsFieldIsAccessible() throws {
        app.startWorkoutFromTemplate("Push Day")
        let repsField = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH 'reps_'")
        ).element(boundBy: 0)
        XCTAssertTrue(repsField.waitForExistence(timeout: 5))
    }

    func testFinishWorkoutShowsSummary() throws {
        app.startWorkoutFromTemplate("Push Day")
        // Must complete a set before Finish is enabled.
        let completeButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'completeSet_'")
        ).element(boundBy: 0)
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))
        completeButton.tap()
        let finish = app.buttons["finishWorkout"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        XCTAssertTrue(app.staticTexts["Workout Complete!"].waitForExistence(timeout: 5))
    }

    func testWorkoutSummaryDoneButtonDismisses() throws {
        app.startWorkoutFromTemplate("Push Day")
        let completeButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'completeSet_'")
        ).element(boundBy: 0)
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))
        completeButton.tap()
        let finish = app.buttons["finishWorkout"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        XCTAssertTrue(app.buttons["summaryDone"].waitForExistence(timeout: 5))
        app.buttons["summaryDone"].tap()
        XCTAssertTrue(app.navigationBars["ClaudeLifter"].waitForExistence(timeout: 5))
    }

    /// Regression test for #123.
    ///
    /// The summary sheet has always been freely swipe-dismissable, but only its
    /// Done button ended the workout. Swiping it away therefore left the user
    /// inside a workout that was already saved and synced — and because the old
    /// `isFinished` flag was one-way, no later Finish tap could bring the sheet
    /// back. This is the exact gesture that caused the reported bug.
    func testSwipingTheSummaryAwayStillLeavesTheWorkout() throws {
        app.startWorkoutFromTemplate("Push Day")
        let completeButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'completeSet_'")
        ).element(boundBy: 0)
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))
        completeButton.tap()

        let finish = app.buttons["finishWorkout"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        XCTAssertTrue(app.staticTexts["Workout Complete!"].waitForExistence(timeout: 5))

        // Drag the sheet down from near its top rather than tapping Done. A
        // plain swipeDown() would scroll the summary's ScrollView instead.
        let sheetTop = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let offscreen = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        sheetTop.press(forDuration: 0.1, thenDragTo: offscreen)

        XCTAssertTrue(
            app.navigationBars["ClaudeLifter"].waitForExistence(timeout: 5),
            "Home must be underneath once the workout has been saved"
        )
        XCTAssertFalse(
            app.buttons["finishWorkout"].exists,
            "Swipe-dismissing the summary must not strand the user in a saved workout"
        )
    }

    /// Regression test for #124. Repeated taps used to re-enter the finish path,
    /// re-stamping completedAt and re-running PR detection each time.
    func testRapidRepeatedFinishTapsProduceOneWorkout() throws {
        app.startWorkoutFromTemplate("Push Day")
        let completeButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'completeSet_'")
        ).element(boundBy: 0)
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))
        completeButton.tap()

        let finish = app.buttons["finishWorkout"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        if finish.exists { finish.tap() }
        if finish.exists { finish.tap() }

        XCTAssertTrue(app.buttons["summaryDone"].waitForExistence(timeout: 5))
        app.buttons["summaryDone"].tap()
        XCTAssertTrue(app.navigationBars["ClaudeLifter"].waitForExistence(timeout: 5))

        // Three taps must produce exactly one session dated today.
        //
        // Counted by row identifier, not by matching "Push Day" text: TabView
        // keeps the Home tab alive and its template picker renders a "Push Day"
        // row too. Filtered to today because the suite launches with
        // -seedTestData and history already contains older sessions. And
        // History is visited only once, because HistoryListView loads its data
        // behind an `if vm == nil` guard and serves a stale list on any later
        // visit (filed separately).
        app.tabBars.buttons["History"].tap()
        let historyRows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'historyRow_'")
        )
        XCTAssertTrue(historyRows.firstMatch.waitForExistence(timeout: 5))

        let today = Date.now.formatted(date: .abbreviated, time: .omitted)
        let rows = (0..<historyRows.count).map { historyRows.element(boundBy: $0).label }
        let todaysRows = rows.filter { $0.contains(today) }
        XCTAssertEqual(
            todaysRows.count, 1,
            "Repeated Finish taps must not produce duplicate history entries. Rows: \(rows)"
        )
    }
}
