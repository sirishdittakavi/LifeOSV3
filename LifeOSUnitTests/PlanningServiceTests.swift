import XCTest
@testable import LifeOS

final class PlanningServiceTests: XCTestCase {
    func testMultipleDailyOccurrencesUseExactMinuteInterval() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let action = Activity(
            profile: profile, category: area, name: "High knees",
            repeatType: .timesPerDay, occurrencesPerDay: 4,
            repeatIntervalMinutes: 17, plannedStartMinutes: 390,
            estimatedDurationMinutes: 6, startDate: TestFixtures.date()
        )

        let result = PlanningService.scheduledStartMinutes(
            action, on: TestFixtures.date(2026, 1, 6), calendar: TestFixtures.calendar
        )

        XCTAssertEqual(result, [390, 407, 424, 441])
    }

    func testScheduleValidationRejectsOccurrencesThatRunPastMidnight() {
        XCTAssertFalse(PlanningService.scheduleFitsWithinDay(
            repeatType: .timesPerDay,
            occurrencesPerDay: 4,
            occurrencesPerWeek: 1,
            selectedWeekdayCount: 0,
            firstStartMinute: 1_380,
            intervalMinutes: 60
        ))
    }

    func testScheduleValidationAcceptsEveryRequestedOccurrence() {
        XCTAssertTrue(PlanningService.scheduleFitsWithinDay(
            repeatType: .timesPerDay,
            occurrencesPerDay: 4,
            occurrencesPerWeek: 1,
            selectedWeekdayCount: 0,
            firstStartMinute: 1_200,
            intervalMinutes: 60
        ))
    }

    func testTimesPerWeekAreDistributedAcrossSelectedDays() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let action = Activity(
            profile: profile, category: area, name: "Mobility",
            repeatType: .timesPerWeek, weekdays: [2, 4], occurrencesPerWeek: 5,
            repeatIntervalMinutes: 15, plannedStartMinutes: 480,
            estimatedDurationMinutes: 10, startDate: TestFixtures.date()
        )

        let monday = PlanningService.scheduledStartMinutes(
            action, on: TestFixtures.date(2026, 1, 5), calendar: TestFixtures.calendar
        )
        let wednesday = PlanningService.scheduledStartMinutes(
            action, on: TestFixtures.date(2026, 1, 7), calendar: TestFixtures.calendar
        )
        let tuesday = PlanningService.scheduledStartMinutes(
            action, on: TestFixtures.date(2026, 1, 6), calendar: TestFixtures.calendar
        )

        XCTAssertEqual(monday, [480, 495, 510])
        XCTAssertEqual(wednesday, [480, 495])
        XCTAssertTrue(tuesday.isEmpty)
    }

    func testGenerationDoesNotDuplicateExistingOccurrence() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let date = TestFixtures.date(2026, 1, 6)
        let action = Activity(
            profile: profile, category: area, name: "Practice",
            repeatType: .timesPerDay, occurrencesPerDay: 2,
            repeatIntervalMinutes: 30, plannedStartMinutes: 600,
            estimatedDurationMinutes: 20, startDate: TestFixtures.date()
        )
        let existing = CalendarItem(
            profile: profile, activity: action, date: date,
            plannedStart: TestFixtures.date(2026, 1, 6, hour: 10)
        )

        let generated = PlanningService.generateMissingCalendarItems(
            profile: profile, date: date, activities: [action], existingItems: [existing],
            calendar: TestFixtures.calendar
        )

        XCTAssertEqual(generated.count, 1)
        XCTAssertEqual(generated.first?.plannedStart, TestFixtures.date(2026, 1, 6, hour: 10, minute: 30))
    }

    func testInactiveAndDifferentProfileActionsAreExcluded() {
        let profile = TestFixtures.profile()
        let other = TestFixtures.profile("Other")
        let area = TestFixtures.area(profile: profile)
        let date = TestFixtures.date(2026, 1, 6)
        let inactive = Activity(
            profile: profile, category: area, name: "Inactive", plannedStartMinutes: 600,
            estimatedDurationMinutes: 10, startDate: TestFixtures.date()
        )
        inactive.isActive = false
        let foreign = Activity(
            profile: other, category: area, name: "Foreign", plannedStartMinutes: 600,
            estimatedDurationMinutes: 10, startDate: TestFixtures.date()
        )

        let generated = PlanningService.generateMissingCalendarItems(
            profile: profile, date: date, activities: [inactive, foreign], existingItems: [],
            calendar: TestFixtures.calendar
        )

        XCTAssertTrue(generated.isEmpty)
    }

    func testOnceActionIsGeneratedOnlyOnItsChosenFutureDate() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let action = Activity(
            profile: profile, category: area, name: "Future appointment",
            repeatType: .once, plannedStartMinutes: 600,
            estimatedDurationMinutes: 30, startDate: TestFixtures.date(2026, 2, 10)
        )

        XCTAssertTrue(PlanningService.scheduledStartMinutes(
            action, on: TestFixtures.date(2026, 2, 9), calendar: TestFixtures.calendar
        ).isEmpty)
        XCTAssertEqual(PlanningService.scheduledStartMinutes(
            action, on: TestFixtures.date(2026, 2, 10), calendar: TestFixtures.calendar
        ), [600])
    }

    func testOneTimeStartMustBeInTheFuture() {
        let now = TestFixtures.date(2026, 2, 10, hour: 12)

        XCTAssertFalse(PlanningService.startDateIsValid(
            repeatType: .once,
            startDate: TestFixtures.date(2026, 2, 10),
            firstStartMinute: 600,
            now: now,
            calendar: TestFixtures.calendar
        ))
        XCTAssertTrue(PlanningService.startDateIsValid(
            repeatType: .once,
            startDate: TestFixtures.date(2026, 2, 11),
            firstStartMinute: 600,
            now: now,
            calendar: TestFixtures.calendar
        ))
    }

    func testPlannedItemsExcludeManualAndUnplannedHistory() {
        let scheduled = CalendarItem(
            profile: nil, activity: nil, date: .now, status: .done, source: .schedule
        )
        let manual = CalendarItem(
            profile: nil, activity: nil, date: .now, status: .done, source: .manual
        )
        let unplanned = CalendarItem(
            profile: nil, activity: nil, date: .now, status: .unplanned, source: .schedule
        )

        XCTAssertEqual(PlanningService.plannedItems([scheduled, manual, unplanned]).map(\.id), [scheduled.id])
    }
}
