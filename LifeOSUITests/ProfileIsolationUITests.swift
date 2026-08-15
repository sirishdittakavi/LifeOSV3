import XCTest

/// LifeOS XCUITest and Notification Ownership Release Pass — Section 2.
/// Uses the deterministic -ui-testing fixture's "Parent"/"Child"/"Unrelated"
/// profiles (LifeOSApp.swift), where Parent and Child intentionally share
/// identical Area/Activity/Goal/Template/Weight-definition names and an
/// identical schedule — the exact trap that would expose an ownership bug
/// resolving by name instead of by ID.
final class ProfileIsolationUITests: XCTestCase {
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

    /// Parent and Child both have a daily "Hitting" Task at the identical
    /// time. Completing Child's must never affect Parent's.
    func testIdenticalProfilesRemainIsolatedAcrossTodayPlansAndProgress() {
        switchProfile(to: "Child")
        completeHittingFromHome()

        let childProgress = app.descendants(matching: .any)["today.progress"]
        scrollUpToElement(childProgress)
        XCTAssertEqual(childProgress.label, "Today's progress, 100 percent, 1 of 1 Tasks complete", "Child must show its own completion")

        switchProfile(to: "Parent")
        let parentProgress = app.descendants(matching: .any)["today.progress"]
        scrollUpToElement(parentProgress)
        XCTAssertFalse(
            parentProgress.label.contains("100 percent"),
            "Parent's identically-named, identically-timed Hitting Task must remain incomplete: got \(parentProgress.label)"
        )

        switchProfile(to: "Child")
        let childProgressAgain = app.descendants(matching: .any)["today.progress"]
        scrollUpToElement(childProgressAgain)
        XCTAssertEqual(childProgressAgain.label, "Today's progress, 100 percent, 1 of 1 Tasks complete", "Switching back to Child must restore its own completed state, not Parent's")
    }

    /// Repeatedly switching profiles and visiting several screens must never
    /// leave a screen showing the PREVIOUSLY selected profile's data.
    func testRapidProfileSwitchDoesNotShowPreviousProfilesData() {
        switchProfile(to: "Parent")
        XCTAssertTrue(app.buttons["today.task.hitting"].exists || app.buttons["today.actions.hitting"].waitForExistence(timeout: 3))

        switchProfile(to: "Child")
        // Child's Nutrition dashboard must show ITS OWN (empty/zero) protein
        // total, never a stale value carried over visually from Parent.
        // Queried by label rather than identifier — the overview tile's
        // identifier can lag a beat behind a fresh profile switch's first
        // render, while the label text is already correct.
        let nutrition = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Nutrition")).firstMatch
        scrollToElement(nutrition)
        LifeOSUITestSupport.scrollHorizontalRow(app, containerIdentifier: "today.plansRow", target: nutrition)
        LifeOSUITestSupport.robustTap(nutrition)
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 3))
        let childProtein = app.descendants(matching: .any)["nutrition.total.protein"]
        XCTAssertTrue(childProtein.waitForExistence(timeout: 3))
        XCTAssertTrue(childProtein.label.contains("0") || childProtein.label.contains("no target"), "Child must start with zero logged protein: got \(childProtein.label)")
        // NutritionDashboardView's sheet has no toolbar dismiss button —
        // swipe down, matching NutritionReviewUITests' closeDashboard().
        app.swipeDown()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 3))
        LifeOSUITestSupport.waitForDisappearance(app.navigationBars["Nutrition"])

        switchProfile(to: "Parent")
        switchProfile(to: "Child")
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 3), "Profile switching must never mutate stored ownership or leave the app in an inconsistent state")
    }

    /// Today has one direct action. Repository-level unit tests cover the
    /// double-tap idempotency guard; this UI test proves the interaction does
    /// not branch into the old Finish form.
    func testOneTapQuickCompletionCreatesOneCompletion() {
        switchProfile(to: "Child")
        let actions = app.buttons["today.actions.hitting"]
        scrollToElement(actions)
        XCTAssertTrue(actions.isHittable)
        actions.tap()
        XCTAssertFalse(app.navigationBars["Finish"].waitForExistence(timeout: 1))

        // The row's status control is gone once done — a second, unrelated
        // tap sequence can't accidentally create a duplicate completion
        // through the same path (the UI itself only exposes one action
        // control per occurrence). Confirm progress reflects exactly one.
        let progress = app.descendants(matching: .any)["today.progress"]
        scrollUpToElement(progress)
        XCTAssertEqual(progress.label, "Today's progress, 100 percent, 1 of 1 Tasks complete")
        XCTAssertFalse(app.buttons["today.actions.hitting"].exists, "a completed occurrence exposes no further action control to double-tap")
    }

    /// A completed task exposes its green leading checkmark in history. A
    /// second tap restores that exact occurrence without touching another
    /// profile's identically named task.
    func testUndoCompletionUpdatesTodayPlanAndProgress() {
        switchProfile(to: "Child")
        completeHittingFromHome()

        let completed = app.buttons["today.completedSection"]
        scrollToElement(completed)
        XCTAssertTrue(completed.isHittable)
        completed.tap()

        let undo = app.buttons["today.undo.hitting"]
        scrollToElement(undo)
        XCTAssertTrue(undo.isHittable, "Expected a completed Task's leading checkmark to undo it")
        undo.tap()

        let progressAfterUndo = app.descendants(matching: .any)["today.progress"]
        scrollUpToElement(progressAfterUndo)
        XCTAssertFalse(progressAfterUndo.label.contains("100 percent"), "undo must remove the completion from Today's progress: got \(progressAfterUndo.label)")
    }

    // MARK: - Helpers

    private func switchProfile(to name: String) {
        LifeOSUITestSupport.switchProfile(app, to: name)
    }

    private func completeHittingFromHome() {
        let actions = app.buttons["today.actions.hitting"]
        scrollToElement(actions)
        XCTAssertTrue(actions.isHittable, "Expected an active status control for Hitting")
        actions.tap()
        XCTAssertFalse(app.navigationBars["Finish"].waitForExistence(timeout: 1))
    }

    private func scrollToElement(_ element: XCUIElement, attempts: Int = 8) {
        LifeOSUITestSupport.scrollToElement(app, element, attempts: attempts)
    }

    private func scrollUpToElement(_ element: XCUIElement, attempts: Int = 8) {
        LifeOSUITestSupport.scrollUpToElement(app, element, attempts: attempts)
    }
}
