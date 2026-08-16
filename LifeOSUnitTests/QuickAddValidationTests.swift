import XCTest
@testable import LifeOS

/// Phase 3 / Chunk 2: Quick Add must never default a one-time Task to a
/// time that has already passed, and must re-validate at Create time, not
/// just whatever was true when the sheet appeared.
final class QuickAddValidationTests: XCTestCase {
    func testDefaultOneTimeWhenIsAlwaysOneHourAhead() {
        let calendar = TestFixtures.calendar
        let now = TestFixtures.date(2026, 6, 1, hour: 23, minute: 30)

        let when = QuickAddValidation.defaultOneTimeWhen(now: now, calendar: calendar)

        XCTAssertGreaterThan(when, now, "the default must always be in the future, even at 11:30 pm")
        XCTAssertEqual(when, calendar.date(byAdding: .hour, value: 1, to: now))
    }

    func testDefaultOneTimeWhenNeverCollapsesToAFixedSixPM() {
        let calendar = TestFixtures.calendar
        // Well past 6 pm -- the old fixed-6pm default would already be in the past here.
        let now = TestFixtures.date(2026, 6, 1, hour: 21, minute: 0)

        let when = QuickAddValidation.defaultOneTimeWhen(now: now, calendar: calendar)

        XCTAssertGreaterThanOrEqual(when, now)
    }

    func testOneTimeWhenIsValidRejectsAPastDateTime() {
        let now = TestFixtures.date(2026, 6, 1, hour: 12)
        let past = TestFixtures.date(2026, 6, 1, hour: 11)

        XCTAssertFalse(QuickAddValidation.oneTimeWhenIsValid(when: past, isRecurring: false, now: now))
    }

    func testOneTimeWhenIsValidAcceptsAFutureDateTime() {
        let now = TestFixtures.date(2026, 6, 1, hour: 12)
        let future = TestFixtures.date(2026, 6, 1, hour: 13)

        XCTAssertTrue(QuickAddValidation.oneTimeWhenIsValid(when: future, isRecurring: false, now: now))
    }

    func testOneTimeWhenIsValidIgnoresThePastForARecurringTask() {
        let now = TestFixtures.date(2026, 6, 1, hour: 12)
        let past = TestFixtures.date(2020, 1, 1, hour: 0)

        XCTAssertTrue(
            QuickAddValidation.oneTimeWhenIsValid(when: past, isRecurring: true, now: now),
            "a recurring Task only uses the time-of-day portion, so an aged start date must not block it"
        )
    }

    func testCanSaveRejectsAnEmptyOrWhitespaceOnlyTitle() {
        let now = TestFixtures.date(2026, 6, 1, hour: 12)
        let future = TestFixtures.date(2026, 6, 1, hour: 13)

        XCTAssertFalse(QuickAddValidation.canSave(
            name: "   ", hasValidCategory: true, isRecurring: false, selectedWeekdays: [], when: future, now: now
        ))
    }

    func testCanSaveRejectsWhenNoValidPlanIsResolved() {
        let now = TestFixtures.date(2026, 6, 1, hour: 12)
        let future = TestFixtures.date(2026, 6, 1, hour: 13)

        XCTAssertFalse(QuickAddValidation.canSave(
            name: "Batting practice", hasValidCategory: false, isRecurring: false, selectedWeekdays: [], when: future, now: now
        ))
    }

    func testCanSaveRejectsAOneTimeTaskWithAPastDateTime() {
        let now = TestFixtures.date(2026, 6, 1, hour: 12)
        let past = TestFixtures.date(2026, 6, 1, hour: 11)

        XCTAssertFalse(QuickAddValidation.canSave(
            name: "Batting practice", hasValidCategory: true, isRecurring: false, selectedWeekdays: [], when: past, now: now
        ))
    }

    func testCanSaveRejectsARecurringTaskWithNoWeekdaysSelected() {
        let now = TestFixtures.date(2026, 6, 1, hour: 12)

        XCTAssertFalse(QuickAddValidation.canSave(
            name: "Batting practice", hasValidCategory: true, isRecurring: true, selectedWeekdays: [], when: now, now: now
        ))
    }

    func testCanSaveAcceptsAValidOneTimeTask() {
        let now = TestFixtures.date(2026, 6, 1, hour: 12)
        let future = TestFixtures.date(2026, 6, 1, hour: 13)

        XCTAssertTrue(QuickAddValidation.canSave(
            name: "Batting practice", hasValidCategory: true, isRecurring: false, selectedWeekdays: [], when: future, now: now
        ))
    }

    func testCanSaveAcceptsAValidRecurringTask() {
        let now = TestFixtures.date(2026, 6, 1, hour: 12)

        XCTAssertTrue(QuickAddValidation.canSave(
            name: "Batting practice", hasValidCategory: true, isRecurring: true, selectedWeekdays: [2, 4], when: now, now: now
        ))
    }
}
