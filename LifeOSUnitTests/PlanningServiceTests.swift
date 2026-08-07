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

    func testOccurrencesAfterMidnightAreRejected() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let action = Activity(
            profile: profile, category: area, name: "Late reminder",
            repeatType: .timesPerDay, occurrencesPerDay: 4,
            repeatIntervalMinutes: 20, plannedStartMinutes: 1_420,
            estimatedDurationMinutes: 5, startDate: TestFixtures.date()
        )

        let result = PlanningService.scheduledStartMinutes(
            action, on: TestFixtures.date(2026, 1, 6), calendar: TestFixtures.calendar
        )

        XCTAssertEqual(result, [1_420])
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
}
