import XCTest

/// Shared scaffolding for the LifeOS XCUITest suites (ProfileIsolationUITests,
/// RemainingReleasePassUITests) — factored out to stop the same helper logic
/// from drifting between per-file copies.
enum LifeOSUITestSupport {
    /// A SwiftUI `Menu` whose row content is a custom composite view (not a
    /// plain Label/Text) is accessibility-opaque inside the native menu
    /// popup on this iOS version — no label, no identifier, nothing is
    /// exposed to XCUITest regardless of modifiers (confirmed by direct
    /// inspection of the live accessibility tree). "Manage Profiles" (a
    /// plain List row in ProfileManagerView, fully accessible) is used
    /// instead; selecting a row there dismisses back to Today automatically.
    static func switchProfile(_ app: XCUIApplication, to name: String) {
        let selector = app.buttons["profile.selector"].firstMatch
        scrollUpToElement(app, selector)
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
        // Confirmed root cause (see waitForDisappearance's doc comment):
        // ProfileManagerView's own sheet ("Profiles") can remain briefly
        // registered in the accessibility tree after Today reappears
        // underneath it, intercepting hits meant for Today's Plans row at
        // the same on-screen position.
        waitForDisappearance(app.navigationBars["Profiles"])
    }

    static func scrollToElement(_ app: XCUIApplication, _ element: XCUIElement, attempts: Int = 8) {
        var remaining = attempts
        while (!element.exists || !element.isHittable) && remaining > 0 {
            app.swipeUp()
            remaining -= 1
        }
    }

    static func scrollUpToElement(_ app: XCUIApplication, _ element: XCUIElement, attempts: Int = 8) {
        var remaining = attempts
        while (!element.exists || !element.isHittable) && remaining > 0 {
            app.swipeDown()
            remaining -= 1
        }
    }

    /// Waits for `element` to fully leave the accessibility tree, not just
    /// for the next screen's own element to appear. Confirmed root cause: a
    /// dismissed sheet (e.g. NutritionDashboardView after `swipeDown()`) can
    /// remain registered in the accessibility tree for a beat after the
    /// screen underneath it is already interactable, silently intercepting
    /// hits meant for elements at the same on-screen position (e.g. Today's
    /// Plans row tiles) — "not hittable" with an in-bounds, unoccluded-
    /// looking frame is the symptom. Call this after dismissing a sheet
    /// whose screen overlaps where the next action needs to tap.
    static func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while element.exists && Date() < deadline {
            usleep(100_000)
        }
    }

    /// Taps `element` via its own coordinate rather than XCUITest's
    /// automatic "scroll to visible, then compute a hit point" path.
    /// Confirmed root cause on the Today Plans row: an oversized, off-
    /// screen-positioned element (~3x the screen in both dimensions,
    /// visible in the accessibility tree at a negative origin — almost
    /// certainly paging/scroll-target-behavior machinery from
    /// `.scrollTargetBehavior(.viewAligned)`) confuses XCUITest's hit-point
    /// computation for a legitimately in-bounds, unoccluded element,
    /// producing "Computed hit point {-1, -1}" even though the element's
    /// own reported frame is entirely on-screen. A direct coordinate tap
    /// bypasses that broken computation — the same fix already proven for
    /// the `profile.selector` Menu trigger.
    static func robustTap(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    /// Scrolls a specific horizontal `ScrollView` (identified by
    /// `containerIdentifier`) until `target` is hittable, by performing the
    /// swipe gesture *on that ScrollView element itself* — not on `app`,
    /// whose center may not even intersect a horizontal row pinned near the
    /// top of the screen. This is the reliable way to scroll one nested
    /// horizontal container in XCUITest, and applies to any current or
    /// future `ScrollView(.horizontal)` row in this app (e.g. Today's Plans
    /// row, MealLoggingView's source tabs).
    static func scrollHorizontalRow(_ app: XCUIApplication, containerIdentifier: String, target: XCUIElement, attempts: Int = 6) {
        let container = app.scrollViews[containerIdentifier].firstMatch
        var remaining = attempts
        while target.exists && !target.isHittable && remaining > 0 {
            if container.exists {
                container.swipeLeft()
            } else {
                target.swipeLeft()
            }
            remaining -= 1
        }
    }
}
