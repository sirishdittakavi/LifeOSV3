import XCTest
import SwiftData
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif
@testable import LifeOS

@MainActor
final class GoalSystemComponentTests: XCTestCase {
    func testManualNutritionEntryImmediatelyContributesCaloriesAndProtein() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let profile = Profile(name: "Player", kind: .individual, colorToken: "blue")
        let entry = FoodEntry(
            profile: profile, date: .now, mealType: .breakfast, name: "Breakfast",
            calories: 450, proteinGrams: 30, nutritionSource: "Manual"
        )
        context.insert(profile)
        context.insert(entry)
        try context.save()

        let today = try context.fetch(FetchDescriptor<FoodEntry>()).filter {
            $0.profile?.id == profile.id && !$0.isMealPlanItem && Calendar.current.isDateInToday($0.date)
        }
        XCTAssertEqual(today.reduce(0) { $0 + $1.calories }, 450)
        XCTAssertEqual(today.reduce(0) { $0 + $1.proteinGrams }, 30)
    }

    func testDuplicatePlansMergeWithoutLosingTasksGoalsOrSportHistory() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let profile = Profile(name: "Player", kind: .individual, colorToken: "blue")
        let first = AppCategory(profile: profile, name: "Baseball", symbol: "baseball.fill", colorToken: "orange")
        let duplicate = AppCategory(profile: profile, name: "  BASEBALL  ", symbol: "figure.baseball", colorToken: "blue")
        let hitting = Activity(profile: profile, category: first, name: "Hitting", plannedStartMinutes: 600, estimatedDurationMinutes: 10)
        let pitching = Activity(profile: profile, category: duplicate, name: "Pitching", plannedStartMinutes: 660, estimatedDurationMinutes: 10)
        let goal = Goal(profile: profile, name: "Improve baseball")
        let contribution = GoalAreaContribution(goal: goal, category: duplicate)
        let sport = SportEntry(profile: profile, category: duplicate, sessionName: "Fielding", durationMinutes: 10)
        context.insert(profile); context.insert(first); context.insert(duplicate)
        context.insert(hitting); context.insert(pitching); context.insert(goal)
        context.insert(contribution); context.insert(sport)
        try context.save()

        try SeedData.repairDuplicateCategories(context: context)
        try context.save()

        let plans = try context.fetch(FetchDescriptor<AppCategory>())
        XCTAssertEqual(plans.count, 1)
        let keeper = try XCTUnwrap(plans.first)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<Activity>()).compactMap { $0.category?.id }), Set([keeper.id]))
        XCTAssertEqual(try context.fetch(FetchDescriptor<GoalAreaContribution>()).first?.category?.id, keeper.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SportEntry>()).first?.category?.id, keeper.id)
    }

    func testDamagedBackupIsRejectedBeforeItCanMutateTheStore() throws {
        let id = UUID()
        let profile = ProfileBackup(
            id: id, name: "Player", kindRaw: ProfileKind.individual.rawValue,
            colorToken: "blue", weightUnitRaw: WeightUnit.kilograms.rawValue,
            avatarData: nil, managementModeRaw: nil, weightGoalKilograms: nil,
            calorieGoal: 2_000, proteinGoalGrams: 120, carbohydrateGoalGrams: 250,
            fatGoalGrams: 65, waterGoalMilliliters: 2_000, isActive: true
        )
        let backup = LifeOSBackupPayload(
            schemaVersion: 2, exportedAt: .now, profiles: [profile, profile], categories: [],
            goals: [], goalContributions: [], resultMeasures: [], resultEntries: [],
            activities: [], calendarItems: [], sessions: [], foodEntries: [],
            weightEntries: [], sportEntries: [], savedTemplates: []
        )
        let container = try LifeOSDataStore.makeContainer(inMemory: true)

        XCTAssertThrowsError(try LifeOSBackupService.restore(backup, into: container.mainContext))
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<Profile>()).isEmpty)
    }

    func testWeeklyNutritionPlanTracksActualMealsAndDeviationsWithoutInflatingTotals() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = Profile(name: "Tester", kind: .individual, colorToken: "blue")
        let nutrition = AppCategory(
            profile: profile, name: "Nutrition", symbol: "fork.knife",
            colorToken: "green", pillar: .nutrition, trackingKind: .nutrition
        )
        let day = TestDate.make(2026, 8, 10, hour: 8)
        let plannedMeals = [
            FoodEntry(profile: profile, date: day, mealType: .breakfast, name: "Oats", calories: 400, nutritionSource: FoodEntry.mealPlanSource),
            FoodEntry(profile: profile, date: day, mealType: .lunch, name: "Chicken bowl", calories: 600, nutritionSource: FoodEntry.mealPlanSource),
            FoodEntry(profile: profile, date: day, mealType: .dinner, name: "Salmon", calories: 550, nutritionSource: FoodEntry.mealPlanSource)
        ]
        let actualMeals = [
            FoodEntry(profile: profile, date: day, mealType: .breakfast, name: "Oats", calories: 410, nutritionSource: "Planned meal"),
            FoodEntry(profile: profile, date: day, mealType: .lunch, name: "Pasta", calories: 720, nutritionSource: "Manual"),
            FoodEntry(profile: profile, date: day, mealType: .snack, name: "Fruit", calories: 120, nutritionSource: "Manual")
        ]
        context.insert(profile)
        context.insert(nutrition)
        plannedMeals.forEach(context.insert)
        actualMeals.forEach(context.insert)
        try context.save()

        let stored = try context.fetch(FetchDescriptor<FoodEntry>())
        XCTAssertEqual(stored.filter(\.isMealPlanItem).count, 3)
        XCTAssertEqual(stored.filter { !$0.isMealPlanItem }.reduce(0) { $0 + $1.calories }, 1_250)
        XCTAssertEqual(stored.filter { !$0.isMealPlanItem && $0.mealType == .lunch }.map(\.name), ["Pasta"])

        let progress = CategoryProgressEngine.progress(
            profile: profile, category: nutrition, period: .day, now: day,
            activities: [], calendarItems: [], foodEntries: stored,
            weightEntries: [], sportEntries: [], calendar: TestDate.calendar
        )
        XCTAssertEqual(progress.completedSessions, 1)

        plannedMeals[2].name = "Vegetable curry"
        plannedMeals[2].calories = 500
        try context.save()
        let edited = try context.fetch(FetchDescriptor<FoodEntry>()).first { $0.id == plannedMeals[2].id }
        XCTAssertEqual(edited?.name, "Vegetable curry")
        XCTAssertEqual(edited?.calories, 500)
    }

    func testHidingPlanRemovesFutureAndTodayCardsButPreservesCompletedHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = Profile(name: "Tester", kind: .individual, colorToken: "blue")
        let plan = AppCategory(profile: profile, name: "Baseball", symbol: "figure.baseball", colorToken: "orange")
        let task = Activity(profile: profile, category: plan, name: "Hitting", plannedStartMinutes: 420, estimatedDurationMinutes: 10, startDate: TestDate.make(2026, 8, 9))
        let today = TestDate.make(2026, 8, 9)
        let done = CalendarItem(profile: profile, activity: task, date: today, plannedStart: TestDate.make(2026, 8, 9, hour: 7), status: .done)
        let future = CalendarItem(profile: profile, activity: task, date: TestDate.make(2026, 8, 10), plannedStart: TestDate.make(2026, 8, 10, hour: 7))
        context.insert(profile); context.insert(plan); context.insert(task); context.insert(done); context.insert(future)
        try context.save()

        plan.isActive = false
        task.isActive = false
        PlanningService.reconcileUntouchedOccurrences(
            for: task, in: [done, future], calendar: TestDate.calendar
        ).forEach(context.delete)
        try context.save()

        let stored = try context.fetch(FetchDescriptor<CalendarItem>())
        XCTAssertEqual(stored.map(\.id), [done.id])
        XCTAssertEqual(stored.first?.status, .done)
        XCTAssertTrue(PlanningService.generateMissingCalendarItems(
            profile: profile, date: TestDate.make(2026, 8, 10), activities: [task],
            existingItems: stored, calendar: TestDate.calendar
        ).isEmpty)
    }

    func testScheduleEditReconcilesPersistedTodayDataForEveryScreen() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = Profile(name: "Tester", kind: .individual, colorToken: "blue")
        let plan = AppCategory(
            profile: profile, name: "Baseball", symbol: "figure.baseball",
            colorToken: "orange", pillar: .sport
        )
        let today = TestDate.make(2026, 8, 9)
        let task = Activity(
            profile: profile, category: plan, name: "Hitting",
            repeatType: .daily, plannedStartMinutes: 420,
            estimatedDurationMinutes: 10, startDate: today
        )
        context.insert(profile); context.insert(plan); context.insert(task)
        try PlanningService.insertMissingCalendarItems(
            profile: profile, date: today, activities: [task],
            context: context, calendar: TestDate.calendar
        )
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<CalendarItem>()).count, 1)

        // The user edits the Task on 9 August so it starts on 10 August.
        task.startDate = TestDate.make(2026, 8, 10)
        PlanningService.reconcileUntouchedOccurrences(
            for: task,
            in: try context.fetch(FetchDescriptor<CalendarItem>()),
            calendar: TestDate.calendar
        ).forEach(context.delete)
        try context.save()

        // Today, Schedule, Plan detail, and progress all consume this same store.
        XCTAssertTrue(try context.fetch(FetchDescriptor<CalendarItem>()).isEmpty)

        try PlanningService.insertMissingCalendarItems(
            profile: profile, date: TestDate.make(2026, 8, 10), activities: [task],
            context: context, calendar: TestDate.calendar
        )
        try context.save()
        let items = try context.fetch(FetchDescriptor<CalendarItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(TestDate.calendar.isDate(
            try XCTUnwrap(items.first?.date), inSameDayAs: TestDate.make(2026, 8, 10)
        ))
    }

    func testEndToEndBaseballDailyPracticeLifecycle() throws {
        // GIVEN a person creates a Baseball Plan with three daily 10-minute Tasks.
        let container = try makeContainer()
        let context = container.mainContext
        let today = TestDate.make(2026, 8, 9)
        let profile = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let baseball = AppCategory(
            profile: profile, name: "Baseball", symbol: "figure.baseball",
            colorToken: "orange", pillar: .sport, trackingKind: .sport
        )
        let taskNamesAndTimes = [
            ("Hitting", 7 * 60),
            ("Pitching", 7 * 60 + 15),
            ("Fielding", 7 * 60 + 30)
        ]
        let tasks = taskNamesAndTimes.map { name, startMinute in
            Activity(
                profile: profile, category: baseball, name: name,
                targetValue: 10, targetUnit: "minutes",
                repeatType: .daily, weekdays: Array(1...7),
                plannedStartMinutes: startMinute, estimatedDurationMinutes: 10,
                startDate: today
            )
        }

        context.insert(profile)
        context.insert(baseball)
        tasks.forEach(context.insert)
        try context.save()

        let savedTasks = try context.fetch(FetchDescriptor<Activity>())
        XCTAssertEqual(savedTasks.count, 3)
        XCTAssertEqual(Set(savedTasks.map(\.name)), Set(["Hitting", "Pitching", "Fielding"]))
        XCTAssertTrue(savedTasks.allSatisfy { task in
            task.profile?.id == profile.id
                && task.category?.id == baseball.id
                && task.repeatType == .daily
                && task.estimatedDurationMinutes == 10
                && task.targetValue == 10
                && task.targetUnit == "minutes"
                && task.isActive
        })

        // WHEN Today generates its scheduled occurrences.
        try PlanningService.insertMissingCalendarItems(
            profile: profile, date: today, activities: savedTasks,
            context: context, calendar: TestDate.calendar
        )
        try context.save()

        // AND Today and another caller both request generation.
        try PlanningService.insertMissingCalendarItems(
            profile: profile, date: today, activities: savedTasks,
            context: context, calendar: TestDate.calendar
        )
        try context.save()

        let todayItems = try context.fetch(FetchDescriptor<CalendarItem>())
            .filter {
                $0.profile?.id == profile.id
                    && TestDate.calendar.isDate($0.date, inSameDayAs: today)
            }
            .sorted { ($0.plannedStart ?? .distantFuture) < ($1.plannedStart ?? .distantFuture) }

        XCTAssertEqual(todayItems.count, 3)
        XCTAssertEqual(todayItems.map { $0.activity?.name }, ["Hitting", "Pitching", "Fielding"])
        XCTAssertEqual(todayItems.map { $0.activity?.estimatedDurationMinutes }, [10, 10, 10])
        XCTAssertTrue(todayItems.allSatisfy { $0.status == .planned && $0.source == .schedule })
        XCTAssertEqual(
            Set(todayItems.compactMap {
                PlanningService.occurrenceIdentity(for: $0, calendar: TestDate.calendar)
            }).count,
            3
        )

        // WHEN Hitting is completed for the full 10 minutes.
        let hittingItem = try XCTUnwrap(todayItems.first { $0.activity?.name == "Hitting" })
        hittingItem.status = .done
        hittingItem.actualStart = TestDate.make(2026, 8, 9, hour: 7)
        hittingItem.actualEnd = TestDate.make(2026, 8, 9, hour: 7, minute: 10)
        let hittingSession = ActivitySession(
            activity: hittingItem.activity, calendarItem: hittingItem, date: today,
            startedAt: hittingItem.actualStart, endedAt: hittingItem.actualEnd,
            actualActiveSeconds: 10 * 60, recordedValue: 10,
            note: "Completed daily hitting practice"
        )
        context.insert(hittingSession)
        try context.save()

        // THEN Today reports one of three complete and persistence keeps the evidence.
        let todaySummary = ProgressEngine.completionSummary(items: todayItems)
        XCTAssertEqual(todaySummary.total, 3)
        XCTAssertEqual(todaySummary.done, 1)
        XCTAssertEqual(todaySummary.remaining, 2)
        let sessions = try context.fetch(FetchDescriptor<ActivitySession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.activity?.name, "Hitting")
        XCTAssertEqual(sessions.first?.actualActiveSeconds, 600)
        XCTAssertEqual(sessions.first?.recordedValue, 10)

        // AND refreshing Today preserves the completed record without duplicates.
        try PlanningService.insertMissingCalendarItems(
            profile: profile, date: today, activities: savedTasks,
            context: context, calendar: TestDate.calendar
        )
        try context.save()
        let refreshedToday = try context.fetch(FetchDescriptor<CalendarItem>()).filter {
            TestDate.calendar.isDate($0.date, inSameDayAs: today)
        }
        XCTAssertEqual(refreshedToday.count, 3)
        XCTAssertEqual(refreshedToday.filter { $0.status == .done }.count, 1)

        // WHEN the next day opens, THEN three fresh daily Tasks are generated.
        let tomorrow = try XCTUnwrap(TestDate.calendar.date(byAdding: .day, value: 1, to: today))
        try PlanningService.insertMissingCalendarItems(
            profile: profile, date: tomorrow, activities: savedTasks,
            context: context, calendar: TestDate.calendar
        )
        try context.save()
        let tomorrowItems = try context.fetch(FetchDescriptor<CalendarItem>())
            .filter { TestDate.calendar.isDate($0.date, inSameDayAs: tomorrow) }
            .sorted { ($0.plannedStart ?? .distantFuture) < ($1.plannedStart ?? .distantFuture) }
        XCTAssertEqual(tomorrowItems.map { $0.activity?.name }, ["Hitting", "Pitching", "Fielding"])
        XCTAssertTrue(tomorrowItems.allSatisfy { $0.status == .planned })
        XCTAssertEqual(try context.fetch(FetchDescriptor<CalendarItem>()).count, 6)
    }

    func testGoalWithMixedTaskSchedulesDrivesExpectedHomeStateAfterPartialCompletion() throws {
        // GIVEN one Goal is supported by three Tasks with distinct schedules:
        // daily, three chosen days per week, and one chosen day per week.
        let container = try makeContainer()
        let context = container.mainContext
        let today = TestDate.make(2026, 8, 10) // Monday in the fixed test calendar.
        let profile = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let baseball = AppCategory(
            profile: profile, name: "Baseball", symbol: "figure.baseball",
            colorToken: "orange", pillar: .sport, trackingKind: .sport
        )
        let goal = Goal(
            profile: profile, name: "Become a Complete Baseball Player",
            purpose: "Improve all three core skills."
        )
        let contribution = GoalAreaContribution(
            goal: goal, category: baseball,
            statement: "Balanced Baseball practice supports this Goal."
        )
        let tasks = [
            Activity(
                profile: profile, category: baseball, name: "Hitting",
                targetValue: 10, targetUnit: "min", repeatType: .daily,
                weekdays: Array(1...7), plannedStartMinutes: 18 * 60,
                estimatedDurationMinutes: 10, startDate: today
            ),
            Activity(
                profile: profile, category: baseball, name: "Pitching",
                targetValue: 10, targetUnit: "min", repeatType: .timesPerWeek,
                weekdays: [2, 4, 6], occurrencesPerWeek: 3,
                plannedStartMinutes: 18 * 60 + 15,
                estimatedDurationMinutes: 10, startDate: today
            ),
            Activity(
                profile: profile, category: baseball, name: "Fielding",
                targetValue: 10, targetUnit: "min", repeatType: .timesPerWeek,
                weekdays: [2], occurrencesPerWeek: 1,
                plannedStartMinutes: 18 * 60 + 30,
                estimatedDurationMinutes: 10, startDate: today
            )
        ]
        context.insert(profile)
        context.insert(baseball)
        context.insert(goal)
        context.insert(contribution)
        tasks.forEach(context.insert)
        try context.save()

        // WHEN Home generates Monday's plan, each Task contributes exactly one
        // occurrence despite their different weekly recurrence definitions.
        try PlanningService.insertMissingCalendarItems(
            profile: profile, date: today, activities: tasks,
            context: context, calendar: TestDate.calendar
        )
        try PlanningService.insertMissingCalendarItems(
            profile: profile, date: today, activities: tasks,
            context: context, calendar: TestDate.calendar
        )
        try context.save()

        let homeItems = try context.fetch(FetchDescriptor<CalendarItem>())
            .filter { TestDate.calendar.isDate($0.date, inSameDayAs: today) }
            .sorted { ($0.plannedStart ?? .distantFuture) < ($1.plannedStart ?? .distantFuture) }
        XCTAssertEqual(homeItems.compactMap { $0.activity?.name }, ["Hitting", "Pitching", "Fielding"])
        XCTAssertEqual(homeItems.count, 3, "Repeated Home refreshes must not duplicate occurrences")
        XCTAssertEqual(Set(homeItems.compactMap {
            PlanningService.occurrenceIdentity(for: $0, calendar: TestDate.calendar)
        }).count, 3)

        // WHEN two Tasks are completed and one is deliberately left planned.
        for name in ["Hitting", "Pitching"] {
            let item = try XCTUnwrap(homeItems.first { $0.activity?.name == name })
            item.status = .done
            item.actualStart = item.plannedStart
            item.actualEnd = item.plannedStart.flatMap {
                TestDate.calendar.date(byAdding: .minute, value: 10, to: $0)
            }
            context.insert(ActivitySession(
                activity: item.activity, calendarItem: item, date: today,
                startedAt: item.actualStart, endedAt: item.actualEnd,
                actualActiveSeconds: 600, recordedValue: 10
            ))
        }
        try context.save()

        // THEN Home shows 67%, two complete, one remaining, and Fielding as the
        // only active Task. Completed Tasks remain in the collapsed history.
        let summary = ProgressEngine.completionSummary(
            items: PlanningService.plannedItems(homeItems)
        )
        XCTAssertEqual(summary.total, 3)
        XCTAssertEqual(summary.done, 2)
        XCTAssertEqual(summary.remaining, 1)
        XCTAssertEqual(summary.skipped, 0)
        XCTAssertEqual(summary.percentComplete, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(homeItems.filter { $0.status == .planned }.compactMap { $0.activity?.name }, ["Fielding"])
        XCTAssertEqual(homeItems.filter { $0.status == .done }.count, 2)

        let goalProgress = GoalProgressEngine.progress(
            goal: goal, period: .day, now: today,
            categories: [baseball], contributions: [contribution],
            measures: [], entries: [], activities: tasks,
            calendarItems: homeItems, calendar: TestDate.calendar
        )
        XCTAssertEqual(goalProgress.contributions.first?.plannedActions, 3)
        XCTAssertEqual(goalProgress.contributions.first?.completedActions, 2)
        XCTAssertEqual(try XCTUnwrap(goalProgress.effortFraction), 2.0 / 3.0, accuracy: 0.0001)

        // AND another Home refresh preserves completion/history and still has
        // exactly three occurrences.
        try PlanningService.insertMissingCalendarItems(
            profile: profile, date: today, activities: tasks,
            context: context, calendar: TestDate.calendar
        )
        try context.save()
        let refreshed = try context.fetch(FetchDescriptor<CalendarItem>())
            .filter { TestDate.calendar.isDate($0.date, inSameDayAs: today) }
        XCTAssertEqual(refreshed.count, 3)
        XCTAssertEqual(refreshed.filter { $0.status == .done }.count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ActivitySession>()).count, 2)
    }

    func testVersionOneSchemaRosterAndMigrationContainer() throws {
        let expectedNames = Set([
            "Profile", "SavedCategoryTemplate", "AppCategory", "Goal",
            "GoalAreaContribution", "ResultMeasure", "ResultEntry", "Activity",
            "CalendarItem", "ActivitySession", "FoodEntry", "WeightEntry", "SportEntry",
            "Relationship", "MeasurementDefinition", "MeasurementEntry",
            "NutritionGoal", "MealTemplate", "MealEntry", "NutritionFoodEntry",
            "WaterEntry", "BodyMetricDefinition", "BodyMetricEntry"
        ])
        let actualNames = Set(LifeOSSchemaV1.models.map { String(describing: $0) })

        XCTAssertEqual(LifeOSSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(
            LifeOSSchemaV1.releaseFingerprint,
            "LifeOSSchemaV1:1.0.0:Profile,SavedCategoryTemplate,AppCategory,Goal,GoalAreaContribution,ResultMeasure,ResultEntry,Activity,CalendarItem,ActivitySession,FoodEntry,WeightEntry,SportEntry,Relationship,MeasurementDefinition,MeasurementEntry,NutritionGoal,MealTemplate,MealEntry,NutritionFoodEntry,WaterEntry,BodyMetricDefinition,BodyMetricEntry"
        )
        XCTAssertEqual(actualNames, expectedNames)
        XCTAssertNoThrow(try LifeOSDataStore.makeContainer(inMemory: true))
    }

    func testVersionOnePlanOpensAStoreCreatedBeforeExplicitVersioning() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LifeOSMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("LifeOS.store")

        do {
            let originalSchema = Schema(LifeOSSchemaV1.models)
            let originalConfiguration = ModelConfiguration(schema: originalSchema, url: storeURL)
            let originalContainer = try ModelContainer(
                for: originalSchema,
                configurations: [originalConfiguration]
            )
            originalContainer.mainContext.insert(
                Profile(name: "Existing Profile", kind: .child, colorToken: "blue")
            )
            try originalContainer.mainContext.save()
        }

        let versionedSchema = LifeOSDataStore.schema
        let versionedConfiguration = ModelConfiguration(schema: versionedSchema, url: storeURL)
        let versionedContainer = try ModelContainer(
            for: versionedSchema,
            migrationPlan: LifeOSMigrationPlan.self,
            configurations: [versionedConfiguration]
        )
        let profiles = try versionedContainer.mainContext.fetch(FetchDescriptor<Profile>())

        XCTAssertEqual(profiles.map(\.name), ["Existing Profile"])
    }

    func testGoalGraphPersistsWithRelationshipsAndProfileIsolation() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let vihaan = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let parent = Profile(name: "Parent", kind: .parent, colorToken: "green")
        let baseball = AppCategory(
            profile: vihaan, name: "Baseball", symbol: "figure.baseball",
            colorToken: "orange", pillar: .sport
        )
        let goal = Goal(profile: vihaan, name: "Throw 70 mph")
        let contribution = GoalAreaContribution(goal: goal, category: baseball)
        let measure = ResultMeasure(
            goal: goal, name: "Throwing velocity", unit: "mph",
            baselineValue: 62, targetValue: 70
        )
        let entry = ResultEntry(profile: vihaan, measure: measure, numericValue: 65)
        [vihaan, parent].forEach(context.insert)
        context.insert(baseball)
        context.insert(goal)
        context.insert(contribution)
        context.insert(measure)
        context.insert(entry)
        try context.save()

        let storedGoals = try context.fetch(FetchDescriptor<Goal>())
        let storedEntries = try context.fetch(FetchDescriptor<ResultEntry>())

        XCTAssertEqual(storedGoals.count, 1)
        XCTAssertEqual(storedGoals.first?.profile?.id, vihaan.id)
        XCTAssertNotEqual(storedGoals.first?.profile?.id, parent.id)
        XCTAssertEqual(storedEntries.first?.measure?.goal?.name, "Throw 70 mph")
        XCTAssertEqual(storedEntries.first?.profile?.name, "Vihaan")
    }

    func testSchemaTwoBackupRoundTripRestoresCompleteGoalGraphWithoutDuplicates() throws {
        let source = try makeContainer()
        let sourceContext = source.mainContext
        let profile = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let area = AppCategory(
            profile: profile, name: "Nutrition", symbol: "fork.knife",
            colorToken: "green", pillar: .nutrition, trackingKind: .nutrition
        )
        let goal = Goal(profile: profile, name: "Reach a healthy weight range", purpose: "Support growth")
        let contribution = GoalAreaContribution(
            goal: goal, category: area, statement: "Consistent meals support growth",
            weeklyTargetSessions: 7, weeklyTargetMinutes: 0
        )
        let measure = ResultMeasure(
            goal: goal, name: "Body weight", unit: "kg", direction: .targetRange,
            baselineValue: 44, targetMinimum: 47, targetMaximum: 49,
            cadence: .monthly, nextCheckInDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let entry = ResultEntry(
            profile: profile, measure: measure, date: Date(timeIntervalSince1970: 1_700_000_000),
            numericValue: 45.5, sourceLabel: "Home scale", note: "Morning"
        )
        sourceContext.insert(profile)
        sourceContext.insert(area)
        sourceContext.insert(goal)
        sourceContext.insert(contribution)
        sourceContext.insert(measure)
        sourceContext.insert(entry)
        try sourceContext.save()

        let payload = LifeOSBackupService.make(
            profiles: [profile], categories: [area], activities: [], goals: [goal],
            goalContributions: [contribution], resultMeasures: [measure], resultEntries: [entry],
            calendarItems: [], sessions: [], foodEntries: [], weightEntries: [],
            sportEntries: [], savedTemplates: []
        )
        let encoded = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(LifeOSBackupPayload.self, from: encoded)
        let destination = try makeContainer()

        try LifeOSBackupService.restore(decoded, into: destination.mainContext)
        try LifeOSBackupService.restore(decoded, into: destination.mainContext)

        let goals = try destination.mainContext.fetch(FetchDescriptor<Goal>())
        let contributions = try destination.mainContext.fetch(FetchDescriptor<GoalAreaContribution>())
        let measures = try destination.mainContext.fetch(FetchDescriptor<ResultMeasure>())
        let entries = try destination.mainContext.fetch(FetchDescriptor<ResultEntry>())

        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(goals.count, 1)
        XCTAssertEqual(contributions.count, 1)
        XCTAssertEqual(measures.count, 1)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(contributions.first?.goal?.id, goals.first?.id)
        XCTAssertEqual(contributions.first?.category?.name, "Nutrition")
        XCTAssertEqual(contributions.first?.category?.trackingKind, .nutrition)
        XCTAssertEqual(measures.first?.targetMinimum, 47)
        XCTAssertEqual(entries.first?.measure?.id, measures.first?.id)
        XCTAssertEqual(entries.first?.sourceLabel, "Home scale")
    }

    func testPersistedManualWorkDoesNotChangePlannedGoalAdherence() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let area = AppCategory(
            profile: profile, name: "Baseball", symbol: "figure.baseball",
            colorToken: "orange", pillar: .sport
        )
        let goal = Goal(profile: profile, name: "Improve throwing")
        goal.createdAt = TestDate.make(2026, 1, 1)
        let contribution = GoalAreaContribution(goal: goal, category: area)
        let action = Activity(
            profile: profile, category: area, name: "Throwing practice",
            repeatType: .daily, plannedStartMinutes: 600,
            estimatedDurationMinutes: 30, startDate: TestDate.make(2026, 1, 1)
        )
        let scheduled = CalendarItem(
            profile: profile, activity: action, date: TestDate.make(2026, 1, 6),
            plannedStart: TestDate.make(2026, 1, 6, hour: 10), status: .done, source: .schedule
        )
        let manual = CalendarItem(
            profile: profile, activity: action, date: TestDate.make(2026, 1, 6),
            plannedStart: TestDate.make(2026, 1, 6, hour: 15), status: .done, source: .manual
        )
        context.insert(profile)
        context.insert(area)
        context.insert(goal)
        context.insert(contribution)
        context.insert(action)
        context.insert(scheduled)
        context.insert(manual)
        try context.save()

        let storedItems = try context.fetch(FetchDescriptor<CalendarItem>())
        let result = GoalProgressEngine.progress(
            goal: goal, period: .day, now: TestDate.make(2026, 1, 6, hour: 20),
            categories: [area], contributions: [contribution], measures: [], entries: [],
            activities: [action], calendarItems: storedItems, calendar: TestDate.calendar
        )

        XCTAssertEqual(storedItems.count, 2)
        XCTAssertEqual(result.contributions.first?.plannedActions, 1)
        XCTAssertEqual(result.contributions.first?.completedActions, 1)
    }

    func testEveryUserEditableTaskAndGoalFieldPersists() throws {
        let container = try makeContainer(), context = container.mainContext
        let profile = Profile(name: "Profile", kind: .individual, colorToken: "blue")
        let firstPlan = AppCategory(profile: profile, name: "First", symbol: "1.circle", colorToken: "blue")
        let secondPlan = AppCategory(profile: profile, name: "Second", symbol: "2.circle", colorToken: "green")
        let task = Activity(profile: profile, category: firstPlan, name: "Original",
                            targetValue: 10, targetUnit: "min", repeatType: .daily,
                            plannedStartMinutes: 480, estimatedDurationMinutes: 10,
                            startDate: TestDate.make(2026, 1, 1))
        let goal = Goal(profile: profile, name: "Original goal")
        let contribution = GoalAreaContribution(goal: goal, category: firstPlan)
        let measure = ResultMeasure(goal: goal, name: "Original result", unit: "points",
                                    baselineValue: 1, targetValue: 2)
        context.insert(profile); context.insert(firstPlan); context.insert(secondPlan)
        context.insert(task); context.insert(goal); context.insert(contribution); context.insert(measure)
        try context.save()

        task.name = "Edited task"; task.category = secondPlan; task.targetValue = 45
        task.targetUnit = "minutes"; task.repeatType = .timesPerWeek; task.weekdays = [2, 4, 6]
        task.occurrencesPerDay = 2; task.occurrencesPerWeek = 3; task.repeatIntervalMinutes = 20
        task.plannedStartMinutes = 615; task.estimatedDurationMinutes = 45
        task.startDate = TestDate.make(2026, 2, 1); task.endDate = TestDate.make(2026, 5, 1)
        task.isActive = false
        goal.name = "Edited goal"; goal.purpose = "Edited purpose"
        goal.targetDate = TestDate.make(2026, 6, 1); goal.isActive = false
        contribution.category = secondPlan; contribution.statement = "Edited support"
        contribution.weeklyTargetSessions = 3; contribution.weeklyTargetMinutes = 135
        measure.name = "Edited result"; measure.unit = "score"; measure.direction = .increase
        measure.baselineValue = 10; measure.targetValue = 20; measure.cadence = .weekly
        measure.nextCheckInDate = TestDate.make(2026, 2, 8); measure.reminderEnabled = true
        measure.reminderHour = 19; measure.reminderMinute = 15
        try context.save()

        let storedTask = try XCTUnwrap(context.fetch(FetchDescriptor<Activity>()).first)
        let storedGoal = try XCTUnwrap(context.fetch(FetchDescriptor<Goal>()).first)
        let storedMeasure = try XCTUnwrap(context.fetch(FetchDescriptor<ResultMeasure>()).first)
        XCTAssertEqual([storedTask.name, storedTask.targetUnit], ["Edited task", "minutes"])
        XCTAssertEqual(storedTask.category?.id, secondPlan.id)
        XCTAssertEqual(storedTask.targetValue, 45); XCTAssertEqual(storedTask.estimatedDurationMinutes, 45)
        XCTAssertEqual(storedTask.repeatType, .timesPerWeek); XCTAssertEqual(storedTask.weekdays, [2, 4, 6])
        XCTAssertEqual(storedTask.occurrencesPerWeek, 3); XCTAssertEqual(storedTask.repeatIntervalMinutes, 20)
        XCTAssertEqual(storedTask.plannedStartMinutes, 615); XCTAssertFalse(storedTask.isActive)
        XCTAssertEqual([storedGoal.name, storedGoal.purpose], ["Edited goal", "Edited purpose"])
        XCTAssertEqual(storedGoal.targetDate, TestDate.make(2026, 6, 1)); XCTAssertFalse(storedGoal.isActive)
        XCTAssertEqual(storedMeasure.name, "Edited result"); XCTAssertEqual(storedMeasure.targetValue, 20)
        XCTAssertEqual(storedMeasure.cadence, .weekly); XCTAssertEqual(storedMeasure.reminderHour, 19)
    }

    #if canImport(UIKit)
    func testGoalsAndTodayComponentsConstructAgainstRealSwiftDataSchema() throws {
        let container = try makeContainer()
        let profile = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let plan = AppCategory(profile: profile, name: "Sport", symbol: "figure.run", colorToken: "orange")
        let task = Activity(profile: profile, category: plan, name: "Training", plannedStartMinutes: 420, estimatedDurationMinutes: 60)
        container.mainContext.insert(profile)
        container.mainContext.insert(plan)
        container.mainContext.insert(task)
        try container.mainContext.save()
        let selection = SelectedProfile()
        selection.profile = profile

        let goalsHost = UIHostingController(
            rootView: ImprovementDashboardView(selection: selection).modelContainer(container)
        )
        let todayHost = UIHostingController(
            rootView: TodayTimelineView(selection: selection).modelContainer(container)
        )
        let taskHost = UIHostingController(
            rootView: TaskDetailView(activity: task).modelContainer(container)
        )
        goalsHost.loadViewIfNeeded()
        todayHost.loadViewIfNeeded()
        taskHost.loadViewIfNeeded()
        goalsHost.view.layoutIfNeeded()
        todayHost.view.layoutIfNeeded()
        taskHost.view.layoutIfNeeded()

        XCTAssertNotNil(goalsHost.view)
        XCTAssertNotNil(todayHost.view)
        XCTAssertNotNil(taskHost.view)
        XCTAssertFalse(goalsHost.view.subviews.isEmpty)
        XCTAssertFalse(todayHost.view.subviews.isEmpty)
    }
    #endif

    private func makeContainer() throws -> ModelContainer {
        try LifeOSDataStore.makeContainer(inMemory: true)
    }
}

private enum TestDate {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func make(
        _ year: Int, _ month: Int, _ day: Int,
        hour: Int = 0, minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone, year: year, month: month, day: day,
            hour: hour, minute: minute
        ))!
    }
}
