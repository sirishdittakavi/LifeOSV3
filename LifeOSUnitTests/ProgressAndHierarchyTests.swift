import XCTest
@testable import LifeOS

final class ProgressAndHierarchyTests: XCTestCase {
    func testDailyProgressSumsOnlySelectedProfileAndDay() {
        let profile = TestFixtures.profile()
        let other = TestFixtures.profile("Other")
        let area = TestFixtures.area(profile: profile)
        let action = Activity(
            profile: profile, category: area, name: "Swings", targetValue: 100,
            targetUnit: "swings", plannedStartMinutes: 600, estimatedDurationMinutes: 20
        )
        let sameDay = ActivitySession(
            activity: action, calendarItem: nil, date: TestFixtures.date(2026, 1, 6),
            recordedValue: 60
        )
        let anotherSameDay = ActivitySession(
            activity: action, calendarItem: nil, date: TestFixtures.date(2026, 1, 6, hour: 16),
            recordedValue: 55
        )
        let priorDay = ActivitySession(
            activity: action, calendarItem: nil, date: TestFixtures.date(2026, 1, 5),
            recordedValue: 999
        )
        let foreignAction = Activity(
            profile: other, category: area, name: "Other swings", targetValue: 100,
            plannedStartMinutes: 600, estimatedDurationMinutes: 20
        )

        let progress = ProgressEngine.dailyProgress(
            profile: profile, date: TestFixtures.date(2026, 1, 6),
            activities: [action, foreignAction], sessions: [sameDay, anotherSameDay, priorDay],
            calendar: TestFixtures.calendar
        )

        XCTAssertEqual(progress.count, 1)
        XCTAssertEqual(progress.first?.actual, 115)
        XCTAssertEqual(progress.first?.cappedFraction, 1)
    }

    func testCompletionSummaryDoesNotCountSkippedAsDone() {
        let items = [
            CalendarItem(profile: nil, activity: nil, date: .now, status: .done),
            CalendarItem(profile: nil, activity: nil, date: .now, status: .skipped),
            CalendarItem(profile: nil, activity: nil, date: .now, status: .planned),
            CalendarItem(profile: nil, activity: nil, date: .now, status: .inProgress)
        ]

        let summary = ProgressEngine.completionSummary(items: items)

        XCTAssertEqual(summary.done, 1)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.remaining, 2)
        XCTAssertEqual(summary.percentComplete, 0.25, accuracy: 0.0001)
    }

    func testHierarchyIncludesNestedDescendantsWithoutDuplicates() {
        let profile = TestFixtures.profile()
        let baseball = TestFixtures.area(profile: profile)
        let driveline = TestFixtures.area(profile: profile, name: "Driveline")
        driveline.parentCategoryID = baseball.id
        let pitching = TestFixtures.area(profile: profile, name: "Pitching")
        pitching.parentCategoryID = driveline.id

        let ids = CategoryHierarchy.idsIncludingDescendants(
            of: baseball, in: [pitching, baseball, driveline]
        )

        XCTAssertEqual(ids, Set([baseball.id, driveline.id, pitching.id]))
        XCTAssertEqual(
            CategoryHierarchy.breadcrumbName(for: pitching, in: [pitching, baseball, driveline]),
            "Baseball › Driveline › Pitching"
        )
    }

    func testCheckInCadenceAdvancesAndOnDemandDoesNotInventDate() {
        let start = TestFixtures.date(2026, 1, 15)

        XCTAssertEqual(
            ResultCheckInCadence.weekly.nextDate(after: start, calendar: TestFixtures.calendar),
            TestFixtures.date(2026, 1, 22)
        )
        XCTAssertEqual(
            ResultCheckInCadence.monthly.nextDate(after: start, calendar: TestFixtures.calendar),
            TestFixtures.date(2026, 2, 15)
        )
        XCTAssertEqual(
            ResultCheckInCadence.quarterly.nextDate(after: start, calendar: TestFixtures.calendar),
            TestFixtures.date(2026, 4, 15)
        )
        XCTAssertNil(ResultCheckInCadence.onDemand.nextDate(after: start, calendar: TestFixtures.calendar))
    }

    func testWeightConversionsRoundTrip() {
        let kilograms = 72.4
        let pounds = WeightUnit.pounds.displayValue(kilograms: kilograms)

        XCTAssertEqual(WeightUnit.kilograms.displayValue(kilograms: kilograms), kilograms)
        XCTAssertEqual(WeightUnit.pounds.kilograms(from: pounds), kilograms, accuracy: 0.000_001)
    }

    func testTargetValidationRequiresDirectionallyCorrectValues() {
        XCTAssertTrue(ResultMeasureValidation.isValidTarget(
            valueType: .number, direction: .increase,
            baseline: 60, target: 70, minimum: nil, maximum: nil
        ))
        XCTAssertFalse(ResultMeasureValidation.isValidTarget(
            valueType: .number, direction: .increase,
            baseline: 60, target: 50, minimum: nil, maximum: nil
        ))
        XCTAssertTrue(ResultMeasureValidation.isValidTarget(
            valueType: .number, direction: .decrease,
            baseline: 80, target: 70, minimum: nil, maximum: nil
        ))
        XCTAssertFalse(ResultMeasureValidation.isValidTarget(
            valueType: .number, direction: .decrease,
            baseline: 80, target: 90, minimum: nil, maximum: nil
        ))
    }

    func testRatingTargetsStayInsideFivePointScale() {
        XCTAssertTrue(ResultMeasureValidation.isValidTarget(
            valueType: .rating, direction: .increase,
            baseline: 2, target: 5, minimum: nil, maximum: nil
        ))
        XCTAssertFalse(ResultMeasureValidation.isValidTarget(
            valueType: .rating, direction: .increase,
            baseline: 2, target: 6, minimum: nil, maximum: nil
        ))
    }

    func testResultValidationDistinguishesMissingFromZero() {
        XCTAssertFalse(ResultMeasureValidation.isValidEntry(
            valueType: .number, numericValue: nil, textValue: ""
        ))
        XCTAssertTrue(ResultMeasureValidation.isValidEntry(
            valueType: .number, numericValue: 0, textValue: ""
        ))
        XCTAssertFalse(ResultMeasureValidation.isValidEntry(
            valueType: .text, numericValue: nil, textValue: "   "
        ))
        XCTAssertTrue(ResultMeasureValidation.isValidEntry(
            valueType: .text, numericValue: nil, textValue: "Coach assessment"
        ))
        XCTAssertFalse(ResultMeasureValidation.isValidEntry(
            valueType: .milestone, numericValue: nil, textValue: ""
        ))
        XCTAssertTrue(ResultMeasureValidation.isValidEntry(
            valueType: .milestone, numericValue: 0, textValue: ""
        ))
    }

    func testReminderPoliciesRequireActiveOwnersAndScheduledCadence() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        area.reminderEnabled = true
        XCTAssertTrue(area.shouldScheduleReminders)
        area.isActive = false
        XCTAssertFalse(area.shouldScheduleReminders)

        let goal = TestFixtures.goal(profile: profile)
        let measure = TestFixtures.measure(goal: goal)
        measure.reminderEnabled = true
        XCTAssertTrue(measure.shouldScheduleReminder)
        measure.cadence = .onDemand
        XCTAssertFalse(measure.shouldScheduleReminder)
    }
}
