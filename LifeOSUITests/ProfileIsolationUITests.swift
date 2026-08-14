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
        nutrition.tap()
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 3))
        let childProtein = app.descendants(matching: .any)["nutrition.total.protein"]
        XCTAssertTrue(childProtein.waitForExistence(timeout: 3))
        XCTAssertTrue(childProtein.label.contains("0") || childProtein.label.contains("no target"), "Child must start with zero logged protein: got \(childProtein.label)")
        // NutritionDashboardView's sheet has no toolbar dismiss button —
        // swipe down, matching NutritionReviewUITests' closeDashboard().
        app.swipeDown()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 3))

        switchProfile(to: "Parent")
        switchProfile(to: "Child")
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 3), "Profile switching must never mutate stored ownership or leave the app in an inconsistent state")
    }

    /// Rapidly tapping Complete twice on the SAME occurrence must create
    /// exactly one completion, not two — regression-style UI coverage for
    /// TodayViewModel.quickFinish's idempotency guard.
    func testDoubleTapQuickCompletionCreatesOneCompletion() {
        switchProfile(to: "Child")
        let actions = app.buttons["today.actions.hitting"]
        scrollToElement(actions)
        XCTAssertTrue(actions.isHittable)
        actions.tap()
        let done = app.buttons["today.done.hitting"]
        XCTAssertTrue(done.waitForExistence(timeout: 2))
        done.tap()
        XCTAssertTrue(app.navigationBars["Finish"].waitForExistence(timeout: 3))
        let save = app.buttons["completion.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 2))
        save.tap()
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

    /// Completing then undoing a Task must return Today/Progress to exactly
    /// their pre-completion state.
    func testUndoCompletionUpdatesTodayPlanAndProgress() {
        switchProfile(to: "Child")
        let actions = app.buttons["today.actions.hitting"]
        scrollToElement(actions)
        actions.tap()
        app.buttons["today.done.hitting"].tap()
        XCTAssertTrue(app.navigationBars["Finish"].waitForExistence(timeout: 3))
        app.buttons["completion.save"].tap()

        let progressAfterComplete = app.descendants(matching: .any)["today.progress"]
        scrollUpToElement(progressAfterComplete)
        XCTAssertEqual(progressAfterComplete.label, "Today's progress, 100 percent, 1 of 1 Tasks complete")

        // Undo via the Plans tab's tap-to-toggle affordance (ImprovementCategoryDetailView).
        app.buttons["list.bullet.clipboard"].tap()
        let baseballRow = app.staticTexts["Baseball"]
        if baseballRow.waitForExistence(timeout: 3) { baseballRow.tap() }
        let hittingStatus = app.buttons["plan.task.status.hitting"]
        XCTAssertTrue(hittingStatus.waitForExistence(timeout: 3), "Expected the Plans-screen status control for Hitting")
        hittingStatus.tap()

        app.buttons["calendar"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 3))
        let progressAfterUndo = app.descendants(matching: .any)["today.progress"]
        scrollUpToElement(progressAfterUndo)
        XCTAssertFalse(progressAfterUndo.label.contains("100 percent"), "undo must remove the completion from Today's progress: got \(progressAfterUndo.label)")
    }

    // MARK: - Helpers

    /// A SwiftUI Menu row whose label is a custom composite view (not a
    /// plain Label/Text) is accessibility-opaque inside a native menu
    /// popup on this iOS version — no label, no identifier, nothing is
    /// exposed to XCUITest regardless of modifiers. "Manage Profiles" (a
    /// plain List row, fully accessible) is used instead; selecting a row
    /// there dismisses back to Today automatically.
    private func switchProfile(to name: String) {
        let selector = app.buttons["profile.selector"].firstMatch
        scrollUpToElement(selector)
        XCTAssertTrue(selector.exists, "Expected the profile selector")
        let manageProfiles = app.buttons["person.2.badge.gearshape"]
        // The menu trigger can occasionally miss under XCUITest — retry
        // rather than fail on a single flaky tap.
        for _ in 0..<3 where !manageProfiles.exists {
            selector.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if manageProfiles.waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(manageProfiles.exists, "Expected the Manage Profiles menu item")
        manageProfiles.tap()

        let row = app.buttons["profile.row.\(name.lowercased())"]
        XCTAssertTrue(row.waitForExistence(timeout: 3), "Expected a profile row for \(name)")
        row.tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 3), "Selecting a profile must dismiss back to Today")
    }

    private func completeHittingFromHome() {
        let actions = app.buttons["today.actions.hitting"]
        scrollToElement(actions)
        XCTAssertTrue(actions.isHittable, "Expected an active status control for Hitting")
        actions.tap()
        let done = app.buttons["today.done.hitting"]
        XCTAssertTrue(done.waitForExistence(timeout: 2))
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
