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
            weightEntries: [], sportEntries: [], savedTemplates: [],
            nutritionGoals: [], mealTemplates: [], mealEntries: [], waterEntries: [],
            bodyMetricDefinitions: [], bodyMetricEntries: []
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

    // MARK: - Body metric delete consistency (Nutrition fix pass §4c/4d)

    /// Create 80.0 / 79.0 / 78.5 (in that chronological order), delete 78.5, and
    /// verify every reader of this data — latest-entry lookup (what the Today
    /// tile and Body Tracking's hero both call), trend/history, and a Goal
    /// linked via linkedBodyMetricDefinitionID — agrees the current value is
    /// 79.0 and that 78.5 is gone everywhere, not just from one query.
    func testDeletingABodyMetricEntryUpdatesLatestHistoryAndLinkedGoalEverywhere() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = Profile(name: "Tester", kind: .individual, colorToken: "blue")
        context.insert(profile)

        let definition = BodyMetricDefinition(profileID: profile.id, name: "Weight", unit: "kg", isSystemDefault: true, sortOrder: 0)
        let repository = SwiftDataBodyTrackingRepository(context: context)
        repository.insertDefinition(definition)

        let day1 = TestDate.make(2026, 3, 1)
        let day2 = TestDate.make(2026, 3, 2)
        let day3 = TestDate.make(2026, 3, 3)
        let entry80 = BodyMetricEntry(profileID: profile.id, bodyMetricDefinition: definition, nameSnapshot: "Weight", unitSnapshot: "kg", value: 80.0, recordedAt: day1)
        let entry79 = BodyMetricEntry(profileID: profile.id, bodyMetricDefinition: definition, nameSnapshot: "Weight", unitSnapshot: "kg", value: 79.0, recordedAt: day2)
        let entry785 = BodyMetricEntry(profileID: profile.id, bodyMetricDefinition: definition, nameSnapshot: "Weight", unitSnapshot: "kg", value: 78.5, recordedAt: day3)
        repository.insertEntry(entry80)
        repository.insertEntry(entry79)
        repository.insertEntry(entry785)

        // A Goal whose primary Result Measure reads this Weight metric directly
        // (the same linkedBodyMetricDefinitionID mechanism CategoryProgressEngine
        // uses for "Your Goals" cards) — achieved only once the value is <= 78.9.
        let goal = Goal(profile: profile, name: "Reach race weight")
        let measure = ResultMeasure(
            goal: goal, name: "Body weight", role: .primary, unit: "kg",
            direction: .decrease, baselineValue: 80, targetValue: 78.9,
            linkedBodyMetricDefinitionID: definition.id
        )
        context.insert(goal)
        context.insert(measure)
        XCTAssertTrue(repository.save())

        let interval = DateInterval(start: day1, end: TestDate.make(2026, 3, 4))

        // Before deletion: 78.5 is latest, and it satisfies the linked Goal's target.
        let entriesBefore = try context.fetch(FetchDescriptor<BodyMetricEntry>())
        XCTAssertEqual(BodyTrackingEngine.latestEntry(definitionID: definition.id, entries: entriesBefore, on: day3)?.value, 78.5)
        XCTAssertEqual(BodyTrackingEngine.trend(definitionID: definition.id, entries: entriesBefore, interval: interval), -1.5)
        let progressBefore = GoalProgressEngine.progress(
            goal: goal, period: .month, now: day3, categories: [], contributions: [],
            measures: [measure], entries: [], activities: [], calendarItems: [],
            bodyMetricEntries: entriesBefore
        )
        XCTAssertEqual(progressBefore.status, .achieved, "78.5 <= 78.9 target must read as achieved before deletion")

        // Delete 78.5 through the same repository the UI uses.
        repository.deleteEntry(entry785)
        XCTAssertTrue(repository.save())

        // After deletion: re-fetch from the store (not the stale in-memory array)
        // so this proves the persisted data, not just object-graph state.
        let entriesAfter = try context.fetch(FetchDescriptor<BodyMetricEntry>())
        XCTAssertEqual(entriesAfter.count, 2)
        XCTAssertEqual(Set(entriesAfter.map(\.value)), Set([80.0, 79.0]), "78.5 must be gone from history everywhere, not just the latest lookup")

        let latestAfter = BodyTrackingEngine.latestEntry(definitionID: definition.id, entries: entriesAfter, on: day3)
        XCTAssertEqual(latestAfter?.value, 79.0, "Today Body Weight / hero value must fall back to 79.0")

        XCTAssertEqual(BodyTrackingEngine.trend(definitionID: definition.id, entries: entriesAfter, interval: interval), -1.0)

        let progressAfter = GoalProgressEngine.progress(
            goal: goal, period: .month, now: day3, categories: [], contributions: [],
            measures: [measure], entries: [], activities: [], calendarItems: [],
            bodyMetricEntries: entriesAfter
        )
        // 79.0 no longer satisfies the 78.9 target (so no longer .achieved), but
        // it's still moving in the right direction from the 80 baseline, so the
        // engine correctly reports .onTrack rather than .achieved — proving the
        // status genuinely recomputed from 79.0, not left over from 78.5.
        XCTAssertEqual(progressAfter.status, .onTrack, "must recompute from 79.0, not remain achieved from the deleted 78.5 entry")
    }

    // MARK: - Backup/restore determinism (Nutrition fix pass §1)

    /// The strongest correctness claim for backups: export realistic Nutrition
    /// + Body Tracking + linked-Goal data, restore it into a brand-new empty
    /// ModelContainer, and prove every derived report value (daily totals,
    /// target progress, consistency days, latest weight, trend, and linked
    /// Goal status) is bit-for-bit identical before and after — not just that
    /// the raw record counts match.
    func testBackupRestoreIntoEmptyContainerReproducesEveryDerivedNutritionAndBodyValue() throws {
        let source = try makeContainer()
        let sourceContext = source.mainContext
        let profile = Profile(name: "Vihaan", kind: .individual, colorToken: "blue")
        sourceContext.insert(profile)

        let day = TestDate.make(2026, 4, 10)
        let dayBefore = TestDate.make(2026, 4, 9)

        let nutritionGoal = NutritionGoal(
            profileID: profile.id, calorieTarget: 2_200, proteinTargetG: 150,
            carbsTargetG: 250, fatTargetG: 70, waterTargetML: 2_500
        )

        let breakfastTemplate = MealTemplate(
            profileID: profile.id, name: "Protein Breakfast", mealTypeDefault: .breakfast,
            details: "Eggs + oats", totals: NutritionValue(calories: 500, proteinG: 40, carbsG: 30, fatG: 15)
        )
        let lunchTemplate = MealTemplate(
            profileID: profile.id, name: "Quick Lunch", mealTypeDefault: .lunch,
            details: "Chicken + rice", totals: NutritionValue(calories: 650, proteinG: 35, carbsG: 60, fatG: 20)
        )

        let breakfast = MealEntry(
            profileID: profile.id, mealType: .breakfast, recordedAt: TestDate.make(2026, 4, 10, hour: 8),
            sourceTemplateID: breakfastTemplate.id, sourceTemplateNameSnapshot: breakfastTemplate.name,
            details: breakfastTemplate.details
        )
        breakfast.setTotals(breakfastTemplate.totals)
        let lunch = MealEntry(profileID: profile.id, mealType: .lunch, recordedAt: TestDate.make(2026, 4, 10, hour: 13), details: "Leftovers")
        lunch.setTotals(NutritionValue(calories: 600, proteinG: 42, carbsG: 55, fatG: 18))
        let dinner = MealEntry(profileID: profile.id, mealType: .dinner, recordedAt: TestDate.make(2026, 4, 10, hour: 19), details: "Salmon + rice")
        dinner.setTotals(NutritionValue(calories: 700, proteinG: 45, carbsG: 65, fatG: 22))

        let water1 = WaterEntry(profileID: profile.id, recordedAt: TestDate.make(2026, 4, 10, hour: 9), amountML: 500)
        let water2 = WaterEntry(profileID: profile.id, recordedAt: TestDate.make(2026, 4, 10, hour: 15), amountML: 750)

        let weightDefinition = BodyMetricDefinition(profileID: profile.id, name: "Weight", unit: "kg", isSystemDefault: true, sortOrder: 0)
        let weightYesterday = BodyMetricEntry(profileID: profile.id, bodyMetricDefinition: weightDefinition, nameSnapshot: "Weight", unitSnapshot: "kg", value: 80.0, recordedAt: dayBefore)
        let weightToday = BodyMetricEntry(profileID: profile.id, bodyMetricDefinition: weightDefinition, nameSnapshot: "Weight", unitSnapshot: "kg", value: 79.0, recordedAt: day)

        let goal = Goal(profile: profile, name: "Reach race weight")
        let measure = ResultMeasure(
            goal: goal, name: "Body weight", role: .primary, unit: "kg",
            direction: .decrease, baselineValue: 82, targetValue: 78,
            linkedBodyMetricDefinitionID: weightDefinition.id
        )

        sourceContext.insert(nutritionGoal)
        sourceContext.insert(breakfastTemplate)
        sourceContext.insert(lunchTemplate)
        sourceContext.insert(breakfast)
        sourceContext.insert(lunch)
        sourceContext.insert(dinner)
        sourceContext.insert(water1)
        sourceContext.insert(water2)
        sourceContext.insert(weightDefinition)
        sourceContext.insert(weightYesterday)
        sourceContext.insert(weightToday)
        sourceContext.insert(goal)
        sourceContext.insert(measure)
        try sourceContext.save()

        let meals = [breakfast, lunch, dinner]
        let waterEntries = [water1, water2]
        let bodyEntries = [weightYesterday, weightToday]
        let interval = DateInterval(start: dayBefore, end: TestDate.make(2026, 4, 11))

        func derivedValues(profileID: UUID, meals: [MealEntry], water: [WaterEntry], goal nGoal: NutritionGoal?, weightDefID: UUID, bodyEntries: [BodyMetricEntry], goal2: Goal, measure2: ResultMeasure) -> [String: Double] {
            let totals = NutritionEngine.dailyTotals(profileID: profileID, date: day, meals: meals, waterEntries: water)
            let progress = NutritionEngine.targetProgress(profileID: profileID, date: day, meals: meals, waterEntries: water, goal: nGoal)
            let consistency = NutritionEngine.consistencyDays(profileID: profileID, interval: interval, metric: .protein, meals: meals, waterEntries: water, goal: nGoal)
            let latest = BodyTrackingEngine.latestEntry(definitionID: weightDefID, entries: bodyEntries, on: day)
            let trend = BodyTrackingEngine.trend(definitionID: weightDefID, entries: bodyEntries, interval: interval)
            let goalProgress = GoalProgressEngine.progress(
                goal: goal2, period: .month, now: day, categories: [], contributions: [],
                measures: [measure2], entries: [], activities: [], calendarItems: [],
                bodyMetricEntries: bodyEntries
            )
            return [
                "calories": totals.calories, "protein": totals.proteinG,
                "carbs": totals.carbsG, "fat": totals.fatG, "water": totals.waterML,
                "calorieFraction": progress.calorieFraction ?? -1, "proteinFraction": progress.proteinFraction ?? -1,
                "consistencyAchieved": Double(consistency?.achieved ?? -1), "consistencyTotalDays": Double(consistency?.totalDays ?? -1),
                "latestWeight": latest?.value ?? -1, "trend": trend ?? .nan,
                "goalAchieved": goalProgress.status == .achieved ? 1 : 0,
            ]
        }

        let before = derivedValues(
            profileID: profile.id, meals: meals, water: waterEntries, goal: nutritionGoal,
            weightDefID: weightDefinition.id, bodyEntries: bodyEntries, goal2: goal, measure2: measure
        )

        let payload = LifeOSBackupService.make(
            profiles: [profile], categories: [], activities: [], goals: [goal],
            goalContributions: [], resultMeasures: [measure], resultEntries: [],
            calendarItems: [], sessions: [], foodEntries: [], weightEntries: [],
            sportEntries: [], savedTemplates: [],
            nutritionGoals: [nutritionGoal], mealTemplates: [breakfastTemplate, lunchTemplate],
            mealEntries: meals, waterEntries: waterEntries,
            bodyMetricDefinitions: [weightDefinition], bodyMetricEntries: bodyEntries
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(payload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LifeOSBackupPayload.self, from: encoded)

        let destination = try makeContainer()
        try LifeOSBackupService.restore(decoded, into: destination.mainContext)
        let destinationContext = destination.mainContext

        // Source records equivalent — counts and identity, not just totals.
        let restoredProfiles = try destinationContext.fetch(FetchDescriptor<Profile>())
        let restoredNutritionGoals = try destinationContext.fetch(FetchDescriptor<NutritionGoal>())
        let restoredMealTemplates = try destinationContext.fetch(FetchDescriptor<MealTemplate>())
        let restoredMeals = try destinationContext.fetch(FetchDescriptor<MealEntry>())
        let restoredWater = try destinationContext.fetch(FetchDescriptor<WaterEntry>())
        let restoredDefinitions = try destinationContext.fetch(FetchDescriptor<BodyMetricDefinition>())
        let restoredEntries = try destinationContext.fetch(FetchDescriptor<BodyMetricEntry>())
        let restoredGoals = try destinationContext.fetch(FetchDescriptor<Goal>())
        let restoredMeasures = try destinationContext.fetch(FetchDescriptor<ResultMeasure>())

        XCTAssertEqual(restoredProfiles.map(\.id), [profile.id])
        XCTAssertEqual(restoredNutritionGoals.count, 1)
        XCTAssertEqual(restoredMealTemplates.count, 2)
        XCTAssertEqual(restoredMeals.count, 3)
        XCTAssertEqual(Set(restoredMeals.map(\.totals.calories)), Set(meals.map(\.totals.calories)))
        XCTAssertEqual(restoredWater.count, 2)
        XCTAssertEqual(restoredWater.reduce(0) { $0 + $1.amountML }, waterEntries.reduce(0) { $0 + $1.amountML })
        XCTAssertEqual(restoredDefinitions.count, 1)
        XCTAssertEqual(restoredEntries.count, 2)
        XCTAssertEqual(Set(restoredEntries.map(\.value)), Set([80.0, 79.0]))
        XCTAssertEqual(restoredGoals.count, 1)
        XCTAssertEqual(restoredMeasures.count, 1)
        XCTAssertEqual(restoredMeasures.first?.linkedBodyMetricDefinitionID, weightDefinition.id, "the Goal<->Weight link must survive backup/restore, not just the raw entries")

        let restoredGoal = try XCTUnwrap(restoredGoals.first)
        let restoredMeasure = try XCTUnwrap(restoredMeasures.first)
        let restoredNutritionGoal = restoredNutritionGoals.first
        let restoredDefinitionID = try XCTUnwrap(restoredDefinitions.first?.id)

        let after = derivedValues(
            profileID: profile.id, meals: restoredMeals, water: restoredWater, goal: restoredNutritionGoal,
            weightDefID: restoredDefinitionID, bodyEntries: restoredEntries, goal2: restoredGoal, measure2: restoredMeasure
        )

        XCTAssertEqual(before, after, "every derived Nutrition/Body report value must be identical before and after a backup round trip")
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

    // MARK: - Profile isolation audit (STOP-feature-development integrity pass)
    //
    // Every test below creates TWO profiles (Alice/Bob) with intentionally
    // IDENTICAL names for their Areas/Activities/Tasks/Measurements/
    // Templates/Definitions, to catch any code path that resolves ownership
    // by name instead of by profileID/relationship-to-an-already-scoped-
    // object. Every assertion checks both halves: the acting profile's data
    // changed as expected, AND the other profile's identically-named data
    // did not change at all.

    func testIdenticalNamedAreasAndActivitiesAreIsolatedByProfileIDNotName() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let alice = Profile(name: "Alice", kind: .individual, colorToken: "blue")
        let bob = Profile(name: "Bob", kind: .individual, colorToken: "orange")
        context.insert(alice); context.insert(bob)

        let aliceSports = AppCategory(profile: alice, name: "Sports", symbol: "figure.run", colorToken: "blue", pillar: .sport, trackingKind: .sport)
        let alicelearning = AppCategory(profile: alice, name: "Learning", symbol: "book", colorToken: "green", pillar: .learning)
        let bobSports = AppCategory(profile: bob, name: "Sports", symbol: "figure.run", colorToken: "orange", pillar: .sport, trackingKind: .sport)
        context.insert(aliceSports); context.insert(alicelearning); context.insert(bobSports)

        let aliceActivity = Activity(profile: alice, category: aliceSports, name: "Practice", plannedStartMinutes: 420, estimatedDurationMinutes: 30, startDate: TestDate.make(2026, 5, 1))
        let bobActivity = Activity(profile: bob, category: bobSports, name: "Practice", plannedStartMinutes: 420, estimatedDurationMinutes: 30, startDate: TestDate.make(2026, 5, 1))
        context.insert(aliceActivity); context.insert(bobActivity)
        try context.save()

        // A same-name "Sports" category must never resolve to the other profile's row.
        XCTAssertNotEqual(aliceSports.id, bobSports.id)
        let allCategories = try context.fetch(FetchDescriptor<AppCategory>())
        let sportsNamedRows = allCategories.filter { $0.name == "Sports" }
        XCTAssertEqual(sportsNamedRows.count, 2, "both profiles' identically-named Sports category must persist as two distinct rows")
        XCTAssertEqual(Set(sportsNamedRows.map { $0.profile?.id }), Set([alice.id, bob.id]))

        // Editing Alice's Sports category must never rename Bob's.
        aliceSports.name = "Baseball"
        try context.save()
        XCTAssertEqual(bobSports.name, "Sports", "editing Alice's category must not rename Bob's identically-named category")

        // Deleting Alice's Sports category must never delete Bob's.
        context.delete(aliceSports)
        try context.save()
        let remainingCategories = try context.fetch(FetchDescriptor<AppCategory>())
        XCTAssertTrue(remainingCategories.contains { $0.id == bobSports.id }, "deleting Alice's category must not delete Bob's identically-named category")
        XCTAssertFalse(remainingCategories.contains { $0.id == aliceSports.id })

        // Alice's Activity must never resolve to Bob's identically-named Activity.
        let allActivities = try context.fetch(FetchDescriptor<Activity>())
        let practiceRows = allActivities.filter { $0.name == "Practice" }
        XCTAssertEqual(practiceRows.count, 2)
        XCTAssertEqual(Set(practiceRows.map { $0.profile?.id }), Set([alice.id, bob.id]))
    }

    func testIdenticalNamedGoalsUseOnlyTheirOwnProfilesEvidence() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let alice = Profile(name: "Alice", kind: .individual, colorToken: "blue")
        let bob = Profile(name: "Bob", kind: .individual, colorToken: "orange")
        context.insert(alice); context.insert(bob)

        // Same title, different targets — the exact "similar-looking data" trap.
        let aliceGoal = Goal(profile: alice, name: "Practice Baseball")
        let bobGoal = Goal(profile: bob, name: "Practice Baseball")
        let aliceMeasure = ResultMeasure(goal: aliceGoal, name: "Sessions", role: .primary, valueType: .number, unit: "sessions", direction: .increase, baselineValue: 0, targetValue: 3)
        let bobMeasure = ResultMeasure(goal: bobGoal, name: "Sessions", role: .primary, valueType: .number, unit: "sessions", direction: .increase, baselineValue: 0, targetValue: 5)
        context.insert(aliceGoal); context.insert(bobGoal)
        context.insert(aliceMeasure); context.insert(bobMeasure)

        // Manual check-ins — Bob logs a much higher value than Alice.
        let aliceEntry = ResultEntry(profile: alice, measure: aliceMeasure, date: TestDate.make(2026, 5, 5), numericValue: 2)
        let bobEntry = ResultEntry(profile: bob, measure: bobMeasure, date: TestDate.make(2026, 5, 5), numericValue: 9)
        context.insert(aliceEntry); context.insert(bobEntry)
        try context.save()

        let progressAlice = GoalProgressEngine.progress(
            goal: aliceGoal, period: .month, now: TestDate.make(2026, 5, 6), categories: [], contributions: [],
            measures: [aliceMeasure, bobMeasure], entries: [aliceEntry, bobEntry], activities: [], calendarItems: []
        )
        let progressBob = GoalProgressEngine.progress(
            goal: bobGoal, period: .month, now: TestDate.make(2026, 5, 6), categories: [], contributions: [],
            measures: [aliceMeasure, bobMeasure], entries: [aliceEntry, bobEntry], activities: [], calendarItems: []
        )

        XCTAssertEqual(progressAlice.latestEntry?.numericValue, 2, "Alice's Goal must read only Alice's ResultEntry even though both engine calls were given both profiles' measures/entries")
        XCTAssertEqual(progressBob.latestEntry?.numericValue, 9, "Bob's Goal must read only Bob's ResultEntry")
        XCTAssertNotEqual(progressAlice.latestEntry?.id, progressBob.latestEntry?.id)

        // A measurement-linked Goal source must also stay confined to its own profile.
        let aliceActivity = Activity(profile: alice, category: nil, name: "Fielding", plannedStartMinutes: 0, estimatedDurationMinutes: 10, startDate: TestDate.make(2026, 5, 1))
        let bobActivity = Activity(profile: bob, category: nil, name: "Fielding", plannedStartMinutes: 0, estimatedDurationMinutes: 10, startDate: TestDate.make(2026, 5, 1))
        context.insert(aliceActivity); context.insert(bobActivity)
        let aliceDefinition = MeasurementDefinition(activity: aliceActivity, name: "Ground Balls", type: .count)
        let bobDefinition = MeasurementDefinition(activity: bobActivity, name: "Ground Balls", type: .count)
        context.insert(aliceDefinition); context.insert(bobDefinition)
        aliceGoal.createdAt = TestDate.make(2026, 5, 1)
        let aliceLinkedMeasure = ResultMeasure(goal: aliceGoal, name: "Ground Balls total", role: .supporting, direction: .increase, baselineValue: 0, targetValue: 100, linkedMeasurementDefinitionID: aliceDefinition.id)
        context.insert(aliceLinkedMeasure)
        let aliceSession = ActivitySession(activity: aliceActivity, calendarItem: nil, date: TestDate.make(2026, 5, 5))
        let bobSession = ActivitySession(activity: bobActivity, calendarItem: nil, date: TestDate.make(2026, 5, 5))
        context.insert(aliceSession); context.insert(bobSession)
        let aliceMeasurementEntry = MeasurementEntry(activitySession: aliceSession, measurementDefinition: aliceDefinition, nameSnapshot: "Ground Balls", typeSnapshot: .count, numericValue: 100, recordedAt: TestDate.make(2026, 5, 5))
        let bobMeasurementEntry = MeasurementEntry(activitySession: bobSession, measurementDefinition: bobDefinition, nameSnapshot: "Ground Balls", typeSnapshot: .count, numericValue: 200, recordedAt: TestDate.make(2026, 5, 5))
        context.insert(aliceMeasurementEntry); context.insert(bobMeasurementEntry)
        try context.save()

        let linkedProgress = GoalProgressEngine.progress(
            goal: aliceGoal, period: .month, now: TestDate.make(2026, 5, 6), categories: [], contributions: [],
            measures: [aliceLinkedMeasure], entries: [],
            activities: [aliceActivity, bobActivity], calendarItems: [],
            measurementDefinitions: [aliceDefinition, bobDefinition],
            measurementEntries: [aliceMeasurementEntry, bobMeasurementEntry]
        )
        XCTAssertEqual(linkedProgress.status, .achieved, "Alice's own 100 ground balls must satisfy her 100-target Goal")
        // Prove it isn't silently summing Bob's 200 in too (300 would still exceed target, so
        // this must be checked via the raw engine total, not just the achieved boolean).
        let aliceOnlyTotal = ProgressEngine.measurementTotal(for: aliceDefinition, entries: [aliceMeasurementEntry, bobMeasurementEntry])
        XCTAssertEqual(aliceOnlyTotal, 100, "measurementTotal for Alice's definition must never include Bob's identically-named definition's entries")
    }

    func testCompletingIdenticalNamedTaskOnlyAffectsTheOwningProfileEverywhere() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let alice = Profile(name: "Alice", kind: .individual, colorToken: "blue")
        let bob = Profile(name: "Bob", kind: .individual, colorToken: "orange")
        context.insert(alice); context.insert(bob)
        let today = TestDate.make(2026, 6, 1)

        let aliceCategory = AppCategory(profile: alice, name: "Baseball", symbol: "figure.baseball", colorToken: "blue", pillar: .sport, trackingKind: .sport)
        let bobCategory = AppCategory(profile: bob, name: "Baseball", symbol: "figure.baseball", colorToken: "orange", pillar: .sport, trackingKind: .sport)
        context.insert(aliceCategory); context.insert(bobCategory)
        let aliceActivity = Activity(profile: alice, category: aliceCategory, name: "Hitting Practice", repeatType: .daily, weekdays: Array(1...7), plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 30, startDate: today)
        let bobActivity = Activity(profile: bob, category: bobCategory, name: "Hitting Practice", repeatType: .daily, weekdays: Array(1...7), plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 30, startDate: today)
        context.insert(aliceActivity); context.insert(bobActivity)
        try context.save()

        try PlanningService.insertMissingCalendarItems(profile: alice, date: today, activities: [aliceActivity, bobActivity], context: context, calendar: TestDate.calendar)
        try PlanningService.insertMissingCalendarItems(profile: bob, date: today, activities: [aliceActivity, bobActivity], context: context, calendar: TestDate.calendar)
        try context.save()

        let allItems = try context.fetch(FetchDescriptor<CalendarItem>())
        let aliceItem = try XCTUnwrap(allItems.first { $0.profile?.id == alice.id })
        let bobItem = try XCTUnwrap(allItems.first { $0.profile?.id == bob.id })
        XCTAssertNotEqual(aliceItem.id, bobItem.id)
        XCTAssertEqual(aliceItem.activity?.name, bobItem.activity?.name, "same-titled task on both profiles, by design, to stress-test isolation")

        let repository = SwiftDataCalendarRepository(context: context)
        let viewModel = TodayViewModel(profile: alice, items: allItems, activities: [aliceActivity, bobActivity], resultMeasures: [], currentTime: today, repository: repository)

        // Duplicate-completion (scenario 6): tap twice, expect exactly one session.
        XCTAssertTrue(viewModel.quickFinish(aliceItem, at: TestDate.make(2026, 6, 1, hour: 18, minute: 30)))
        XCTAssertFalse(viewModel.quickFinish(aliceItem, at: TestDate.make(2026, 6, 1, hour: 18, minute: 31)), "quickFinish must be idempotent once done")

        XCTAssertEqual(aliceItem.status, .done)
        XCTAssertEqual(bobItem.status, .planned, "Bob's identically-named/timed task must remain untouched")

        let sessions = try context.fetch(FetchDescriptor<ActivitySession>())
        XCTAssertEqual(sessions.filter { $0.activity?.id == aliceActivity.id }.count, 1, "exactly one session, no duplicates from the double tap")
        XCTAssertEqual(sessions.filter { $0.activity?.id == bobActivity.id }.count, 0, "Bob's session count must remain unchanged")

        // Derived progress must reflect only Alice.
        let aliceViewModelAfter = TodayViewModel(profile: alice, items: allItems, activities: [aliceActivity, bobActivity], resultMeasures: [], currentTime: today, repository: repository)
        let bobViewModelAfter = TodayViewModel(profile: bob, items: allItems, activities: [aliceActivity, bobActivity], resultMeasures: [], currentTime: today, repository: repository)
        XCTAssertEqual(aliceViewModelAfter.summary.done, 1)
        XCTAssertEqual(bobViewModelAfter.summary.done, 0, "Bob's Today completion count must not increment from Alice's completion")

        // Skip + undoSkip (scenario 8) on a second occurrence proves per-item, not per-title, resolution.
        let tomorrow = try XCTUnwrap(TestDate.calendar.date(byAdding: .day, value: 1, to: today))
        try PlanningService.insertMissingCalendarItems(profile: alice, date: tomorrow, activities: [aliceActivity, bobActivity], context: context, calendar: TestDate.calendar)
        try PlanningService.insertMissingCalendarItems(profile: bob, date: tomorrow, activities: [aliceActivity, bobActivity], context: context, calendar: TestDate.calendar)
        try context.save()
        let nextDayItems = try context.fetch(FetchDescriptor<CalendarItem>()).filter { TestDate.calendar.isDate($0.date, inSameDayAs: tomorrow) }
        let aliceNextItem = try XCTUnwrap(nextDayItems.first { $0.profile?.id == alice.id })
        let bobNextItem = try XCTUnwrap(nextDayItems.first { $0.profile?.id == bob.id })

        let aliceTomorrowVM = TodayViewModel(profile: alice, items: nextDayItems, activities: [aliceActivity, bobActivity], resultMeasures: [], currentTime: tomorrow, repository: repository)
        aliceTomorrowVM.skip(aliceNextItem)
        XCTAssertEqual(aliceNextItem.status, .skipped)
        XCTAssertEqual(bobNextItem.status, .planned, "skipping Alice's occurrence must never skip Bob's identically-scheduled occurrence")
        aliceTomorrowVM.undoSkip(aliceNextItem)
        XCTAssertEqual(aliceNextItem.status, .planned, "undoSkip must restore Alice's own item")
        XCTAssertEqual(bobNextItem.status, .planned, "Bob remains unaffected by Alice's skip/undo cycle")
    }

    func testNutritionAndBodyTrackingIsolationWithIdenticalTargetsAndDefinitionNames() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let alice = Profile(name: "Alice", kind: .individual, colorToken: "blue")
        let bob = Profile(name: "Bob", kind: .individual, colorToken: "orange")
        context.insert(alice); context.insert(bob)

        let aliceGoal = NutritionGoal(profileID: alice.id, proteinTargetG: 220)
        let bobGoal = NutritionGoal(profileID: bob.id, proteinTargetG: 100)
        context.insert(aliceGoal); context.insert(bobGoal)

        let day = TestDate.make(2026, 7, 1)
        let aliceMeal = MealEntry(profileID: alice.id, mealType: .lunch, recordedAt: day, details: "Chicken")
        aliceMeal.setTotals(NutritionValue(calories: 500, proteinG: 70, carbsG: 40, fatG: 15))
        let bobMeal = MealEntry(profileID: bob.id, mealType: .lunch, recordedAt: day, details: "Chicken")
        bobMeal.setTotals(NutritionValue(calories: 300, proteinG: 40, carbsG: 20, fatG: 10))
        context.insert(aliceMeal); context.insert(bobMeal)
        try context.save()

        let allMeals = try context.fetch(FetchDescriptor<MealEntry>())
        let aliceProgress = NutritionEngine.targetProgress(profileID: alice.id, date: day, meals: allMeals, waterEntries: [], goal: aliceGoal)
        let bobProgress = NutritionEngine.targetProgress(profileID: bob.id, date: day, meals: allMeals, waterEntries: [], goal: bobGoal)
        XCTAssertEqual(aliceProgress.totals.proteinG, 70, "Alice's dashboard must read 70, not 70+40=110")
        XCTAssertEqual(bobProgress.totals.proteinG, 40)
        XCTAssertEqual(aliceProgress.proteinTarget, 220)
        XCTAssertEqual(bobProgress.proteinTarget, 100)

        // Same-named "Weight" BodyMetricDefinition per profile.
        let aliceWeightDef = BodyMetricDefinition(profileID: alice.id, name: "Weight", unit: "kg", isSystemDefault: true)
        let bobWeightDef = BodyMetricDefinition(profileID: bob.id, name: "Weight", unit: "kg", isSystemDefault: true)
        context.insert(aliceWeightDef); context.insert(bobWeightDef)
        let aliceEntry = BodyMetricEntry(profileID: alice.id, bodyMetricDefinition: aliceWeightDef, nameSnapshot: "Weight", unitSnapshot: "kg", value: 78.5, recordedAt: day)
        let bobEntry = BodyMetricEntry(profileID: bob.id, bodyMetricDefinition: bobWeightDef, nameSnapshot: "Weight", unitSnapshot: "kg", value: 92, recordedAt: day)
        context.insert(aliceEntry); context.insert(bobEntry)
        try context.save()

        let allBodyEntries = try context.fetch(FetchDescriptor<BodyMetricEntry>())
        // A "Weight" definition lookup by NAME ALONE (not ID) would wrongly
        // match either profile's row — this proves the definition itself,
        // not just the entry, is what must be profile-scoped before lookup.
        let aliceLatest = BodyTrackingEngine.latestEntry(definitionID: aliceWeightDef.id, entries: allBodyEntries, on: day)
        let bobLatest = BodyTrackingEngine.latestEntry(definitionID: bobWeightDef.id, entries: allBodyEntries, on: day)
        XCTAssertEqual(aliceLatest?.value, 78.5)
        XCTAssertEqual(bobLatest?.value, 92)

        // Edit/delete isolation (scenario 19): deleting Alice's meal/body entry
        // must never touch Bob's identically-shaped row.
        context.delete(aliceMeal)
        context.delete(aliceEntry)
        try context.save()
        let remainingMeals = try context.fetch(FetchDescriptor<MealEntry>())
        let remainingBodyEntries = try context.fetch(FetchDescriptor<BodyMetricEntry>())
        XCTAssertEqual(remainingMeals.map(\.profileID), [bob.id])
        XCTAssertEqual(remainingBodyEntries.map(\.profileID), [bob.id])
        XCTAssertEqual(remainingBodyEntries.first?.value, 92, "Bob's Weight entry must be untouched by deleting Alice's identically-named-definition entry")
    }

    func testTwoProfileBackupRestorePreservesOwnershipAndReportsMatchAfterRestore() throws {
        let source = try makeContainer()
        let sourceContext = source.mainContext
        let alice = Profile(name: "Alice", kind: .individual, colorToken: "blue")
        let bob = Profile(name: "Bob", kind: .individual, colorToken: "orange")
        sourceContext.insert(alice); sourceContext.insert(bob)

        let day = TestDate.make(2026, 8, 1)
        let aliceGoal = NutritionGoal(profileID: alice.id, proteinTargetG: 220)
        let bobGoal = NutritionGoal(profileID: bob.id, proteinTargetG: 100)
        let aliceMeal = MealEntry(profileID: alice.id, mealType: .lunch, recordedAt: day, details: "Chicken")
        aliceMeal.setTotals(NutritionValue(calories: 500, proteinG: 70, carbsG: 40, fatG: 15))
        let bobMeal = MealEntry(profileID: bob.id, mealType: .lunch, recordedAt: day, details: "Chicken")
        bobMeal.setTotals(NutritionValue(calories: 300, proteinG: 40, carbsG: 20, fatG: 10))
        let aliceWeightDef = BodyMetricDefinition(profileID: alice.id, name: "Weight", unit: "kg", isSystemDefault: true)
        let bobWeightDef = BodyMetricDefinition(profileID: bob.id, name: "Weight", unit: "kg", isSystemDefault: true)
        let aliceEntry = BodyMetricEntry(profileID: alice.id, bodyMetricDefinition: aliceWeightDef, nameSnapshot: "Weight", unitSnapshot: "kg", value: 78.5, recordedAt: day)
        let bobEntry = BodyMetricEntry(profileID: bob.id, bodyMetricDefinition: bobWeightDef, nameSnapshot: "Weight", unitSnapshot: "kg", value: 92, recordedAt: day)
        [aliceGoal, bobGoal].forEach(sourceContext.insert)
        [aliceMeal, bobMeal].forEach(sourceContext.insert)
        [aliceWeightDef, bobWeightDef].forEach(sourceContext.insert)
        [aliceEntry, bobEntry].forEach(sourceContext.insert)
        try sourceContext.save()

        let payload = LifeOSBackupService.make(
            profiles: [alice, bob], categories: [], activities: [], goals: [],
            goalContributions: [], resultMeasures: [], resultEntries: [],
            calendarItems: [], sessions: [], foodEntries: [], weightEntries: [],
            sportEntries: [], savedTemplates: [],
            nutritionGoals: [aliceGoal, bobGoal], mealTemplates: [],
            mealEntries: [aliceMeal, bobMeal], waterEntries: [],
            bodyMetricDefinitions: [aliceWeightDef, bobWeightDef], bodyMetricEntries: [aliceEntry, bobEntry]
        )
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(payload)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LifeOSBackupPayload.self, from: encoded)

        let destination = try makeContainer()
        try LifeOSBackupService.restore(decoded, into: destination.mainContext)
        // Restoring the same backup twice must not duplicate records (scenario 21).
        try LifeOSBackupService.restore(decoded, into: destination.mainContext)
        let destinationContext = destination.mainContext

        let restoredProfiles = try destinationContext.fetch(FetchDescriptor<Profile>())
        XCTAssertEqual(Set(restoredProfiles.map(\.id)), Set([alice.id, bob.id]))

        let restoredMeals = try destinationContext.fetch(FetchDescriptor<MealEntry>())
        XCTAssertEqual(restoredMeals.count, 2, "restoring the same backup twice must not duplicate MealEntry rows")
        let restoredAliceMeal = try XCTUnwrap(restoredMeals.first { $0.profileID == alice.id })
        let restoredBobMeal = try XCTUnwrap(restoredMeals.first { $0.profileID == bob.id })
        XCTAssertEqual(restoredAliceMeal.totals.proteinG, 70, "Alice's restored meal must keep her own values, not Bob's")
        XCTAssertEqual(restoredBobMeal.totals.proteinG, 40)

        let restoredDefinitions = try destinationContext.fetch(FetchDescriptor<BodyMetricDefinition>())
        XCTAssertEqual(restoredDefinitions.count, 2, "two identically-named Weight definitions must restore as two distinct rows, not merge into one")
        let restoredEntries = try destinationContext.fetch(FetchDescriptor<BodyMetricEntry>())
        XCTAssertEqual(restoredEntries.count, 2)

        // Recompute reports from restored data and confirm no ownership crossed over.
        let restoredAliceGoal = try XCTUnwrap((try destinationContext.fetch(FetchDescriptor<NutritionGoal>())).first { $0.profileID == alice.id })
        let restoredBobGoal = try XCTUnwrap((try destinationContext.fetch(FetchDescriptor<NutritionGoal>())).first { $0.profileID == bob.id })
        let restoredAliceProgress = NutritionEngine.targetProgress(profileID: alice.id, date: day, meals: restoredMeals, waterEntries: [], goal: restoredAliceGoal)
        let restoredBobProgress = NutritionEngine.targetProgress(profileID: bob.id, date: day, meals: restoredMeals, waterEntries: [], goal: restoredBobGoal)
        XCTAssertEqual(restoredAliceProgress.totals.proteinG, 70)
        XCTAssertEqual(restoredBobProgress.totals.proteinG, 40)

        let restoredAliceDef = try XCTUnwrap(restoredDefinitions.first { $0.profileID == alice.id })
        let restoredBobDef = try XCTUnwrap(restoredDefinitions.first { $0.profileID == bob.id })
        XCTAssertEqual(BodyTrackingEngine.latestEntry(definitionID: restoredAliceDef.id, entries: restoredEntries, on: day)?.value, 78.5)
        XCTAssertEqual(BodyTrackingEngine.latestEntry(definitionID: restoredBobDef.id, entries: restoredEntries, on: day)?.value, 92)
    }

    // MARK: - End-to-end user journeys (cancel/skip/complete/update, and Nutrition save+reflect)

    /// Simulates a full single-user session against a real store: schedule →
    /// start → skip → undo the skip → complete → undo the completion
    /// (mirrors ImprovementCategoryDetailView.undoComplete) — checking after
    /// EVERY step that CalendarItem status, ActivitySession existence, Today
    /// completion count, and the linked Goal's progress all agree, and that
    /// no step ever leaves a duplicate or orphaned record behind.
    func testFullTaskLifecycleJourneyKeepsCalendarSessionTodayAndGoalProgressInSync() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = Profile(name: "Tester", kind: .individual, colorToken: "blue")
        let today = TestDate.make(2026, 9, 1)
        context.insert(profile)

        let category = AppCategory(profile: profile, name: "Baseball", symbol: "figure.baseball", colorToken: "orange", pillar: .sport, trackingKind: .sport)
        context.insert(category)
        let activity = Activity(
            profile: profile, category: category, name: "Hitting Practice",
            repeatType: .daily, weekdays: Array(1...7),
            plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 30, startDate: today
        )
        context.insert(activity)
        let goal = Goal(profile: profile, name: "Improve hitting")
        goal.createdAt = today
        let contribution = GoalAreaContribution(goal: goal, category: category, weeklyTargetSessions: 7, weeklyTargetMinutes: 210)
        context.insert(goal); context.insert(contribution)
        try context.save()

        try PlanningService.insertMissingCalendarItems(profile: profile, date: today, activities: [activity], context: context, calendar: TestDate.calendar)
        try context.save()

        let item = try XCTUnwrap(try context.fetch(FetchDescriptor<CalendarItem>()).first)
        let repository = SwiftDataCalendarRepository(context: context)
        let viewModel = TodayViewModel(profile: profile, items: [item], activities: [activity], resultMeasures: [], currentTime: today, repository: repository)

        func goalProgress() -> GoalProgress {
            GoalProgressEngine.progress(
                goal: goal, period: .week, now: today, categories: [category], contributions: [contribution],
                measures: [], entries: [], activities: [activity],
                calendarItems: try! context.fetch(FetchDescriptor<CalendarItem>())
            )
        }

        // Step 1: start.
        viewModel.start(item)
        XCTAssertEqual(item.status, .inProgress)
        XCTAssertEqual(viewModel.summary.done, 0)

        // Step 2: skip — no session, Goal sees zero completed actions.
        viewModel.skip(item)
        XCTAssertEqual(item.status, .skipped)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ActivitySession>()).isEmpty)
        XCTAssertEqual(goalProgress().contributions.first?.completedActions, 0)

        // Step 3: undo the skip — back to planned, still no session.
        viewModel.undoSkip(item)
        XCTAssertEqual(item.status, .planned)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ActivitySession>()).isEmpty)

        // Step 4: complete — exactly one session, Today +1, Goal sees it.
        XCTAssertTrue(viewModel.quickFinish(item, at: TestDate.make(2026, 9, 1, hour: 18, minute: 30)))
        XCTAssertEqual(item.status, .done)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ActivitySession>()).count, 1)
        XCTAssertEqual(viewModel.summary.done, 1)
        XCTAssertEqual(goalProgress().contributions.first?.completedActions, 1)

        // Step 5: undo the completion (ImprovementCategoryDetailView.undoComplete's
        // exact logic — by CalendarItem.id, never by activity name/time) — back to
        // planned, session removed, Today and Goal both revert to zero.
        let sessionsForItem = try context.fetch(FetchDescriptor<ActivitySession>()).filter { $0.calendarItem?.id == item.id }
        item.status = .planned
        item.actualStart = nil
        item.actualEnd = nil
        sessionsForItem.forEach(context.delete)
        try context.save()

        XCTAssertEqual(item.status, .planned)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ActivitySession>()).isEmpty, "undo must remove exactly the session it created, leaving none behind")
        let finalViewModel = TodayViewModel(profile: profile, items: [item], activities: [activity], resultMeasures: [], currentTime: today, repository: repository)
        XCTAssertEqual(finalViewModel.summary.done, 0)
        XCTAssertEqual(goalProgress().contributions.first?.completedActions, 0)
    }

    /// Simulates a full single-user Nutrition session: log a meal from a
    /// Template → confirm the Dashboard-level totals reflect it → edit the
    /// meal's totals → confirm the change is reflected immediately → delete
    /// the meal → confirm it drops back to zero. Every step recomputes
    /// NutritionEngine.dailyTotals/targetProgress fresh from the persisted
    /// store (not cached state), for the one profile throughout.
    func testNutritionLogEditDeleteJourneyIsReflectedInDashboardTotalsAtEveryStep() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = Profile(name: "Tester", kind: .individual, colorToken: "blue")
        context.insert(profile)
        let goal = NutritionGoal(profileID: profile.id, proteinTargetG: 150)
        context.insert(goal)
        let day = TestDate.make(2026, 9, 5)
        let repository = SwiftDataNutritionRepository(context: context)

        func totals() throws -> NutritionEngine.DailyTotals {
            let meals = try context.fetch(FetchDescriptor<MealEntry>())
            return NutritionEngine.dailyTotals(profileID: profile.id, date: day, meals: meals, waterEntries: [])
        }

        // Step 1: before logging anything, totals are zero.
        XCTAssertEqual(try totals().proteinG, 0)

        // Step 2: log from a Template — fixed totals copied verbatim (no scaling/calc).
        let template = MealTemplate(
            profileID: profile.id, name: "Protein Breakfast", mealTypeDefault: .breakfast,
            details: "Eggs + oats", totals: NutritionValue(calories: 500, proteinG: 40, carbsG: 30, fatG: 15)
        )
        repository.insertTemplate(template, foodEntries: [])
        let meal = MealEntry(
            profileID: profile.id, mealType: .breakfast, recordedAt: day,
            sourceTemplateID: template.id, sourceTemplateNameSnapshot: template.name, details: template.details
        )
        repository.insertMeal(meal, foodEntries: [])
        meal.setTotals(template.totals)
        XCTAssertTrue(repository.save())

        XCTAssertEqual(try totals().proteinG, 40, "logging from a template must be reflected immediately")
        XCTAssertEqual(try totals().calories, 500)

        // Step 3: edit the meal (AddEditMealView.saveMeal's exact path) —
        // change must be reflected immediately, not just on the next fetch cycle.
        meal.details = "Eggs + oats + extra protein shake"
        meal.setTotals(NutritionValue(calories: 650, proteinG: 60, carbsG: 35, fatG: 18))
        XCTAssertTrue(repository.save())

        XCTAssertEqual(try totals().proteinG, 60, "editing must be reflected immediately, not the stale 40")
        XCTAssertEqual(try totals().calories, 650)

        // Also verify target-progress framing recomputes with the edit.
        let progressAfterEdit = NutritionEngine.targetProgress(
            profileID: profile.id, date: day, meals: try context.fetch(FetchDescriptor<MealEntry>()),
            waterEntries: [], goal: goal
        )
        XCTAssertEqual(progressAfterEdit.proteinFraction ?? -1, 0.4, accuracy: 0.0001, "60/150 target")

        // Step 4: delete the meal (AddEditMealView.deleteMeal's exact path) —
        // totals must drop back to zero, not linger from the deleted row.
        try repository.deleteMeal(meal)
        XCTAssertTrue(repository.save())

        XCTAssertEqual(try totals().proteinG, 0, "deleting the meal must zero the total immediately")
        XCTAssertEqual(try totals().calories, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<MealEntry>()).isEmpty)
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
        // A hosting controller never attached to a window doesn't reliably
        // materialize its SwiftUI subview hierarchy on-demand from
        // loadViewIfNeeded()/layoutIfNeeded() alone on current SwiftUI/UIKit
        // — the window is what gives it a trait collection and rendering
        // pass. Attach each in turn so `subviews` below actually reflects
        // what SwiftUI built rather than an as-yet-unrendered empty view.
        let goalsWindow = attachedToKeyWindow(goalsHost)
        let todayWindow = attachedToKeyWindow(todayHost)
        let taskWindow = attachedToKeyWindow(taskHost)

        XCTAssertNotNil(goalsHost.view)
        XCTAssertNotNil(todayHost.view)
        XCTAssertNotNil(taskHost.view)
        XCTAssertFalse(goalsHost.view.subviews.isEmpty)
        XCTAssertFalse(todayHost.view.subviews.isEmpty)

        // Keep the windows alive until the assertions above have run.
        _ = (goalsWindow, todayWindow, taskWindow)
    }

    /// Attaches `host` as the root view controller of a new key window and
    /// forces layout, so SwiftUI actually builds its subview hierarchy.
    /// Returns the window — the caller must keep it alive for as long as it
    /// needs `host.view`'s hierarchy to remain populated.
    private func attachedToKeyWindow<V: View>(_ host: UIHostingController<V>) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 932))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return window
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
