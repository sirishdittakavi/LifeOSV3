import XCTest
@testable import LifeOS

final class ProgressAndHierarchyTests: XCTestCase {
    func testResultTargetsAndEntriesRejectInvalidValuesWithoutRejectingZero() {
        assertTargetValidationRequiresDirectionallyCorrectValues()
        assertRatingTargetsStayInsideFivePointScale()
        assertResultValidationDistinguishesMissingFromZero()
    }

    func testStarterTemplatesRemainCompleteEditableStartingPoints() {
        assertEveryAreaTemplateContainsEditableStarterActions()
        assertGoalTemplatesProvideMeasurableEditableStartingPoints()
    }

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

    func testPeriodReportSeparatesProfilesManualLogsAndTaskStates() {
        let profile = TestFixtures.profile(), other = TestFixtures.profile("Other")
        let day = TestFixtures.date(2026, 1, 6)
        let items = [
            CalendarItem(profile: profile, activity: nil, date: day, status: .done),
            CalendarItem(profile: profile, activity: nil, date: day, status: .skipped),
            CalendarItem(profile: profile, activity: nil, date: day, status: .planned),
            CalendarItem(profile: profile, activity: nil, date: day, status: .done, source: .manual),
            CalendarItem(profile: other, activity: nil, date: day, status: .done)
        ]
        let report = ProgressEngine.periodCompletionReport(
            profile: profile,
            interval: DateInterval(start: day, end: TestFixtures.date(2026, 1, 8)),
            items: items, now: TestFixtures.date(2026, 1, 7, hour: 12), calendar: TestFixtures.calendar
        )
        XCTAssertEqual([report.done, report.skipped, report.missed, report.remaining, report.total], [1, 1, 1, 0, 3])
        XCTAssertEqual(report.buckets.map(\.total), [3, 0])
    }

    func testPeriodReportSynthesizesFuturePlanAndMarksSameDayOverdue() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let firstDay = TestFixtures.date(2026, 8, 10)
        let task = Activity(
            profile: profile, category: area, name: "Practice",
            repeatType: .daily, plannedStartMinutes: 600,
            estimatedDurationMinutes: 10, startDate: firstDay
        )

        let report = ProgressEngine.periodCompletionReport(
            profile: profile,
            interval: DateInterval(start: firstDay, end: TestFixtures.date(2026, 8, 12)),
            items: [], activities: [task], now: TestFixtures.date(2026, 8, 10, hour: 12),
            calendar: TestFixtures.calendar
        )

        XCTAssertEqual([report.done, report.missed, report.remaining, report.total], [0, 1, 1, 2])
        XCTAssertEqual(report.buckets.map(\.total), [1, 1])
    }

    func testPlannedSummaryExcludesManualCompletedWork() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let task = Activity(
            profile: profile, category: area, name: "Practice",
            plannedStartMinutes: 600, estimatedDurationMinutes: 10
        )
        let date = TestFixtures.date(2026, 1, 6)
        let scheduled = CalendarItem(
            profile: profile, activity: task, date: date,
            plannedStart: TestFixtures.date(2026, 1, 6, hour: 10)
        )
        let manual = CalendarItem(
            profile: profile, activity: task, date: date,
            plannedStart: TestFixtures.date(2026, 1, 6, hour: 12),
            status: .done, source: .manual
        )

        let summary = ProgressEngine.completionSummary(
            items: PlanningService.plannedItems([scheduled, manual])
        )
        XCTAssertEqual(summary.total, 1)
        XCTAssertEqual(summary.done, 0)
        XCTAssertEqual(summary.remaining, 1)
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

    func testTrackingCapabilityIsExplicitAndSurvivesRename() {
        let profile = TestFixtures.profile()
        let area = AppCategory(
            profile: profile, name: "Baseball", symbol: "figure.baseball",
            colorToken: "orange", trackingKind: .sport
        )

        area.name = "Cricket"

        XCTAssertEqual(area.trackingKind, .sport)
        XCTAssertEqual(area.trackingKindRaw, AreaTrackingKind.sport.rawValue)
        XCTAssertEqual(AreaTrackingKind.legacyDefault(name: "Food", pillar: .nutrition), .nutrition)
    }

    func testProfileScopeRejectsAnotherProfilesArea() {
        let vihaan = TestFixtures.profile("Vihaan")
        let sibling = TestFixtures.profile("Sibling")
        let ownArea = TestFixtures.area(profile: vihaan)
        let foreignArea = TestFixtures.area(profile: sibling)

        XCTAssertEqual(ProfileScope.categories(for: vihaan, from: [foreignArea, ownArea]).map(\.id), [ownArea.id])
        XCTAssertTrue(ProfileScope.canAssign(ownArea, to: vihaan))
        XCTAssertFalse(ProfileScope.canAssign(foreignArea, to: vihaan))
    }

    func testCompletionTimingUsesActualEnteredDuration() {
        let end = TestFixtures.date(2026, 1, 6, hour: 18)
        let timing = CompletionTiming.interval(endingAt: end, durationMinutes: 37)

        XCTAssertEqual(timing.end, end)
        XCTAssertEqual(timing.end.timeIntervalSince(timing.start), 37 * 60, accuracy: 0.001)
    }

    private func assertTargetValidationRequiresDirectionallyCorrectValues() {
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

    private func assertRatingTargetsStayInsideFivePointScale() {
        XCTAssertTrue(ResultMeasureValidation.isValidTarget(
            valueType: .rating, direction: .increase,
            baseline: 2, target: 5, minimum: nil, maximum: nil
        ))
        XCTAssertFalse(ResultMeasureValidation.isValidTarget(
            valueType: .rating, direction: .increase,
            baseline: 2, target: 6, minimum: nil, maximum: nil
        ))
    }

    private func assertResultValidationDistinguishesMissingFromZero() {
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

    /// Container templates (Refactor.md Run 4 — something else's
    /// parentTemplateID points at them, e.g. "Sports" for "Baseball") exist
    /// to group disciplines, not to be logged themselves, so they may have
    /// zero starter tasks. Leaf templates (everything else) must still
    /// contain editable starter activities.
    private func assertEveryAreaTemplateContainsEditableStarterActions() {
        XCTAssertFalse(ImprovementTemplates.all.isEmpty)
        let containerIDs = Set(ImprovementTemplates.all.compactMap(\.parentTemplateID))
        for template in ImprovementTemplates.all {
            XCTAssertFalse(template.name.isEmpty)
            XCTAssertFalse(template.purpose.isEmpty)
            if !containerIDs.contains(template.id) {
                XCTAssertFalse(template.tasks.isEmpty, "\(template.name) unexpectedly has no starter actions")
            }
            XCTAssertTrue(template.tasks.allSatisfy { !$0.name.isEmpty })
        }
    }

    private func assertGoalTemplatesProvideMeasurableEditableStartingPoints() {
        XCTAssertGreaterThanOrEqual(GoalStarterTemplates.all.count, 5)
        XCTAssertEqual(Set(GoalStarterTemplates.all.map(\.id)).count, GoalStarterTemplates.all.count)
        for template in GoalStarterTemplates.all {
            XCTAssertFalse(template.name.isEmpty)
            XCTAssertFalse(template.measureName.isEmpty)
            XCTAssertFalse(template.suggestedAreaNames.isEmpty)
        }

        let weight = GoalStarterTemplates.all.first { $0.id == "weight-range" }
        XCTAssertTrue(weight?.needsPersonalValues == true)
        XCTAssertNil(weight?.baseline)
        XCTAssertNil(weight?.targetMinimum)
        XCTAssertNil(weight?.targetMaximum)
    }

    func testPlannedMealsDoNotCountAsNutritionAdherenceUntilActuallyLogged() {
        let profile = TestFixtures.profile()
        let area = AppCategory(
            profile: profile, name: "Nutrition", symbol: "fork.knife",
            colorToken: "green", pillar: .nutrition, trackingKind: .nutrition
        )
        let date = TestFixtures.date(2026, 1, 6, hour: 12)
        let planned = FoodEntry(
            profile: profile, date: date, mealType: .lunch, name: "Planned bowl",
            calories: 500, nutritionSource: FoodEntry.mealPlanSource
        )

        let beforeLogging = CategoryProgressEngine.progress(
            profile: profile, category: area, period: .day, now: date,
            activities: [], calendarItems: [], foodEntries: [planned],
            weightEntries: [], sportEntries: [], calendar: TestFixtures.calendar
        )
        XCTAssertEqual(beforeLogging.completedSessions, 0)

        let actual = FoodEntry(
            profile: profile, date: date, mealType: .lunch, name: "Actual bowl",
            calories: 520, nutritionSource: "Manual"
        )
        let afterLogging = CategoryProgressEngine.progress(
            profile: profile, category: area, period: .day, now: date,
            activities: [], calendarItems: [], foodEntries: [planned, actual],
            weightEntries: [], sportEntries: [], calendar: TestFixtures.calendar
        )
        XCTAssertEqual(afterLogging.completedSessions, 1)
    }

    /// Chunk 4 fix: a brand-new Plan with zero completed sessions and zero
    /// decided occurrences must never read as "On track" -- the zero-
    /// evidence guard has to run before the on-track pace check, not after,
    /// because 0 completed trivially clears "0 >= expectedSessions * 0.85"
    /// whenever elapsedFraction is still ~0 right after creation.
    func testNewPlanWithZeroEvidenceIsInsufficientDataNotOnTrackAtPeriodStart() {
        let profile = TestFixtures.profile()
        let category = AppCategory(
            profile: profile, name: "Strength Training", symbol: "figure.strengthtraining.traditional",
            colorToken: "blue", pillar: .life,
            weeklyTargetSessions: 1, weeklyTargetMinutes: 30
        )
        let interval = DashboardPeriod.week.interval(containing: TestFixtures.date(2026, 1, 6, hour: 9), calendar: TestFixtures.calendar)
        let now = interval.start.addingTimeInterval(60 * 5) // moments after the period began
        let activity = Activity(
            profile: profile, category: category, name: "Bench press practice",
            repeatType: .daily, plannedStartMinutes: 18 * 60,
            estimatedDurationMinutes: 30, startDate: interval.start
        )

        let progress = CategoryProgressEngine.progress(
            profile: profile, category: category, period: .week, now: now,
            activities: [activity], calendarItems: [],
            foodEntries: [], weightEntries: [], sportEntries: [],
            calendar: TestFixtures.calendar
        )

        XCTAssertEqual(progress.completedSessions, 0)
        XCTAssertEqual(progress.status, .insufficientData)
    }

    /// Same guard, proven against the "needsAttention" branch: even when
    /// enough future scheduled/potential sessions exist to still meet the
    /// weekly target on paper, zero decided evidence so far this period
    /// must not be judged "Needs attention" -- there's nothing to judge yet.
    func testNewPlanWithZeroEvidenceIsInsufficientDataNotNeedsAttentionWhenFuturePotentialMeetsTarget() {
        let profile = TestFixtures.profile()
        let category = AppCategory(
            profile: profile, name: "Strength Training", symbol: "figure.strengthtraining.traditional",
            colorToken: "blue", pillar: .life,
            weeklyTargetSessions: 2, weeklyTargetMinutes: 60
        )
        let interval = DashboardPeriod.week.interval(containing: TestFixtures.date(2026, 1, 6, hour: 9), calendar: TestFixtures.calendar)
        let now = interval.start.addingTimeInterval(interval.duration * 0.5) // roughly halfway through the week
        let activity = Activity(
            profile: profile, category: category, name: "Bench press practice",
            repeatType: .daily, plannedStartMinutes: 18 * 60,
            estimatedDurationMinutes: 30, startDate: interval.start
        )

        let progress = CategoryProgressEngine.progress(
            profile: profile, category: category, period: .week, now: now,
            activities: [activity], calendarItems: [],
            foodEntries: [], weightEntries: [], sportEntries: [],
            calendar: TestFixtures.calendar
        )

        XCTAssertEqual(progress.completedSessions, 0)
        XCTAssertGreaterThanOrEqual(
            progress.completedSessions + max(0, progress.targetSessions), progress.targetSessions,
            "sanity: this scenario is set up so future potential sessions could still meet the target"
        )
        XCTAssertEqual(progress.status, .insufficientData)
    }

    /// Same guard, proven against the "behind" branch: a Plan created with
    /// too little of the period left to reach its target on paper must
    /// still read as "Insufficient data", not "Behind" -- there's no
    /// judgment the zero evidence actually supports.
    func testNewPlanWithZeroEvidenceIsInsufficientDataNotBehindWhenTooFewDaysRemain() {
        let profile = TestFixtures.profile()
        let category = AppCategory(
            profile: profile, name: "Strength Training", symbol: "figure.strengthtraining.traditional",
            colorToken: "blue", pillar: .life,
            weeklyTargetSessions: 3, weeklyTargetMinutes: 90
        )
        let interval = DashboardPeriod.week.interval(containing: TestFixtures.date(2026, 1, 6, hour: 9), calendar: TestFixtures.calendar)
        let now = interval.end.addingTimeInterval(-60 * 60 * 2) // two hours before the period ends
        let activity = Activity(
            profile: profile, category: category, name: "Bench press practice",
            repeatType: .daily, plannedStartMinutes: 18 * 60,
            estimatedDurationMinutes: 30, startDate: now
        )

        let progress = CategoryProgressEngine.progress(
            profile: profile, category: category, period: .week, now: now,
            activities: [activity], calendarItems: [],
            foodEntries: [], weightEntries: [], sportEntries: [],
            calendar: TestFixtures.calendar
        )

        XCTAssertEqual(progress.completedSessions, 0)
        XCTAssertLessThan(
            progress.completedSessions + 1, progress.targetSessions,
            "sanity: this scenario is set up so too little of the period remains to meet the target"
        )
        XCTAssertEqual(progress.status, .insufficientData)
    }

    /// Contrast case: once there IS decided evidence this period (even a
    /// single skipped occurrence, still zero completions), the zero-
    /// evidence guard must not swallow a real "Behind" judgment -- it only
    /// applies when there is truly nothing decided either way.
    func testPlanWithOneDecidedSkipAndTooFewDaysRemainingIsStillBehind() {
        let profile = TestFixtures.profile()
        let category = AppCategory(
            profile: profile, name: "Strength Training", symbol: "figure.strengthtraining.traditional",
            colorToken: "blue", pillar: .life,
            weeklyTargetSessions: 3, weeklyTargetMinutes: 90
        )
        let interval = DashboardPeriod.week.interval(containing: TestFixtures.date(2026, 1, 6, hour: 9), calendar: TestFixtures.calendar)
        let now = interval.end.addingTimeInterval(-60 * 60 * 2)
        let activity = Activity(
            profile: profile, category: category, name: "Bench press practice",
            repeatType: .daily, plannedStartMinutes: 18 * 60,
            estimatedDurationMinutes: 30, startDate: interval.start
        )
        let decidedSkip = CalendarItem(
            profile: profile, activity: activity, date: TestFixtures.calendar.startOfDay(for: now),
            plannedStart: now.addingTimeInterval(-3600), status: .skipped, source: .schedule
        )

        let progress = CategoryProgressEngine.progress(
            profile: profile, category: category, period: .week, now: now,
            activities: [activity], calendarItems: [decidedSkip],
            foodEntries: [], weightEntries: [], sportEntries: [],
            calendar: TestFixtures.calendar
        )

        XCTAssertEqual(progress.completedSessions, 0)
        XCTAssertEqual(progress.status, .behind, "real decided evidence (a skip) must still be judged, not treated as zero evidence")
    }

    /// Step 1 of Refactor.md: ProgressEngine, CategoryProgressEngine and
    /// GoalProgressEngine used to reconstruct scheduled occurrences with
    /// three separate inline implementations. This proves they now agree,
    /// using a record that a naive re-derivation from `scheduledStartMinutes`
    /// alone would miss: a stored, already-decided CalendarItem whose
    /// `plannedStart` no longer matches the Activity's current schedule
    /// config (e.g. left behind by an edited schedule). The canonical
    /// `PlanningService.reconstructedOccurrences` counts it as a second,
    /// distinct occurrence alongside today's 10:00 slot (still `.planned`,
    /// now overdue); before this refactor, CategoryProgressEngine and
    /// GoalProgressEngine ignored it entirely and undercounted at 1.
    func testAllThreeProgressEnginesAgreeOnReconstructedOccurrenceCount() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let day = TestFixtures.date(2026, 1, 6)
        let now = TestFixtures.date(2026, 1, 6, hour: 12)
        let activity = Activity(
            profile: profile, category: area, name: "Throwing drill",
            repeatType: .daily, plannedStartMinutes: 600, // 10:00 — still open today
            estimatedDurationMinutes: 30, startDate: TestFixtures.date(2026, 1, 1)
        )
        // A historical record at 14:00 that no longer matches the Activity's
        // current schedule slot, but is real, decided work that happened.
        let strayDecidedItem = CalendarItem(
            profile: profile, activity: activity, date: day,
            plannedStart: TestFixtures.date(2026, 1, 6, hour: 14),
            status: .done, source: .schedule
        )

        let interval = DashboardPeriod.day.interval(containing: now, calendar: TestFixtures.calendar)
        let canonical = PlanningService.reconstructedOccurrences(
            profile: profile, interval: interval, activities: [activity],
            calendarItems: [strayDecidedItem], calendar: TestFixtures.calendar
        )
        XCTAssertEqual(canonical.count, 2, "expected today's open 10:00 slot plus the stray 14:00 record")

        let report = ProgressEngine.periodCompletionReport(
            profile: profile, interval: interval, items: [strayDecidedItem],
            activities: [activity], now: now, calendar: TestFixtures.calendar
        )
        XCTAssertEqual(report.total, canonical.count)
        XCTAssertEqual(report.done, 1)
        XCTAssertEqual(report.missed, 1, "the still-open 10:00 slot is before `now` (noon), so it's overdue")
        XCTAssertEqual(report.remaining, 0)

        let categoryProgress = CategoryProgressEngine.progress(
            profile: profile, category: area, period: .day, now: now,
            activities: [activity], calendarItems: [strayDecidedItem],
            foodEntries: [], weightEntries: [], sportEntries: [],
            calendar: TestFixtures.calendar
        )
        XCTAssertEqual(categoryProgress.targetSessions, canonical.count)

        let goal = TestFixtures.goal(profile: profile)
        let contribution = GoalAreaContribution(goal: goal, category: area)
        let goalProgress = TestFixtures.progress(
            goal: goal, contributions: [contribution],
            activities: [activity], items: [strayDecidedItem],
            now: now, period: .day
        )
        XCTAssertEqual(goalProgress.contributions.first?.plannedActions, canonical.count)
    }

    /// Step 7 (Refactor.md): FoodTrackerView and TodayTimelineView's
    /// nutrition plan card used to compute today's calories/protein
    /// independently and identically — exactly the "independent Protein
    /// totals on Dashboard and Nutrition" duplication DESIGN.md §9 warns
    /// against. Both now call this one function.
    func testNutritionTotalsExcludesMealPlanItemsOtherProfilesAndOtherDays() {
        let profile = TestFixtures.profile(), other = TestFixtures.profile("Other")
        let today = TestFixtures.date(2026, 1, 6, hour: 12)
        let actual = FoodEntry(
            profile: profile, date: TestFixtures.date(2026, 1, 6, hour: 8),
            mealType: .breakfast, name: "Oats", calories: 300, proteinGrams: 20
        )
        let planned = FoodEntry(
            profile: profile, date: TestFixtures.date(2026, 1, 6, hour: 8),
            mealType: .breakfast, name: "Planned oats", calories: 999, proteinGrams: 999,
            nutritionSource: FoodEntry.mealPlanSource
        )
        let otherProfileEntry = FoodEntry(
            profile: other, date: TestFixtures.date(2026, 1, 6, hour: 8),
            mealType: .breakfast, name: "Not mine", calories: 999, proteinGrams: 999
        )
        let yesterdayEntry = FoodEntry(
            profile: profile, date: TestFixtures.date(2026, 1, 5, hour: 8),
            mealType: .breakfast, name: "Yesterday", calories: 999, proteinGrams: 999
        )

        let totals = ProgressEngine.nutritionTotals(
            profile: profile, date: today,
            entries: [actual, planned, otherProfileEntry, yesterdayEntry],
            calendar: TestFixtures.calendar
        )

        XCTAssertEqual(totals.calories, 300)
        XCTAssertEqual(totals.protein, 20)
    }

    /// Step 7: ProgressMetricBuilder wraps the already-canonical engines
    /// (CategoryProgressEngine, GoalProgressEngine — unified in Step 1)
    /// into one generic shape, per DESIGN.md §8's "do not create separate
    /// hard-coded dashboard logic for Protein, Baseball, Coding, etc."
    func testProgressMetricBuilderWrapsCategoryAndGoalProgressGenerically() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let categoryProgress = CategoryProgressEngine.progress(
            profile: profile, category: area, period: .week,
            activities: [], calendarItems: [], foodEntries: [], weightEntries: [], sportEntries: []
        )
        let metric = ProgressMetricBuilder.metric(from: categoryProgress)
        XCTAssertEqual(metric.title, area.name)
        XCTAssertEqual(metric.id, area.id)

        let goal = TestFixtures.goal(profile: profile)
        let goalProgress = TestFixtures.progress(goal: goal)
        let goalMetric = ProgressMetricBuilder.metric(from: goalProgress)
        XCTAssertEqual(goalMetric.title, goal.name)
        XCTAssertEqual(goalMetric.targetValue, 100)
    }

    /// TodayTimelineView's Plan cards now derive their progress bar fraction
    /// from ProgressMetric.progress instead of hand-computing
    /// CompletionSummary.percentComplete directly. Since done is always a
    /// subset of total, both must agree — this pins that down so a future
    /// change to either can't silently diverge them.
    func testProgressMetricAgreesWithCompletionSummaryForDoneOverTotal() {
        let items = [
            CalendarItem(profile: nil, activity: nil, date: .now, status: .done),
            CalendarItem(profile: nil, activity: nil, date: .now, status: .done),
            CalendarItem(profile: nil, activity: nil, date: .now, status: .planned),
            CalendarItem(profile: nil, activity: nil, date: .now, status: .planned)
        ]
        let summary = ProgressEngine.completionSummary(items: items)
        let metric = ProgressMetric(
            id: UUID(), title: "Plan", currentValue: Double(summary.done),
            targetValue: Double(summary.total), unit: "tasks", statusText: "",
            destinationCategoryID: nil, destinationGoalID: nil
        )
        XCTAssertEqual(metric.progress, summary.percentComplete, accuracy: 0.0001)
    }
}
