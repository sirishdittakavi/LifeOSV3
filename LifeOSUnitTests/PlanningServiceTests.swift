import XCTest
import SwiftData
@testable import LifeOS

final class PlanningServiceTests: XCTestCase {
    func testReminderDatesRespectLifecycleAndExcludeElapsedOccurrences() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let task = Activity(
            profile: profile, category: area, name: "Practice",
            repeatType: .daily, plannedStartMinutes: 600,
            estimatedDurationMinutes: 10,
            startDate: TestFixtures.date(2026, 8, 11),
            endDate: TestFixtures.date(2026, 8, 12)
        )

        XCTAssertEqual(
            PlanningService.reminderOccurrenceDates(
                for: task, after: TestFixtures.date(2026, 8, 10, hour: 20),
                calendar: TestFixtures.calendar
            ),
            [TestFixtures.date(2026, 8, 11, hour: 10), TestFixtures.date(2026, 8, 12, hour: 10)]
        )
        XCTAssertEqual(
            PlanningService.reminderOccurrenceDates(
                for: task, after: TestFixtures.date(2026, 8, 11, hour: 12),
                calendar: TestFixtures.calendar
            ),
            [TestFixtures.date(2026, 8, 12, hour: 10)]
        )
        task.isActive = false
        XCTAssertTrue(PlanningService.reminderOccurrenceDates(
            for: task, after: TestFixtures.date(2026, 8, 10), calendar: TestFixtures.calendar
        ).isEmpty)
    }

    func testOccurrenceIdentityPreventsDuplicatesWithoutCollapsingLegitimateWork() {
        assertGenerationDoesNotDuplicateExistingOccurrence()
        assertGenerationUsesMinuteIdentityWhenStoredOccurrenceHasSeconds()
        assertOccurrenceIdentitySeparatesLegitimateNeighbors()
        assertManualEntryNeverCollidesWithScheduledOccurrence()
        assertAllRequestedSameDayOccurrencesRemainDistinct()
    }

    func testLifecycleBoundariesNeverScheduleOutsideInclusiveStartAndEndDates() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let task = Activity(
            profile: profile, category: area, name: "Practice",
            repeatType: .daily, plannedStartMinutes: 600,
            estimatedDurationMinutes: 10,
            startDate: TestFixtures.date(2026, 8, 10),
            endDate: TestFixtures.date(2026, 8, 12)
        )

        XCTAssertEqual(PlanningService.scheduledStartMinutes(
            task, on: TestFixtures.date(2026, 8, 9), calendar: TestFixtures.calendar
        ), [])
        XCTAssertEqual(PlanningService.scheduledStartMinutes(
            task, on: TestFixtures.date(2026, 8, 10), calendar: TestFixtures.calendar
        ), [600])
        XCTAssertEqual(PlanningService.scheduledStartMinutes(
            task, on: TestFixtures.date(2026, 8, 12), calendar: TestFixtures.calendar
        ), [600])
        XCTAssertEqual(PlanningService.scheduledStartMinutes(
            task, on: TestFixtures.date(2026, 8, 13), calendar: TestFixtures.calendar
        ), [])
    }

    func testEditingStartDateArchiveOrTimeRemovesOnlyStaleUntouchedOccurrences() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let today = TestFixtures.date(2026, 8, 9)
        let task = Activity(
            profile: profile, category: area, name: "Practice",
            repeatType: .daily, plannedStartMinutes: 420,
            estimatedDurationMinutes: 10, startDate: today
        )
        let untouched = CalendarItem(
            profile: profile, activity: task, date: today,
            plannedStart: TestFixtures.date(2026, 8, 9, hour: 7)
        )
        let completed = CalendarItem(
            profile: profile, activity: task, date: today,
            plannedStart: TestFixtures.date(2026, 8, 9, hour: 7), status: .done
        )

        task.startDate = TestFixtures.date(2026, 8, 10)
        XCTAssertEqual(PlanningService.reconcileUntouchedOccurrences(
            for: task, in: [untouched, completed], calendar: TestFixtures.calendar
        ).map(\.id), [untouched.id])

        task.startDate = today
        task.plannedStartMinutes = 480
        XCTAssertEqual(PlanningService.reconcileUntouchedOccurrences(
            for: task, in: [untouched, completed], calendar: TestFixtures.calendar
        ).map(\.id), [untouched.id])

        task.isActive = false
        XCTAssertEqual(PlanningService.reconcileUntouchedOccurrences(
            for: task, in: [untouched, completed], calendar: TestFixtures.calendar
        ).map(\.id), [untouched.id])
    }

    func testEditingDurationUpdatesUntouchedOccurrenceEndWithoutDeletingIt() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let today = TestFixtures.date(2026, 8, 9)
        let task = Activity(
            profile: profile, category: area, name: "Practice",
            repeatType: .daily, plannedStartMinutes: 420,
            estimatedDurationMinutes: 20, startDate: today
        )
        let item = CalendarItem(
            profile: profile, activity: task, date: today,
            plannedStart: TestFixtures.date(2026, 8, 9, hour: 7),
            plannedEnd: TestFixtures.date(2026, 8, 9, hour: 7, minute: 10)
        )

        XCTAssertTrue(PlanningService.reconcileUntouchedOccurrences(
            for: task, in: [item], calendar: TestFixtures.calendar
        ).isEmpty)
        XCTAssertEqual(item.plannedEnd, TestFixtures.date(2026, 8, 9, hour: 7, minute: 20))
    }

    func testRepeatRuleTransitionsRemoveEveryOccurrenceNoLongerInTheSchedule() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let monday = TestFixtures.date(2026, 8, 10)
        let task = Activity(
            profile: profile, category: area, name: "Practice",
            repeatType: .timesPerDay, occurrencesPerDay: 3,
            repeatIntervalMinutes: 15, plannedStartMinutes: 420,
            estimatedDurationMinutes: 10, startDate: monday
        )
        let items = [420, 435, 450].map { minute in
            CalendarItem(
                profile: profile, activity: task, date: monday,
                plannedStart: TestFixtures.calendar.date(
                    byAdding: .minute, value: minute, to: monday
                )
            )
        }

        task.occurrencesPerDay = 1
        XCTAssertEqual(Set(PlanningService.reconcileUntouchedOccurrences(
            for: task, in: items, calendar: TestFixtures.calendar
        ).map(\.id)), Set(items.dropFirst().map(\.id)))

        task.repeatType = .selectedWeekdays
        task.weekdays = [3] // Tuesday; these Monday occurrences are all stale.
        XCTAssertEqual(Set(PlanningService.reconcileUntouchedOccurrences(
            for: task, in: items, calendar: TestFixtures.calendar
        ).map(\.id)), Set(items.map(\.id)))

        task.repeatType = .once
        task.startDate = TestFixtures.date(2026, 8, 11)
        XCTAssertEqual(Set(PlanningService.reconcileUntouchedOccurrences(
            for: task, in: items, calendar: TestFixtures.calendar
        ).map(\.id)), Set(items.map(\.id)))
    }

    func testCompletedOccurrenceCountsAsHistoryButUntouchedPlanDoesNot() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let today = TestFixtures.date(2026, 8, 9)
        let task = Activity(
            profile: profile, category: area, name: "Practice",
            plannedStartMinutes: 420, estimatedDurationMinutes: 10, startDate: today
        )
        let planned = CalendarItem(
            profile: profile, activity: task, date: today,
            plannedStart: TestFixtures.date(2026, 8, 9, hour: 7)
        )
        let done = CalendarItem(
            profile: profile, activity: task, date: today,
            plannedStart: TestFixtures.date(2026, 8, 9, hour: 7), status: .done
        )

        XCTAssertFalse(PlanningService.hasHistory(
            for: task, on: today, in: [planned], calendar: TestFixtures.calendar
        ))
        XCTAssertTrue(PlanningService.hasHistory(
            for: task, on: today, in: [planned, done], calendar: TestFixtures.calendar
        ))
    }

    func testReusableManualWorkBeginsTomorrowAndDoesNotCreateAnotherTodayTask() {
        let loggedDate = TestFixtures.date(2026, 8, 9, hour: 18)
        let firstDate = PlanningService.firstReusableDate(
            after: loggedDate, calendar: TestFixtures.calendar
        )
        XCTAssertEqual(firstDate, TestFixtures.date(2026, 8, 10))

        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let task = Activity(
            profile: profile, category: area, name: "Extra practice",
            repeatType: .daily, plannedStartMinutes: 1080,
            estimatedDurationMinutes: 10, startDate: firstDate
        )
        XCTAssertTrue(PlanningService.generateMissingCalendarItems(
            profile: profile, date: loggedDate, activities: [task], existingItems: [],
            calendar: TestFixtures.calendar
        ).isEmpty)
        XCTAssertEqual(PlanningService.generateMissingCalendarItems(
            profile: profile, date: firstDate, activities: [task], existingItems: [],
            calendar: TestFixtures.calendar
        ).count, 1)
    }

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

    private func assertGenerationDoesNotDuplicateExistingOccurrence() {
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

    private func assertGenerationUsesMinuteIdentityWhenStoredOccurrenceHasSeconds() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let date = TestFixtures.date(2026, 1, 6)
        let action = Activity(profile: profile, category: area, name: "Practice",
                              plannedStartMinutes: 600, estimatedDurationMinutes: 20,
                              startDate: TestFixtures.date())
        let storedStart = TestFixtures.calendar.date(byAdding: .second, value: 42,
                                                      to: TestFixtures.date(2026, 1, 6, hour: 10))!
        let existing = CalendarItem(profile: profile, activity: action, date: date,
                                    plannedStart: storedStart)

        XCTAssertTrue(PlanningService.generateMissingCalendarItems(
            profile: profile, date: date, activities: [action], existingItems: [existing],
            calendar: TestFixtures.calendar
        ).isEmpty)
    }

    func testDuplicateRepairKeepsCompletedOccurrence() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let action = Activity(profile: profile, category: area, name: "Practice",
                              plannedStartMinutes: 600, estimatedDurationMinutes: 20)
        let date = TestFixtures.date(2026, 1, 6)
        let planned = CalendarItem(profile: profile, activity: action, date: date,
                                   plannedStart: TestFixtures.date(2026, 1, 6, hour: 10))
        let completed = CalendarItem(profile: profile, activity: action, date: date,
                                     plannedStart: TestFixtures.date(2026, 1, 6, hour: 10), status: .done)

        XCTAssertEqual(PlanningService.duplicateCalendarItems(
            in: [planned, completed], calendar: TestFixtures.calendar
        ).map(\.id), [planned.id])
    }

    private func assertOccurrenceIdentitySeparatesLegitimateNeighbors() {
        let p1 = TestFixtures.profile(), p2 = TestFixtures.profile("Other")
        let area = TestFixtures.area(profile: p1), day = TestFixtures.date(2026, 1, 6)
        let a1 = Activity(profile: p1, category: area, name: "A", plannedStartMinutes: 600, estimatedDurationMinutes: 10)
        let a2 = Activity(profile: p1, category: area, name: "B", plannedStartMinutes: 600, estimatedDurationMinutes: 10)
        let items = [
            CalendarItem(profile: p1, activity: a1, date: day, plannedStart: TestFixtures.date(2026, 1, 6, hour: 10)),
            CalendarItem(profile: p1, activity: a2, date: day, plannedStart: TestFixtures.date(2026, 1, 6, hour: 10)),
            CalendarItem(profile: p2, activity: a1, date: day, plannedStart: TestFixtures.date(2026, 1, 6, hour: 10)),
            CalendarItem(profile: p1, activity: a1, date: day, plannedStart: TestFixtures.date(2026, 1, 6, hour: 10, minute: 30))
        ]
        XCTAssertEqual(Set(items.compactMap { PlanningService.occurrenceIdentity(for: $0, calendar: TestFixtures.calendar) }).count, 4)
        XCTAssertTrue(PlanningService.duplicateCalendarItems(in: items, calendar: TestFixtures.calendar).isEmpty)
    }

    private func assertManualEntryNeverCollidesWithScheduledOccurrence() {
        let profile = TestFixtures.profile(), area = TestFixtures.area(profile: profile)
        let action = Activity(profile: profile, category: area, name: "Practice", plannedStartMinutes: 600, estimatedDurationMinutes: 10)
        let day = TestFixtures.date(2026, 1, 6), start = TestFixtures.date(2026, 1, 6, hour: 10)
        let scheduled = CalendarItem(profile: profile, activity: action, date: day, plannedStart: start)
        let manual = CalendarItem(profile: profile, activity: action, date: day, plannedStart: start, source: .manual)

        XCTAssertNil(PlanningService.occurrenceIdentity(for: manual, calendar: TestFixtures.calendar))
        XCTAssertTrue(PlanningService.duplicateCalendarItems(in: [scheduled, manual], calendar: TestFixtures.calendar).isEmpty)
    }

    func testDuplicateRepairNeverDeletesTwoHistoryBearingRecords() {
        let profile = TestFixtures.profile(), area = TestFixtures.area(profile: profile)
        let action = Activity(profile: profile, category: area, name: "Practice", plannedStartMinutes: 600, estimatedDurationMinutes: 10)
        let day = TestFixtures.date(2026, 1, 6), start = TestFixtures.date(2026, 1, 6, hour: 10)
        let done = CalendarItem(profile: profile, activity: action, date: day, plannedStart: start, status: .done)
        let skipped = CalendarItem(profile: profile, activity: action, date: day, plannedStart: start, status: .skipped)

        XCTAssertTrue(PlanningService.duplicateCalendarItems(in: [done, skipped], calendar: TestFixtures.calendar).isEmpty)
    }

    private func assertAllRequestedSameDayOccurrencesRemainDistinct() {
        let profile = TestFixtures.profile(), area = TestFixtures.area(profile: profile)
        let action = Activity(profile: profile, category: area, name: "Practice", repeatType: .timesPerDay,
                              occurrencesPerDay: 4, repeatIntervalMinutes: 15, plannedStartMinutes: 600,
                              estimatedDurationMinutes: 10, startDate: TestFixtures.date())
        let generated = PlanningService.generateMissingCalendarItems(
            profile: profile, date: TestFixtures.date(2026, 1, 6), activities: [action],
            existingItems: [], calendar: TestFixtures.calendar
        )

        XCTAssertEqual(generated.count, 4)
        XCTAssertEqual(Set(generated.compactMap { PlanningService.occurrenceIdentity(for: $0, calendar: TestFixtures.calendar) }).count, 4)
    }

    func testFourOnboardingSelectionsProduceFourScrollableTodayOccurrences() {
        let profile = TestFixtures.profile(), area = TestFixtures.area(profile: profile)
        let activities = ["Career", "Health", "Nutrition", "Sport"].enumerated().map { index, name in
            Activity(profile: profile, category: area, name: name, source: .template,
                     repeatType: .daily, weekdays: Array(1...7), plannedStartMinutes: 540 + index * 60,
                     estimatedDurationMinutes: 30, startDate: TestFixtures.date())
        }
        let generated = PlanningService.generateMissingCalendarItems(
            profile: profile, date: TestFixtures.date(2026, 1, 6), activities: activities,
            existingItems: [], calendar: TestFixtures.calendar
        )

        XCTAssertEqual(generated.map { $0.activity?.name }, ["Career", "Health", "Nutrition", "Sport"])
    }

    @MainActor
    func testPersistenceEntryPointIsIdempotentAcrossRepeatedCallers() throws {
        let container = try ModelContainer(
            for: Profile.self, SavedCategoryTemplate.self, AppCategory.self, Goal.self,
            GoalAreaContribution.self, ResultMeasure.self, ResultEntry.self, Activity.self,
            CalendarItem.self, ActivitySession.self, FoodEntry.self, WeightEntry.self, SportEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let date = TestFixtures.date(2026, 1, 6)
        let action = Activity(profile: profile, category: area, name: "Practice",
                              plannedStartMinutes: 600, estimatedDurationMinutes: 20,
                              startDate: TestFixtures.date())
        context.insert(profile)
        context.insert(area)
        context.insert(action)
        try context.save()

        try PlanningService.insertMissingCalendarItems(
            profile: profile, date: date, activities: [action], context: context,
            calendar: TestFixtures.calendar
        )
        try context.save()
        try PlanningService.insertMissingCalendarItems(
            profile: profile, date: date, activities: [action], context: context,
            calendar: TestFixtures.calendar
        )
        try context.save()

        let stored = try context.fetch(FetchDescriptor<CalendarItem>())
        XCTAssertEqual(stored.count, 1)
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

    func testHiddenOrOrphanedPlanAndInactiveProfileNeverGenerateOccurrences() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let date = TestFixtures.date(2026, 1, 6)
        let task = Activity(
            profile: profile, category: area, name: "Practice",
            plannedStartMinutes: 600, estimatedDurationMinutes: 10,
            startDate: TestFixtures.date()
        )

        area.isActive = false
        XCTAssertTrue(PlanningService.generateMissingCalendarItems(
            profile: profile, date: date, activities: [task], existingItems: [],
            calendar: TestFixtures.calendar
        ).isEmpty)

        area.isActive = true
        task.category = nil
        XCTAssertTrue(PlanningService.generateMissingCalendarItems(
            profile: profile, date: date, activities: [task], existingItems: [],
            calendar: TestFixtures.calendar
        ).isEmpty)

        task.category = area
        profile.isActive = false
        XCTAssertTrue(PlanningService.generateMissingCalendarItems(
            profile: profile, date: date, activities: [task], existingItems: [],
            calendar: TestFixtures.calendar
        ).isEmpty)
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

    func testSevenAMTaskIsOverdueAtEightPMButCompletedTaskIsNot() {
        let day = TestFixtures.date(2026, 1, 6)
        let item = CalendarItem(
            profile: nil, activity: nil, date: day,
            plannedStart: TestFixtures.date(2026, 1, 6, hour: 7)
        )
        let eightPM = TestFixtures.date(2026, 1, 6, hour: 20)

        XCTAssertTrue(PlanningService.isOverdue(item, now: eightPM))
        item.status = .done
        XCTAssertFalse(PlanningService.isOverdue(item, now: eightPM))
    }
}
