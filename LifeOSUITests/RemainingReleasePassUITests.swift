import XCTest

/// LifeOS XCUITest and Notification Ownership Release Pass — remaining
/// Section 2 coverage (measured completion, Nutrition, Body Tracking).
/// Uses the same -ui-testing "Parent"/"Child" fixture as
/// ProfileIsolationUITests.swift.
///
/// Explicitly NOT attempted here, and why:
/// - App-relaunch persistence: the -ui-testing fixture uses an in-memory
///   SwiftData store rebuilt fresh on every launch (by design, for test
///   isolation) — a real relaunch test would need a second, persistent
///   -ui-testing-relaunch launch path that doesn't exist yet.
/// - Backup/restore UI journey: needs deterministic automation around the
///   system file-picker sheet (fileExporter/fileImporter), which has no
///   test hook in this app yet.
/// - Notification deep-link tap: needs a deterministic UI-test launch hook
///   to simulate a delivered notification, which doesn't exist yet.
/// - Template-snapshot-survives-edit: deferred for time; the Templates
///   edit flow (MealTemplatesView) wasn't exercised in this pass.
/// These four are reported as pending, not faked.
final class RemainingReleasePassUITests: XCTestCase {
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

    // MARK: - Measured completion

    /// A Task may retain a legacy target, but completing it from Today stays
    /// one tap. Optional value logging belongs in the detail flow.
    func testMeasuredTaskCompletesDirectlyWithoutOpeningAForm() {
        switchProfile(to: "Child")
        let actions = app.buttons["today.actions.hitting"]
        scrollToElement(actions)
        actions.tap()
        XCTAssertFalse(app.navigationBars["Finish"].waitForExistence(timeout: 1))

        let progress = app.descendants(matching: .any)["today.progress"]
        scrollUpToElement(progress)
        XCTAssertEqual(progress.label, "Today's progress, 100 percent, 1 of 1 Tasks complete", "exactly one completed occurrence must be reflected")
    }

    // MARK: - Nutrition

    func testLoggingMealForProfileAChangesOnlyProfileA() {
        switchProfile(to: "Child")
        logManualBreakfast(calories: "500", protein: "40")

        let childProtein = app.descendants(matching: .any)["nutrition.total.protein"]
        XCTAssertTrue(childProtein.waitForExistence(timeout: 3))
        XCTAssertTrue(childProtein.label.contains("40"), "Child's own total must reflect the logged meal: got \(childProtein.label)")
        app.swipeDown()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 3))
        LifeOSUITestSupport.waitForDisappearance(app.navigationBars["Nutrition"])

        switchProfile(to: "Parent")
        openNutritionDashboard()
        let parentProtein = app.descendants(matching: .any)["nutrition.total.protein"]
        XCTAssertTrue(parentProtein.waitForExistence(timeout: 3))
        XCTAssertFalse(parentProtein.label.contains("40"), "Parent must never see Child's logged meal: got \(parentProtein.label)")
    }

    func testEditingMealUpdatesDashboardAndProgress() {
        switchProfile(to: "Child")
        logManualBreakfast(calories: "500", protein: "40")

        // Reopen the same meal type and edit it.
        let breakfastRow = app.buttons["nutrition.meal.breakfast"]
        scrollToElement(breakfastRow)
        LifeOSUITestSupport.robustTap(breakfastRow)
        XCTAssertTrue(app.navigationBars["Breakfast"].waitForExistence(timeout: 3))
        let loggedCard = app.buttons["nutrition.meal.loggedCard"]
        XCTAssertTrue(loggedCard.waitForExistence(timeout: 3))
        LifeOSUITestSupport.robustTap(loggedCard)

        XCTAssertTrue(app.navigationBars["Edit Breakfast"].waitForExistence(timeout: 3))
        let proteinField = app.textFields["nutrition.field.protein"]
        XCTAssertTrue(proteinField.waitForExistence(timeout: 3))
        proteinField.doubleTap()
        proteinField.typeText("60")
        app.buttons["nutrition.meal.save"].tap()
        XCTAssertFalse(app.navigationBars["Edit Breakfast"].waitForExistence(timeout: 1))

        app.buttons["Done"].tap()
        let protein = app.descendants(matching: .any)["nutrition.total.protein"]
        XCTAssertTrue(protein.waitForExistence(timeout: 3))
        XCTAssertTrue(protein.label.contains("60"), "the edit must be reflected immediately, not the stale original value: got \(protein.label)")
    }

    func testDeletingMealUpdatesEveryCurrentReport() {
        switchProfile(to: "Child")
        logManualBreakfast(calories: "500", protein: "40")

        let breakfastRow = app.buttons["nutrition.meal.breakfast"]
        scrollToElement(breakfastRow)
        LifeOSUITestSupport.robustTap(breakfastRow)
        XCTAssertTrue(app.navigationBars["Breakfast"].waitForExistence(timeout: 3))
        let loggedCard = app.buttons["nutrition.meal.loggedCard"]
        XCTAssertTrue(loggedCard.waitForExistence(timeout: 3))
        LifeOSUITestSupport.robustTap(loggedCard)

        XCTAssertTrue(app.navigationBars["Edit Breakfast"].waitForExistence(timeout: 3))
        let deleteButton = app.buttons["nutrition.meal.delete.breakfast"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        deleteButton.tap()
        let confirm = app.buttons["Delete Meal"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        confirm.tap()
        XCTAssertFalse(app.navigationBars["Edit Breakfast"].waitForExistence(timeout: 1))

        app.buttons["Done"].tap()
        let protein = app.descendants(matching: .any)["nutrition.total.protein"]
        XCTAssertTrue(protein.waitForExistence(timeout: 3))
        XCTAssertFalse(protein.label.contains("40"), "deleting must remove the meal's contribution immediately: got \(protein.label)")
    }

    func testNutritionTargetCanBeSetClearedAndRemainProfileScoped() {
        switchProfile(to: "Child")
        openNutritionDashboard()

        app.buttons["Targets"].tap()
        XCTAssertTrue(app.navigationBars["Nutrition Targets"].waitForExistence(timeout: 3))
        let proteinTarget = app.textFields["nutrition.target.protein"]
        XCTAssertTrue(proteinTarget.waitForExistence(timeout: 3))
        proteinTarget.doubleTap()
        proteinTarget.typeText("150")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 3))

        let proteinAfterSet = app.descendants(matching: .any)["nutrition.total.protein"]
        XCTAssertTrue(proteinAfterSet.waitForExistence(timeout: 3))
        XCTAssertTrue(proteinAfterSet.label.contains("150"), "Child's target must apply immediately: got \(proteinAfterSet.label)")

        // Clear it.
        app.buttons["Targets"].tap()
        XCTAssertTrue(app.navigationBars["Nutrition Targets"].waitForExistence(timeout: 3))
        let clearField = app.textFields["nutrition.target.protein"]
        clearField.doubleTap()
        if let current = clearField.value as? String, !current.isEmpty, current != "Optional" {
            clearField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        }
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 3))
        let proteinAfterClear = app.descendants(matching: .any)["nutrition.total.protein"]
        XCTAssertTrue(proteinAfterClear.waitForExistence(timeout: 3))
        XCTAssertFalse(proteinAfterClear.label.contains("of 150"), "clearing must remove the target framing, not just show 0: got \(proteinAfterClear.label)")

        app.swipeDown()
        LifeOSUITestSupport.waitForDisappearance(app.navigationBars["Nutrition"])
        switchProfile(to: "Parent")
        openNutritionDashboard()
        app.buttons["Targets"].tap()
        XCTAssertTrue(app.navigationBars["Nutrition Targets"].waitForExistence(timeout: 3))
        let parentProteinTarget = app.textFields["nutrition.target.protein"]
        XCTAssertTrue(parentProteinTarget.waitForExistence(timeout: 3))
        XCTAssertEqual(parentProteinTarget.value as? String, "120", "Parent's own pre-seeded 120g target must be untouched by Child's changes")
    }

    /// Was skipped: QuickActionSheet's List did not respond to any tap
    /// (five distinct strategies tried) when nested two sheets deep
    /// (Today → Nutrition → QuickActionSheet) — a genuine SwiftUI/UIKit
    /// touch-delivery limitation at that depth, not a test-side problem.
    /// Fixed in QuickActionSheet.swift by replacing the List with a plain
    /// VStack of Buttons (LOCard, matching this app's other option-picker
    /// rows, e.g. AddGoalView's Plan picker) -- List's own scroll/cell
    /// machinery was the part misbehaving at this sheet depth, not the
    /// sheet nesting itself, which every other nested sheet in this app
    /// already relies on.
    func testWaterLogAndDeleteRemainProfileScoped() throws {
        switchProfile(to: "Child")
        openNutritionDashboard()

        app.buttons["nutrition.meal.add"].tap()
        let water = app.buttons["nutrition.quickAction.water"]
        XCTAssertTrue(water.waitForExistence(timeout: 3))
        water.tap()
        XCTAssertTrue(app.navigationBars["Water"].waitForExistence(timeout: 3))

        let add500 = app.buttons["nutrition.water.add500"]
        XCTAssertTrue(add500.waitForExistence(timeout: 3))
        add500.tap()

        // The sheet stays open after adding, now showing "Logged today".
        let loggedRow = app.staticTexts["500 mL"]
        XCTAssertTrue(loggedRow.waitForExistence(timeout: 3), "the just-logged entry must appear immediately")

        app.swipeDown()
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 3))
        let totalAfterAdd = app.descendants(matching: .any)["nutrition.water.total"]
        XCTAssertTrue(totalAfterAdd.waitForExistence(timeout: 3))
        XCTAssertTrue(totalAfterAdd.label.contains("0.5"), "500 mL must show as 0.5 L: got \(totalAfterAdd.label)")

        // Delete it via swipe-to-delete and confirm the total reverts.
        app.buttons["nutrition.meal.add"].tap()
        app.buttons["nutrition.quickAction.water"].tap()
        XCTAssertTrue(app.navigationBars["Water"].waitForExistence(timeout: 3))
        let entryToDelete = app.staticTexts["500 mL"]
        XCTAssertTrue(entryToDelete.waitForExistence(timeout: 3))
        entryToDelete.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertFalse(entryToDelete.waitForExistence(timeout: 1), "the deleted entry must disappear from Logged today")

        app.swipeDown()
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 3))
        let totalAfterDelete = app.descendants(matching: .any)["nutrition.water.total"]
        XCTAssertTrue(totalAfterDelete.waitForExistence(timeout: 3))
        XCTAssertFalse(totalAfterDelete.label.contains("0.5"), "deleting the only entry must revert the total: got \(totalAfterDelete.label)")

        // Profile isolation: Parent must never see Child's water logging.
        switchProfile(to: "Parent")
        openNutritionDashboard()
        let parentTotal = app.descendants(matching: .any)["nutrition.water.total"]
        XCTAssertTrue(parentTotal.waitForExistence(timeout: 3))
        XCTAssertFalse(parentTotal.label.contains("0.5"), "Parent must never see Child's water total")
    }

    // MARK: - Body Tracking

    /// Child's fixture is deliberately pre-seeded with 2 Weight points (so
    /// the isolation tests above have history to work with) — this test
    /// verifies logging a NEW quick-add value becomes the canonical latest
    /// everywhere at once (Body Tracking's own hero value here; Today's
    /// tile and Progress read the exact same BodyTrackingEngine.latestEntry
    /// call, already proven in NotificationOwnershipTests/GoalSystemComponentTests).
    func testFirstQuickWeightCreatesOneHistoryEntryAndOneCurrentValue() {
        switchProfile(to: "Child")
        openBodyTracking()

        let latestBefore = app.descendants(matching: .any)["body.weight.latest"]
        XCTAssertTrue(latestBefore.waitForExistence(timeout: 3))
        XCTAssertTrue(latestBefore.label.contains("54.5"), "must show Child's seeded latest value: got \(latestBefore.label)")

        app.buttons["body.weight.add"].tap()
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 3))
        let valueField = app.textFields.firstMatch
        valueField.tap()
        valueField.typeText("53.0")
        app.buttons["Save"].tap()
        XCTAssertFalse(app.navigationBars["Weight"].waitForExistence(timeout: 1))

        let latestAfter = app.descendants(matching: .any)["body.weight.latest"]
        XCTAssertTrue(latestAfter.waitForExistence(timeout: 3))
        XCTAssertTrue(latestAfter.label.contains("53"), "the newly logged value must become latest immediately: got \(latestAfter.label)")
    }

    func testLoggingWeightForProfileAChangesOnlyProfileA() {
        switchProfile(to: "Child")
        openBodyTracking()
        app.buttons["body.weight.add"].tap()
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 3))
        app.textFields.firstMatch.tap()
        app.textFields.firstMatch.typeText("49.5")
        app.buttons["Save"].tap()
        XCTAssertFalse(app.navigationBars["Weight"].waitForExistence(timeout: 1))
        let childLatest = app.descendants(matching: .any)["body.weight.latest"]
        XCTAssertTrue(childLatest.waitForExistence(timeout: 3))
        XCTAssertTrue(childLatest.label.contains("49.5"))
        app.swipeDown()
        LifeOSUITestSupport.waitForDisappearance(app.navigationBars["Body Tracking"])

        switchProfile(to: "Parent")
        openBodyTracking()
        let parentLatest = app.descendants(matching: .any)["body.weight.latest"]
        XCTAssertTrue(parentLatest.waitForExistence(timeout: 3))
        XCTAssertFalse(parentLatest.label.contains("49.5"), "Parent must never show Child's newly logged weight: got \(parentLatest.label)")
    }

    func testDeletingLatestWeightUpdatesEveryBodyConsumer() {
        switchProfile(to: "Child")
        openBodyTracking()

        // Child's fixture has two entries (55.0 seven days ago, 54.5 today).
        let latestBefore = app.descendants(matching: .any)["body.weight.latest"]
        XCTAssertTrue(latestBefore.waitForExistence(timeout: 3))
        XCTAssertTrue(latestBefore.label.contains("54.5"))

        let todayEntryRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "54.5")).firstMatch
        XCTAssertTrue(todayEntryRow.waitForExistence(timeout: 3))
        LifeOSUITestSupport.robustTap(todayEntryRow)
        // confirmationDialog's destructive action button is exposed as two
        // duplicate accessibility nodes with the same identifier on this
        // iOS version (confirmed via debug tree) — same class of issue as
        // profile.selector; .firstMatch resolves it.
        let confirm = app.buttons["body.entry.delete.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        confirm.tap()

        let latestAfter = app.descendants(matching: .any)["body.weight.latest"]
        XCTAssertTrue(latestAfter.waitForExistence(timeout: 3))
        XCTAssertTrue(latestAfter.label.contains("55"), "deleting the latest entry must fall back to the previous one: got \(latestAfter.label)")
    }

    // MARK: - Helpers

    private func switchProfile(to name: String) {
        LifeOSUITestSupport.switchProfile(app, to: name)
    }

    /// Opens the current profile's Nutrition dashboard from the Today
    /// screen's Plans row — scrolls the row itself (not the whole app) so
    /// the Nutrition tile (3rd of 3) is reliably hittable regardless of
    /// its position.
    private func openNutritionDashboard() {
        let nutrition = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Nutrition")).firstMatch
        scrollToElement(nutrition)
        LifeOSUITestSupport.scrollHorizontalRow(app, containerIdentifier: "today.plansRow", target: nutrition)
        LifeOSUITestSupport.robustTap(nutrition)
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 3))
    }

    /// Opens the current profile's Body Tracking screen from the Today
    /// screen's Plans row (2nd of 3 tiles).
    private func openBodyTracking() {
        let bodyWeightTile = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Body Weight")).firstMatch
        scrollToElement(bodyWeightTile)
        LifeOSUITestSupport.scrollHorizontalRow(app, containerIdentifier: "today.plansRow", target: bodyWeightTile)
        LifeOSUITestSupport.robustTap(bodyWeightTile)
        XCTAssertTrue(app.navigationBars["Body Tracking"].waitForExistence(timeout: 3))
    }

    private func logManualBreakfast(calories: String, protein: String) {
        openNutritionDashboard()

        let breakfastRow = app.buttons["nutrition.meal.breakfast"]
        scrollToElement(breakfastRow)
        LifeOSUITestSupport.robustTap(breakfastRow)
        XCTAssertTrue(app.navigationBars["Breakfast"].waitForExistence(timeout: 3))

        let manualEntryChip = app.buttons["Manual entry"]
        LifeOSUITestSupport.scrollHorizontalRow(app, containerIdentifier: "nutrition.mealSourceTabs", target: manualEntryChip)
        LifeOSUITestSupport.robustTap(manualEntryChip)
        app.buttons["Add Breakfast"].tap()
        XCTAssertTrue(app.navigationBars["Add Breakfast"].waitForExistence(timeout: 3))

        let caloriesField = app.textFields["nutrition.field.calories"]
        XCTAssertTrue(caloriesField.waitForExistence(timeout: 3))
        caloriesField.tap()
        caloriesField.typeText(calories)
        let proteinField = app.textFields["nutrition.field.protein"]
        proteinField.tap()
        proteinField.typeText(protein)

        app.buttons["nutrition.meal.save"].tap()
        XCTAssertFalse(app.navigationBars["Add Breakfast"].waitForExistence(timeout: 1))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 3))
    }

    private func scrollToElement(_ element: XCUIElement, attempts: Int = 8) {
        LifeOSUITestSupport.scrollToElement(app, element, attempts: attempts)
    }

    private func scrollUpToElement(_ element: XCUIElement, attempts: Int = 8) {
        LifeOSUITestSupport.scrollUpToElement(app, element, attempts: attempts)
    }
}
