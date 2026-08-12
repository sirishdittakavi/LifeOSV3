import XCTest

final class LifeOSUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 8))
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// The Home plan must expose every due Task while excluding Tasks whose
    /// start date is in the future. Each generated occurrence appears once.
    func testTodayPlanShowsAllDueTasksExactlyOnceAndExcludesFutureTask() {
        openTodayTasks()

        assertExactlyOneTask(named: "Hitting")
        assertExactlyOneTask(named: "Pitching")
        assertExactlyOneTask(named: "Fielding")
        XCTAssertEqual(app.staticTexts.matching(label: "Future Conditioning").count, 0)
    }

    /// This is the core user journey: open a Task, inspect its complete
    /// schedule, edit it, and see the changed value on returning to the plan.
    func testTaskCanBeOpenedInspectedAndEdited() {
        openTodayTasks()
        task(named: "Hitting").tap()

        XCTAssertTrue(app.navigationBars["Task Details"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["10 minutes"].exists)
        XCTAssertTrue(app.staticTexts["Every day"].exists)

        let edit = app.buttons["task.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 2))
        edit.tap()

        let name = app.textFields["task.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.clearAndType("Hitting Practice")
        app.buttons["task.save"].tap()

        XCTAssertTrue(app.staticTexts["Hitting Practice"].waitForExistence(timeout: 3))
    }

    /// The dashboard card must lead to the fixed Nutrition experience and its
    /// two primary V1 actions: manual entry and weekly planning.
    func testNutritionCardOpensManualEntryAndWeeklyPlan() {
        let nutrition = app.buttons["today.overview.nutrition"]
        scrollToElement(nutrition)
        XCTAssertTrue(nutrition.exists)
        nutrition.tap()

        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["nutrition.addFood"].exists)
        XCTAssertTrue(app.buttons["nutrition.weeklyPlan"].exists)

        app.buttons["nutrition.weeklyPlan"].tap()
        XCTAssertTrue(app.navigationBars["Weekly Meal Plan"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Add to plan"].exists)
        XCTAssertTrue(app.buttons["Add unplanned"].exists)
    }

    /// End-to-end Home behavior for a Goal supported by Daily, 3× Weekly,
    /// and Weekly Tasks. Two are completed; one intentionally remains due.
    func testMixedScheduleGoalShowsPartialCompletionCorrectlyOnHome() {
        completeHomeTask(named: "Hitting")
        completeHomeTask(named: "Pitching")

        let progress = app.descendants(matching: .any)["today.progress"]
        scrollUpToElement(progress)
        XCTAssertTrue(progress.exists)
        XCTAssertEqual(
            progress.label,
            "Today's progress, 67 percent, 2 of 3 Tasks complete"
        )

        let fielding = app.descendants(matching: .any)["today.card.fielding"]
        scrollToElement(fielding)
        XCTAssertTrue(fielding.exists, "The uncompleted weekly Task must remain active on Home")
        // Completed Tasks no longer expose a status/action control at all
        // (there's nothing left to do), so the single-control identifier
        // itself must be gone rather than a specific menu item.
        XCTAssertFalse(app.buttons["today.actions.hitting"].exists)
        XCTAssertFalse(app.buttons["today.actions.pitching"].exists)
        let fieldingActions = app.buttons["today.actions.fielding"]
        XCTAssertTrue(fieldingActions.isHittable, "Expected an active status control for the uncompleted Task")
        fieldingActions.tap()
        XCTAssertTrue(app.buttons["today.done.fielding"].waitForExistence(timeout: 2))
        app.buttons["today.done.fielding"].tap()
        XCTAssertTrue(app.navigationBars["Finish"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()

        let completed = app.buttons["today.completedSection"]
        scrollToElement(completed)
        XCTAssertTrue(completed.exists, "Completed Tasks must remain available in collapsed history")

        scrollUpToElement(app.buttons["today.tasksOverview"])
        app.buttons["today.tasksOverview"].tap()
        XCTAssertTrue(app.navigationBars["Today's Tasks"].waitForExistence(timeout: 3))
        assertExactlyOneTask(named: "Hitting")
        assertExactlyOneTask(named: "Pitching")
        assertExactlyOneTask(named: "Fielding")
    }

    func testAccidentallySkippedTaskCanReturnToTheActiveHomePlan() {
        let actions = app.buttons["today.actions.fielding"]
        scrollToElement(actions)
        XCTAssertTrue(actions.isHittable)
        actions.tap()
        let skip = app.buttons["today.skip.fielding"]
        XCTAssertTrue(skip.waitForExistence(timeout: 2))
        skip.tap()

        let completed = app.buttons["today.completedSection"]
        scrollToElement(completed)
        XCTAssertTrue(completed.isHittable)
        completed.tap()

        // Skipped is the one status with a single obvious next action, so
        // Undo Skip stays a directly-tappable control, not behind a menu.
        let undo = app.buttons["today.undoSkip.fielding"]
        scrollToElement(undo)
        XCTAssertTrue(undo.isHittable, "Skipped Tasks must expose a recovery action")
        undo.tap()

        let restored = app.buttons["today.actions.fielding"]
        scrollToElement(restored)
        XCTAssertTrue(restored.isHittable, "Undo Skip must return the occurrence to Planned")
        restored.tap()
        XCTAssertTrue(app.buttons["today.done.fielding"].waitForExistence(timeout: 2), "Undo Skip must restore the Finish action")
        app.buttons["today.done.fielding"].tap()
        XCTAssertTrue(app.navigationBars["Finish"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()

        let progress = app.descendants(matching: .any)["today.progress"]
        scrollUpToElement(progress)
        XCTAssertEqual(progress.label, "Today's progress, 0 percent, 0 of 3 Tasks complete")
    }

    private func openTodayTasks() {
        let overview = app.buttons["today.tasksOverview"]
        scrollToElement(overview)
        XCTAssertTrue(overview.exists)
        overview.tap()
        XCTAssertTrue(app.navigationBars["Today's Tasks"].waitForExistence(timeout: 3))
    }

    private func task(named name: String) -> XCUIElement {
        let row = app.buttons["today.task.\(name.lowercased())"]
        scrollToElement(row)
        return row
    }

    private func assertExactlyOneTask(named name: String) {
        let row = task(named: name)
        XCTAssertTrue(row.exists, "Expected \(name) in Today's Tasks")
        XCTAssertEqual(
            app.staticTexts.matching(label: name).count, 1,
            "Expected one generated occurrence for \(name)"
        )
    }

    private func completeHomeTask(named name: String) {
        let actions = app.buttons["today.actions.\(name.lowercased())"]
        scrollToElement(actions)
        XCTAssertTrue(actions.isHittable, "Expected an active status control for \(name)")
        actions.tap()

        let done = app.buttons["today.done.\(name.lowercased())"]
        XCTAssertTrue(done.waitForExistence(timeout: 2), "Expected an active Done action for \(name)")
        done.tap()

        XCTAssertTrue(app.navigationBars["Finish"].waitForExistence(timeout: 3))
        let save = app.buttons["completion.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 2))
        save.tap()
        XCTAssertFalse(app.navigationBars["Finish"].waitForExistence(timeout: 1))
    }

    private func scrollToElement(_ element: XCUIElement, attempts: Int = 8) {
        var remaining = attempts
        while (!element.exists || !element.isHittable) && remaining > 0 {
            app.swipeUp()
            remaining -= 1
        }
    }

    private func scrollUpToElement(_ element: XCUIElement, attempts: Int = 8) {
        var remaining = attempts
        while (!element.exists || !element.isHittable) && remaining > 0 {
            app.swipeDown()
            remaining -= 1
        }
    }
}

private extension XCUIElementQuery {
    func matching(label: String) -> XCUIElementQuery {
        matching(NSPredicate(format: "label == %@", label))
    }
}

private extension XCUIElement {
    func clearAndType(_ text: String) {
        guard let current = value as? String else {
            typeText(text)
            return
        }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        typeText(text)
    }
}
