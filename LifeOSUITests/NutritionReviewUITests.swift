import XCTest

/// End-to-end smoke coverage for the Nutrition module's navigation and data
/// flow — the class of regression unit/component tests can't catch (a menu
/// wired to the wrong sheet, a screen unreachable from Area Hub, a saved
/// target not reflected on the Dashboard). Deterministic, light-mode only,
/// no screenshots, no external simulator state — safe to run in the normal
/// suite. Relies on the DEBUG/-ui-testing fixture in LifeOSApp.swift.
final class NutritionReviewUITests: XCTestCase {
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

    /// Today → Area Hub → Nutrition Dashboard → Quick Actions → Meal
    /// Logging → using a fixed-total Meal Template logs a MealEntry with
    /// that template's exact totals, reflected immediately on the Dashboard.
    func testUsingAMealTemplateLogsItsFixedTotalsAndUpdatesTheDashboard() throws {
        openNutritionDashboard()

        // Quick Actions is reachable and offers all three logging paths.
        let quickActions = app.buttons["Log Meal, Water, or Weight"]
        XCTAssertTrue(quickActions.exists)
        quickActions.tap()
        XCTAssertTrue(app.navigationBars["Log something"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Log Meal"].exists)
        XCTAssertTrue(app.buttons["Water"].exists)
        XCTAssertTrue(app.buttons["Weight"].exists)
        app.buttons["Cancel"].tap()

        // Meal Logging -> My Templates shows the fixture's two Lamb Shank
        // portion templates as independent fixed totals.
        let dinnerRow = app.staticTexts["Dinner"]
        scrollToElement(dinnerRow)
        dinnerRow.tap()
        XCTAssertTrue(app.navigationBars["Dinner"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Coles Lamb Shank + 0.5 cup rice"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["873 kcal"].exists)
        XCTAssertTrue(app.staticTexts["Coles Lamb Shank + 1 cup rice"].exists, "a different portion is a separate template, not derived from the first")
        XCTAssertTrue(app.staticTexts["1046 kcal"].exists)

        app.staticTexts["Coles Lamb Shank + 0.5 cup rice"].tap()
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 3), "using a template returns to the Dashboard")

        // The logged Dinner now shows the template's exact totals, copied
        // verbatim — no scaling or calculation.
        let dinnerMealRow = app.staticTexts["Dinner"]
        scrollToElement(dinnerMealRow)
        XCTAssertTrue(app.staticTexts["873 kcal"].waitForExistence(timeout: 3))

        closeDashboard()
    }

    /// Nutrition Targets: setting Protein = 220g/day is reflected on the
    /// Dashboard immediately, and clearing the other targets removes their
    /// progress framing without affecting Protein's.
    func testProteinTargetIsUserDefinedOptionalAndAppliesImmediately() throws {
        openNutritionDashboard()
        openTargetsScreen()

        setTargetField("Protein", to: "220")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["102g of 220g"].waitForExistence(timeout: 3), "the Dashboard must reflect the newly saved daily target immediately")

        openTargetsScreen()
        clearTargetField("Calories")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["102g of 220g"].exists, "Protein's target must be unaffected by clearing Calories")
        XCTAssertTrue(app.staticTexts["1067 today"].waitForExistence(timeout: 3), "Calories must show a plain value with no target framing once cleared, never \"/0\"")

        closeDashboard()
    }

    // MARK: - Helpers

    /// Tapping the Today Nutrition tile opens the Nutrition Dashboard
    /// directly — the generic Area Hub (Tasks/Goals/Measurements) has
    /// nothing relevant for Nutrition, so it's skipped rather than being an
    /// extra intermediate screen.
    private func openNutritionDashboard() {
        let nutritionTile = app.descendants(matching: .any)["today.overview.nutrition"]
        XCTAssertTrue(nutritionTile.waitForExistence(timeout: 6), "Today Nutrition Plan tile must exist")
        scrollToElement(nutritionTile)
        nutritionTile.tap()
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 3), "Nutrition Dashboard should open directly, with no Area Hub screen in between")
    }

    private func closeDashboard() {
        if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }
    }

    private func openTargetsScreen() {
        let targetsChip = app.buttons["Targets"]
        XCTAssertTrue(targetsChip.waitForExistence(timeout: 3))
        targetsChip.tap()
        XCTAssertTrue(app.navigationBars["Nutrition Targets"].waitForExistence(timeout: 3))
    }

    /// Right-aligned numeric fields: a plain `.tap()` from XCUITest can
    /// land the synthetic touch (and so the caret) to the left of the
    /// visible digits rather than at the end, so a backspace-count-based
    /// clear can leave stray characters (a real finger tap doesn't have
    /// this problem — this is purely an XCUITest quirk). Double-tap
    /// selects the whole numeric token instead, so typing always replaces
    /// it cleanly regardless of where the caret would have landed.
    private func setTargetField(_ label: String, to value: String) {
        let field = app.textFields.matching(NSPredicate(format: "placeholderValue == 'Optional'")).element(
            boundBy: fieldIndex(for: label)
        )
        field.doubleTap()
        if let current = field.value as? String, !current.isEmpty, current != "Optional" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        }
        field.typeText(value)
        app.staticTexts["Nutrition Targets"].tap()
    }

    private func clearTargetField(_ label: String) {
        let field = app.textFields.matching(NSPredicate(format: "placeholderValue == 'Optional'")).element(
            boundBy: fieldIndex(for: label)
        )
        field.doubleTap()
        if let current = field.value as? String, !current.isEmpty, current != "Optional" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        }
        app.staticTexts["Nutrition Targets"].tap()
    }

    private func fieldIndex(for label: String) -> Int {
        switch label {
        case "Protein": return 0
        case "Calories": return 1
        case "Carbs": return 2
        case "Fat": return 3
        case "Water": return 4
        default: return 0
        }
    }

    private func scrollToElement(_ element: XCUIElement, attempts: Int = 8) {
        var remaining = attempts
        while (!element.exists || !element.isHittable) && remaining > 0 {
            app.swipeUp()
            remaining -= 1
        }
    }
}
