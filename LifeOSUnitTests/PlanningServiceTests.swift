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

    /// Step 3 (Refactor.md): backs the delete-vs-archive decision for
    /// EditTaskView — an Activity with only untouched planned occurrences
    /// (however many, on however many days) has no history to lose and is
    /// safe to delete outright; anything decided, manual, or annotated means
    /// it must be archived instead.
    func testHasAnyHistoryDistinguishesUntouchedPlansFromRealRecords() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let task = Activity(
            profile: profile, category: area, name: "Practice",
            repeatType: .daily, plannedStartMinutes: 420,
            estimatedDurationMinutes: 10, startDate: TestFixtures.date(2026, 8, 9)
        )
        let untouchedToday = CalendarItem(
            profile: profile, activity: task, date: TestFixtures.date(2026, 8, 9),
            plannedStart: TestFixtures.date(2026, 8, 9, hour: 7)
        )
        let untouchedTomorrow = CalendarItem(
            profile: profile, activity: task, date: TestFixtures.date(2026, 8, 10),
            plannedStart: TestFixtures.date(2026, 8, 10, hour: 7)
        )
        XCTAssertFalse(PlanningService.hasAnyHistory(for: task, in: [untouchedToday, untouchedTomorrow]))

        let skipped = CalendarItem(
            profile: profile, activity: task, date: TestFixtures.date(2026, 8, 9),
            plannedStart: TestFixtures.date(2026, 8, 9, hour: 7), status: .skipped
        )
        XCTAssertTrue(
            PlanningService.hasAnyHistory(for: task, in: [untouchedToday, untouchedTomorrow, skipped]),
            "a decided occurrence (even just Skipped, not Done) counts as history"
        )

        let otherTask = Activity(
            profile: profile, category: area, name: "Other",
            plannedStartMinutes: 480, estimatedDurationMinutes: 10, startDate: TestFixtures.date(2026, 8, 9)
        )
        let otherDone = CalendarItem(
            profile: profile, activity: otherTask, date: TestFixtures.date(2026, 8, 9),
            plannedStart: TestFixtures.date(2026, 8, 9, hour: 8), status: .done
        )
        XCTAssertFalse(
            PlanningService.hasAnyHistory(for: task, in: [untouchedToday, otherDone]),
            "another Activity's history must never leak into this one's delete-safety check"
        )

        let manualEntry = CalendarItem(
            profile: profile, activity: task, date: TestFixtures.date(2026, 8, 9),
            plannedStart: TestFixtures.date(2026, 8, 9, hour: 7), source: .manual
        )
        XCTAssertTrue(
            PlanningService.hasAnyHistory(for: task, in: [manualEntry]),
            "a manual entry counts as history even while still status .planned"
        )
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

    /// Step 2 (Refactor.md): direct coverage of `.selectedWeekdays`, the one
    /// V1 repeat type that previously only had indirect coverage (via a
    /// reconciliation test). Also pins down the weekday numbering contract
    /// documented in DESIGN.md §13's `"weekdays": [2, 3, 4, 5, 6]` example —
    /// Foundation's Sunday = 1 ... Saturday = 7 — so a regression here would
    /// be caught even if `Calendar.component(.weekday:)` semantics changed.
    func testSelectedWeekdaysOnlyScheduleOnConfiguredDaysWithCorrectMapping() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let action = Activity(
            profile: profile, category: area, name: "Practice",
            repeatType: .selectedWeekdays, weekdays: [2, 4, 6], // Mon, Wed, Fri
            plannedStartMinutes: 600, estimatedDurationMinutes: 20,
            startDate: TestFixtures.date(2026, 1, 1)
        )
        let week = (5...11).map { TestFixtures.date(2026, 1, $0) } // Mon Jan 5 ... Sun Jan 11

        let weekdayNumbers = week.map { TestFixtures.calendar.component(.weekday, from: $0) }
        XCTAssertEqual(weekdayNumbers, [2, 3, 4, 5, 6, 7, 1], "Sun=1...Sat=7, per DESIGN.md's weekday examples")

        let scheduled = week.map { PlanningService.scheduledStartMinutes(action, on: $0, calendar: TestFixtures.calendar) }
        XCTAssertEqual(scheduled, [[600], [], [600], [], [600], [], []])
    }

    /// Step 2: `.selectedWeekdays` and `.timesPerWeek` derive purely from a
    /// date's weekday, with no per-week counter — so the same weekday must
    /// schedule identically every week, indefinitely. Confirms there's no
    /// week-boundary state that could drift or reset.
    func testSelectedWeekdaysAndTimesPerWeekRepeatIdenticallyAcrossWeeks() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let weekly = Activity(
            profile: profile, category: area, name: "Weekly practice",
            repeatType: .selectedWeekdays, weekdays: [2, 5], // Mon, Thu
            plannedStartMinutes: 540, estimatedDurationMinutes: 20,
            startDate: TestFixtures.date(2026, 1, 1)
        )
        let distributed = Activity(
            profile: profile, category: area, name: "Distributed practice",
            repeatType: .timesPerWeek, weekdays: [2, 4, 6], occurrencesPerWeek: 4,
            repeatIntervalMinutes: 15, plannedStartMinutes: 480,
            estimatedDurationMinutes: 10, startDate: TestFixtures.date(2026, 1, 1)
        )
        // The same weekday, four consecutive Mondays.
        let mondays = [5, 12, 19, 26].map { TestFixtures.date(2026, 1, $0) }

        let weeklyResults = mondays.map { PlanningService.scheduledStartMinutes(weekly, on: $0, calendar: TestFixtures.calendar) }
        XCTAssertEqual(weeklyResults, Array(repeating: [540], count: 4))

        let distributedResults = mondays.map { PlanningService.scheduledStartMinutes(distributed, on: $0, calendar: TestFixtures.calendar) }
        XCTAssertEqual(distributedResults, Array(repeating: [480, 495], count: 4))
    }

    /// Step 2: exercises the exact reconcile-then-regenerate sequence
    /// `EditTaskView.save()` performs in production — editing a repeating
    /// schedule must both drop occurrences that no longer belong (even on
    /// future days already generated by the Week view) and let the correct
    /// new occurrences be generated in their place, without duplicating the
    /// occurrences that remain valid on both the old and new schedule.
    func testEditingScheduleTypeProducesCorrectFutureOccurrencesWithoutDuplicates() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let monday = TestFixtures.date(2026, 1, 5)
        let action = Activity(
            profile: profile, category: area, name: "Practice",
            repeatType: .daily, plannedStartMinutes: 600,
            estimatedDurationMinutes: 20, startDate: monday
        )
        let weekdays = (5...9).map { TestFixtures.date(2026, 1, $0) } // Mon...Fri
        var items = weekdays.flatMap { day in
            PlanningService.generateMissingCalendarItems(
                profile: profile, date: day, activities: [action],
                existingItems: [], calendar: TestFixtures.calendar
            )
        }
        XCTAssertEqual(items.count, 5, "one daily occurrence generated per weekday")

        // Edit: switch to Mon/Wed/Fri only — Tue and Thu no longer apply.
        action.repeatType = .selectedWeekdays
        action.weekdays = [2, 4, 6]

        let stale = PlanningService.reconcileUntouchedOccurrences(
            for: action, in: items, calendar: TestFixtures.calendar
        )
        XCTAssertEqual(
            Set(stale.map(\.id)),
            Set([items[1].id, items[3].id]), // Tuesday (Jan 6), Thursday (Jan 8)
            "only the occurrences that fell off the new schedule should be marked stale"
        )
        let staleIDs = Set(stale.map(\.id))
        items.removeAll { staleIDs.contains($0.id) }

        let regenerated = weekdays.flatMap { day in
            PlanningService.generateMissingCalendarItems(
                profile: profile, date: day, activities: [action],
                existingItems: items, calendar: TestFixtures.calendar
            )
        }
        XCTAssertTrue(regenerated.isEmpty, "Mon/Wed/Fri already exist and Tue/Thu are no longer scheduled")
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(
            Set(items.compactMap { $0.plannedStart.map { TestFixtures.calendar.component(.weekday, from: $0) } }),
            Set([2, 4, 6])
        )
        XCTAssertEqual(Set(items.compactMap { PlanningService.occurrenceIdentity(for: $0, calendar: TestFixtures.calendar) }).count, 3)
    }

    /// Reproduces the exact sequence EditTaskView.deleteOrArchive() runs,
    /// through a real ModelContext/save — not bare Swift objects — because
    /// SwiftData's default relationship behavior on delete (nullify vs.
    /// cascade) can only surface through a real persistence round-trip.
    /// Also mirrors real app usage: today's item generated via
    /// insertMissingCalendarItems (as TodayTimelineView does) *and* a
    /// future item pre-generated ahead of time (as WeeklyScheduleView's
    /// generateVisibleWeek does for the whole visible week).
    @MainActor
    func testDeletingActivityWithNoHistoryRemovesTodayAndFutureItemsWithoutOrphaning() throws {
        let container = try ModelContainer(
            for: Profile.self, SavedCategoryTemplate.self, AppCategory.self, Goal.self,
            GoalAreaContribution.self, ResultMeasure.self, ResultEntry.self, Activity.self,
            CalendarItem.self, ActivitySession.self, FoodEntry.self, WeightEntry.self, SportEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let today = TestFixtures.date(2026, 1, 6)
        let tomorrow = TestFixtures.date(2026, 1, 7)
        let action = Activity(
            profile: profile, category: area, name: "Practice",
            repeatType: .daily, plannedStartMinutes: 600,
            estimatedDurationMinutes: 20, startDate: today
        )
        context.insert(profile)
        context.insert(area)
        context.insert(action)
        try context.save()

        try PlanningService.insertMissingCalendarItems(
            profile: profile, date: today, activities: [action], context: context,
            calendar: TestFixtures.calendar
        )
        try PlanningService.insertMissingCalendarItems(
            profile: profile, date: tomorrow, activities: [action], context: context,
            calendar: TestFixtures.calendar
        )
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<CalendarItem>()).count, 2)

        // Exactly EditTaskView.deleteOrArchive()'s no-history branch.
        let allItems = try context.fetch(FetchDescriptor<CalendarItem>())
        XCTAssertFalse(PlanningService.hasAnyHistory(for: action, in: allItems))
        allItems.filter { $0.activity?.id == action.id }.forEach(context.delete)
        context.delete(action)
        try context.save()

        let remainingItems = try context.fetch(FetchDescriptor<CalendarItem>())
        XCTAssertTrue(remainingItems.isEmpty, "today's and tomorrow's occurrences must both be gone, not orphaned")
        XCTAssertTrue(try context.fetch(FetchDescriptor<Activity>()).isEmpty)
    }

    /// Same real-persistence setup, but today's occurrence already has
    /// history (Done) before the delete/archive action runs — the activity
    /// must be archived, not deleted, and today's decided item must survive
    /// with its Activity link intact (never orphaned to a blank "Task" row),
    /// while tomorrow's still-untouched placeholder is cleaned up.
    @MainActor
    func testArchivingActivityWithTodayHistoryKeepsTodayLinkedAndDropsFuturePlaceholder() throws {
        let container = try ModelContainer(
            for: Profile.self, SavedCategoryTemplate.self, AppCategory.self, Goal.self,
            GoalAreaContribution.self, ResultMeasure.self, ResultEntry.self, Activity.self,
            CalendarItem.self, ActivitySession.self, FoodEntry.self, WeightEntry.self, SportEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let today = TestFixtures.date(2026, 1, 6)
        let tomorrow = TestFixtures.date(2026, 1, 7)
        let action = Activity(
            profile: profile, category: area, name: "Practice",
            repeatType: .daily, plannedStartMinutes: 600,
            estimatedDurationMinutes: 20, startDate: today
        )
        context.insert(profile)
        context.insert(area)
        context.insert(action)
        try context.save()

        try PlanningService.insertMissingCalendarItems(
            profile: profile, date: today, activities: [action], context: context,
            calendar: TestFixtures.calendar
        )
        try PlanningService.insertMissingCalendarItems(
            profile: profile, date: tomorrow, activities: [action], context: context,
            calendar: TestFixtures.calendar
        )
        try context.save()

        let todayItem = try XCTUnwrap(try context.fetch(FetchDescriptor<CalendarItem>()).first {
            TestFixtures.calendar.isSameDay($0.date, as: today)
        })
        todayItem.status = .done
        try context.save()

        // Exactly EditTaskView.deleteOrArchive()'s history branch.
        let allItems = try context.fetch(FetchDescriptor<CalendarItem>())
        XCTAssertTrue(PlanningService.hasAnyHistory(for: action, in: allItems))
        action.isActive = false
        PlanningService.reconcileUntouchedOccurrences(
            for: action, in: allItems, calendar: TestFixtures.calendar
        ).forEach(context.delete)
        try context.save()

        let remainingItems = try context.fetch(FetchDescriptor<CalendarItem>())
        XCTAssertEqual(remainingItems.count, 1)
        let survivor = try XCTUnwrap(remainingItems.first)
        XCTAssertTrue(TestFixtures.calendar.isSameDay(survivor.date, as: today))
        XCTAssertNotNil(survivor.activity, "today's decided occurrence must stay linked to its Activity, never orphaned")
        XCTAssertEqual(survivor.activity?.id, action.id)
        XCTAssertFalse(try XCTUnwrap(try context.fetch(FetchDescriptor<Activity>()).first).isActive)
    }
}
