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
        // LabeledContent rows expose their value as the accessibility
        // VALUE, not the label, so a plain staticTexts[...] label lookup
        // can miss them — match either.
        XCTAssertTrue(existsAnywhere("10 minutes"), "Expected the Duration row's value")
        XCTAssertTrue(existsAnywhere("Every day"), "Expected the Repeats row's value")

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

    // NOTE (LifeOS XCUITest release pass): `testNutritionCardOpensManualEntryAndWeeklyPlan`
    // was removed here. It asserted on `nutrition.addFood`/`nutrition.weeklyPlan` and a
    // "Weekly Meal Plan" screen — the legacy FoodTrackerView/FoodEntry workflow, which the
    // Nutrition tile no longer opens (Nutrition V1 uses MealEntry/MealTemplate/WaterEntry/
    // NutritionGoal via NutritionDashboardView instead). FoodTrackerView.swift still exists
    // in the codebase but is UI-unreachable — nothing sets `showingFoodTracker`. The test
    // failed outright (couldn't even find the tile via the wrong query type). Its only
    // still-relevant assertion — tapping the Nutrition tile opens current Nutrition UI — is
    // already covered, correctly, by NutritionReviewUITests.swift's `openNutritionDashboard()`.

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
        XCTAssertTrue(fieldingActions.isHittable, "Expected an active one-tap completion control for the uncompleted Task")

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

    func testSkipRecoveryIsDeferredToTaskDetail() throws {
        throw XCTSkip("The approved Today redesign removes Skip from the daily surface. Add and test task-detail recovery controls in the dedicated task-detail implementation chunk.")
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
        // Scoped to the row's own stable identifier, not a global label
        // search — the same Task name legitimately also renders on the
        // underlying Today screen (still present in the accessibility tree
        // behind this sheet), so `app.staticTexts.matching(label:)` across
        // the whole app would double-count a single generated occurrence.
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "identifier == %@", "today.task.\(name.lowercased())")).count, 1,
            "Expected exactly one generated occurrence for \(name)"
        )
    }

    private func completeHomeTask(named name: String) {
        let actions = app.buttons["today.actions.\(name.lowercased())"]
        scrollToElement(actions)
        XCTAssertTrue(actions.isHittable, "Expected an active status control for \(name)")
        actions.tap()
        XCTAssertFalse(app.navigationBars["Finish"].waitForExistence(timeout: 1))
    }

    /// Matches `text` as a substring of either the accessibility label OR
    /// value, anywhere in the app's current element tree — robust against
    /// LabeledContent rows, which can combine "Label, Value" into one
    /// accessibility label/value string rather than exposing "Value" alone.
    private func existsAnywhere(_ text: String) -> Bool {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", text, text))
            .firstMatch.exists
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
