import XCTest
import SwiftData
@testable import LifeOS

/// Phase 10: a single, deliberately broad audit sweep across every core
/// model family, complementing the many single-feature profile-isolation
/// tests already scattered through this suite (TaskOccurrenceActionsTests,
/// ProgressViewAlignmentTests, ScheduleNavigationTests, GoalSystemComponentTests,
/// ProgressAndHierarchyTests). Two profiles carry a fully parallel graph of
/// IDENTICALLY-named and identically-timed data across every model family
/// LifeOS has -- the sharpest test that filtering is genuinely by
/// `profile.id`, never by name/time coincidence.
///
/// Model-name note: the actual persisted types are `Activity` /
/// `CalendarItem` / `ActivitySession` (task/schedule/session),
/// `FoodEntry` / `WeightEntry` / `SportEntry` (legacy Nutrition/body/sport
/// tracking, still live behind FoodTrackerView/WeightTrackerView per
/// CLAUDE.md) and `MealEntry` / `WaterEntry` / `BodyMetricEntry` (the
/// newer Nutrition-native module). There is no `NutritionLog` or
/// `WeightLog` type in this codebase.
@MainActor
final class ProfileIsolationAuditTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try LifeOSDataStore.makeContainer(inMemory: true)
    }

    private struct TwoProfileFixture {
        let container: ModelContainer
        let context: ModelContext
        let vihaan: Profile
        let sibling: Profile
        let vihaanArea: AppCategory
        let siblingArea: AppCategory
        let vihaanActivity: Activity
        let siblingActivity: Activity
        let vihaanItem: CalendarItem
        let siblingItem: CalendarItem
        let vihaanSession: ActivitySession
        let siblingSession: ActivitySession
        let vihaanGoal: Goal
        let siblingGoal: Goal
        let vihaanMeasure: ResultMeasure
        let siblingMeasure: ResultMeasure
        let vihaanContribution: GoalAreaContribution
        let siblingContribution: GoalAreaContribution
        let vihaanFood: FoodEntry
        let siblingFood: FoodEntry
        let vihaanWeight: WeightEntry
        let siblingWeight: WeightEntry
        let vihaanMeal: MealEntry
        let siblingMeal: MealEntry
        let vihaanWater: WaterEntry
        let siblingWater: WaterEntry
        let vihaanBodyDefinition: BodyMetricDefinition
        let siblingBodyDefinition: BodyMetricDefinition
        let vihaanBodyEntry: BodyMetricEntry
        let siblingBodyEntry: BodyMetricEntry
    }

    /// Every record on both sides uses the same name, category name,
    /// schedule time, and day -- on purpose. Only `profile` differs.
    private func makeTwoProfileFixture() throws -> TwoProfileFixture {
        let container = try makeContainer()
        let context = container.mainContext
        let vihaan = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let sibling = Profile(name: "Sibling", kind: .child, colorToken: "green")
        let day = TestFixtures.date(2026, 3, 2)

        let vihaanArea = AppCategory(profile: vihaan, name: "Baseball", symbol: "figure.baseball", colorToken: "orange")
        let siblingArea = AppCategory(profile: sibling, name: "Baseball", symbol: "figure.baseball", colorToken: "orange")

        let vihaanActivity = Activity(
            profile: vihaan, category: vihaanArea, name: "Hitting",
            plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 30, startDate: day
        )
        let siblingActivity = Activity(
            profile: sibling, category: siblingArea, name: "Hitting",
            plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 30, startDate: day
        )
        let vihaanItem = CalendarItem(profile: vihaan, activity: vihaanActivity, date: day, plannedStart: TestFixtures.date(2026, 3, 2, hour: 18), status: .done)
        let siblingItem = CalendarItem(profile: sibling, activity: siblingActivity, date: day, plannedStart: TestFixtures.date(2026, 3, 2, hour: 18), status: .done)
        let vihaanSession = ActivitySession(activity: vihaanActivity, calendarItem: vihaanItem, date: day, recordedValue: 10)
        let siblingSession = ActivitySession(activity: siblingActivity, calendarItem: siblingItem, date: day, recordedValue: 10)

        let vihaanGoal = Goal(profile: vihaan, name: "Throw 70 mph")
        let siblingGoal = Goal(profile: sibling, name: "Throw 70 mph")
        let vihaanMeasure = ResultMeasure(goal: vihaanGoal, name: "Velocity", role: .primary, direction: .increase, baselineValue: 60, targetValue: 70)
        let siblingMeasure = ResultMeasure(goal: siblingGoal, name: "Velocity", role: .primary, direction: .increase, baselineValue: 60, targetValue: 70)
        let vihaanContribution = GoalAreaContribution(goal: vihaanGoal, category: vihaanArea)
        let siblingContribution = GoalAreaContribution(goal: siblingGoal, category: siblingArea)

        let vihaanFood = FoodEntry(profile: vihaan, date: day, mealType: .lunch, name: "Chicken bowl", calories: 600)
        let siblingFood = FoodEntry(profile: sibling, date: day, mealType: .lunch, name: "Chicken bowl", calories: 600)
        let vihaanWeight = WeightEntry(profile: vihaan, date: day, kilograms: 45)
        let siblingWeight = WeightEntry(profile: sibling, date: day, kilograms: 45)

        let vihaanMeal = MealEntry(profileID: vihaan.id, mealType: .lunch, recordedAt: day)
        vihaanMeal.setTotals(NutritionValue(calories: 600, proteinG: 40, carbsG: 60, fatG: 15))
        let siblingMeal = MealEntry(profileID: sibling.id, mealType: .lunch, recordedAt: day)
        siblingMeal.setTotals(NutritionValue(calories: 600, proteinG: 40, carbsG: 60, fatG: 15))
        let vihaanWater = WaterEntry(profileID: vihaan.id, recordedAt: day, amountML: 500)
        let siblingWater = WaterEntry(profileID: sibling.id, recordedAt: day, amountML: 500)

        let vihaanBodyDefinition = BodyMetricDefinition(profileID: vihaan.id, name: "Weight", unit: "kg", isSystemDefault: true, sortOrder: 0)
        let siblingBodyDefinition = BodyMetricDefinition(profileID: sibling.id, name: "Weight", unit: "kg", isSystemDefault: true, sortOrder: 0)
        let vihaanBodyEntry = BodyMetricEntry(profileID: vihaan.id, bodyMetricDefinition: vihaanBodyDefinition, nameSnapshot: "Weight", unitSnapshot: "kg", value: 45, recordedAt: day)
        let siblingBodyEntry = BodyMetricEntry(profileID: sibling.id, bodyMetricDefinition: siblingBodyDefinition, nameSnapshot: "Weight", unitSnapshot: "kg", value: 45, recordedAt: day)

        [vihaan, sibling].forEach(context.insert)
        [vihaanArea, siblingArea].forEach(context.insert)
        [vihaanActivity, siblingActivity].forEach(context.insert)
        [vihaanItem, siblingItem].forEach(context.insert)
        [vihaanSession, siblingSession].forEach(context.insert)
        [vihaanGoal, siblingGoal].forEach(context.insert)
        [vihaanMeasure, siblingMeasure].forEach(context.insert)
        [vihaanContribution, siblingContribution].forEach(context.insert)
        [vihaanFood, siblingFood].forEach(context.insert)
        [vihaanWeight, siblingWeight].forEach(context.insert)
        [vihaanMeal, siblingMeal].forEach(context.insert)
        [vihaanWater, siblingWater].forEach(context.insert)
        [vihaanBodyDefinition, siblingBodyDefinition].forEach(context.insert)
        [vihaanBodyEntry, siblingBodyEntry].forEach(context.insert)
        try context.save()

        return TwoProfileFixture(
            container: container, context: context, vihaan: vihaan, sibling: sibling,
            vihaanArea: vihaanArea, siblingArea: siblingArea,
            vihaanActivity: vihaanActivity, siblingActivity: siblingActivity,
            vihaanItem: vihaanItem, siblingItem: siblingItem,
            vihaanSession: vihaanSession, siblingSession: siblingSession,
            vihaanGoal: vihaanGoal, siblingGoal: siblingGoal,
            vihaanMeasure: vihaanMeasure, siblingMeasure: siblingMeasure,
            vihaanContribution: vihaanContribution, siblingContribution: siblingContribution,
            vihaanFood: vihaanFood, siblingFood: siblingFood,
            vihaanWeight: vihaanWeight, siblingWeight: siblingWeight,
            vihaanMeal: vihaanMeal, siblingMeal: siblingMeal,
            vihaanWater: vihaanWater, siblingWater: siblingWater,
            vihaanBodyDefinition: vihaanBodyDefinition, siblingBodyDefinition: siblingBodyDefinition,
            vihaanBodyEntry: vihaanBodyEntry, siblingBodyEntry: siblingBodyEntry
        )
    }

    // MARK: - Direct queries stay scoped by profile.id

    func testDirectQueriesForEveryModelFamilyAreScopedByProfileIDNotNameOrTime() throws {
        let fixture = try makeTwoProfileFixture()
        let context = fixture.context

        let activities = try context.fetch(FetchDescriptor<Activity>()).filter { $0.profile?.id == fixture.vihaan.id }
        XCTAssertEqual(activities.map(\.id), [fixture.vihaanActivity.id])

        let items = try context.fetch(FetchDescriptor<CalendarItem>()).filter { $0.profile?.id == fixture.vihaan.id }
        XCTAssertEqual(items.map(\.id), [fixture.vihaanItem.id])

        let sessions = try context.fetch(FetchDescriptor<ActivitySession>()).filter { $0.calendarItem?.profile?.id == fixture.vihaan.id }
        XCTAssertEqual(sessions.map(\.id), [fixture.vihaanSession.id])

        let goals = try context.fetch(FetchDescriptor<Goal>()).filter { $0.profile?.id == fixture.vihaan.id }
        XCTAssertEqual(goals.map(\.id), [fixture.vihaanGoal.id])

        let food = try context.fetch(FetchDescriptor<FoodEntry>()).filter { $0.profile?.id == fixture.vihaan.id }
        XCTAssertEqual(food.map(\.id), [fixture.vihaanFood.id])

        let weight = try context.fetch(FetchDescriptor<WeightEntry>()).filter { $0.profile?.id == fixture.vihaan.id }
        XCTAssertEqual(weight.map(\.id), [fixture.vihaanWeight.id])

        let meals = try context.fetch(FetchDescriptor<MealEntry>()).filter { $0.profileID == fixture.vihaan.id }
        XCTAssertEqual(meals.map(\.id), [fixture.vihaanMeal.id])

        let water = try context.fetch(FetchDescriptor<WaterEntry>()).filter { $0.profileID == fixture.vihaan.id }
        XCTAssertEqual(water.map(\.id), [fixture.vihaanWater.id])

        let bodyEntries = try context.fetch(FetchDescriptor<BodyMetricEntry>()).filter { $0.profileID == fixture.vihaan.id }
        XCTAssertEqual(bodyEntries.map(\.id), [fixture.vihaanBodyEntry.id])
    }

    // MARK: - Engine aggregations stay scoped even given unfiltered input

    func testCategoryProgressAggregationNeverCountsAnotherProfilesIdenticalSession() throws {
        let fixture = try makeTwoProfileFixture()
        let allActivities = [fixture.vihaanActivity, fixture.siblingActivity]
        let allItems = [fixture.vihaanItem, fixture.siblingItem]

        let progress = CategoryProgressEngine.progress(
            profile: fixture.vihaan, category: fixture.vihaanArea, period: .day, now: TestFixtures.date(2026, 3, 2),
            activities: allActivities, calendarItems: allItems,
            foodEntries: [], weightEntries: [], sportEntries: [], calendar: TestFixtures.calendar
        )

        XCTAssertEqual(progress.completedSessions, 1, "must count only Vihaan's own completed Hitting session")
    }

    func testGoalProgressAggregationNeverCountsAnotherProfilesIdenticalContribution() throws {
        let fixture = try makeTwoProfileFixture()

        let progress = GoalProgressEngine.progress(
            goal: fixture.vihaanGoal, period: .day, now: TestFixtures.date(2026, 3, 2),
            categories: [fixture.vihaanArea, fixture.siblingArea],
            contributions: [fixture.vihaanContribution, fixture.siblingContribution],
            measures: [fixture.vihaanMeasure, fixture.siblingMeasure], entries: [],
            activities: [fixture.vihaanActivity, fixture.siblingActivity],
            calendarItems: [fixture.vihaanItem, fixture.siblingItem], calendar: TestFixtures.calendar
        )

        XCTAssertEqual(progress.contributions.count, 1, "Vihaan's Goal must only ever resolve its own GoalAreaContribution")
        XCTAssertEqual(progress.contributions.first?.completedActions, 1)
    }

    func testNutritionAggregationNeverSumsAnotherProfilesIdenticalMeal() throws {
        let fixture = try makeTwoProfileFixture()
        let day = TestFixtures.date(2026, 3, 2)

        let totals = NutritionEngine.dailyTotals(
            profileID: fixture.vihaan.id, date: day,
            meals: [fixture.vihaanMeal, fixture.siblingMeal],
            waterEntries: [fixture.vihaanWater, fixture.siblingWater]
        )

        XCTAssertEqual(totals.calories, 600, "must not double-count Sibling's identical meal")
        XCTAssertEqual(totals.waterML, 500, "must not double-count Sibling's identical water entry")
    }

    func testBodyTrackingLookupNeverReturnsAnotherProfilesIdenticalEntry() throws {
        let fixture = try makeTwoProfileFixture()
        let day = TestFixtures.date(2026, 3, 2)

        let latest = BodyTrackingEngine.latestEntry(
            definitionID: fixture.vihaanBodyDefinition.id,
            entries: [fixture.vihaanBodyEntry, fixture.siblingBodyEntry], on: day
        )

        XCTAssertEqual(latest?.id, fixture.vihaanBodyEntry.id, "must resolve by definitionID, which is itself profile-scoped, never by coincidental matching value")
    }

    // MARK: - Profile hide/restore never touches the other profile or its data

    func testHidingOneProfileNeverChangesAnotherProfilesActiveStateOrData() throws {
        let fixture = try makeTwoProfileFixture()
        let context = fixture.context

        fixture.vihaan.isActive = false
        try context.save()

        let refreshedSibling = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Profile>()).first { $0.id == fixture.sibling.id }
        )
        XCTAssertTrue(refreshedSibling.isActive, "hiding Vihaan must never hide Sibling")

        let siblingActivities = try context.fetch(FetchDescriptor<Activity>()).filter { $0.profile?.id == fixture.sibling.id }
        XCTAssertEqual(siblingActivities.map(\.id), [fixture.siblingActivity.id], "hiding a profile must never delete or mutate another profile's records")
        XCTAssertTrue(siblingActivities.allSatisfy(\.isActive))
    }

    // MARK: - Activity delete/archive cascade stays within its own profile

    /// Mirrors EditTaskView.deleteOrArchive()'s no-history branch exactly:
    /// delete every CalendarItem for the Activity, then the Activity itself.
    func testDeletingAnActivityWithNoHistoryOnlyRemovesItsOwnCalendarItemsNeverAnotherProfiles() throws {
        let fixture = try makeTwoProfileFixture()
        let context = fixture.context
        // Give Vihaan's Activity a second, untouched (no-history) occurrence to delete via the no-history path.
        let freshActivity = Activity(
            profile: fixture.vihaan, category: fixture.vihaanArea, name: "Fielding",
            plannedStartMinutes: 19 * 60, estimatedDurationMinutes: 20, startDate: TestFixtures.date(2026, 3, 2)
        )
        let freshSiblingActivity = Activity(
            profile: fixture.sibling, category: fixture.siblingArea, name: "Fielding",
            plannedStartMinutes: 19 * 60, estimatedDurationMinutes: 20, startDate: TestFixtures.date(2026, 3, 2)
        )
        let freshItem = CalendarItem(profile: fixture.vihaan, activity: freshActivity, date: TestFixtures.date(2026, 3, 2), plannedStart: TestFixtures.date(2026, 3, 2, hour: 19))
        let freshSiblingItem = CalendarItem(profile: fixture.sibling, activity: freshSiblingActivity, date: TestFixtures.date(2026, 3, 2), plannedStart: TestFixtures.date(2026, 3, 2, hour: 19))
        context.insert(freshActivity); context.insert(freshSiblingActivity)
        context.insert(freshItem); context.insert(freshSiblingItem)
        try context.save()

        let allItems = try context.fetch(FetchDescriptor<CalendarItem>())
        allItems.filter { $0.activity?.id == freshActivity.id }.forEach(context.delete)
        context.delete(freshActivity)
        try context.save()

        let remainingItems = try context.fetch(FetchDescriptor<CalendarItem>())
        XCTAssertTrue(remainingItems.contains { $0.id == freshSiblingItem.id }, "Sibling's identically-named/timed occurrence must survive Vihaan's Activity deletion")
        XCTAssertFalse(remainingItems.contains { $0.id == freshItem.id })
        let remainingActivities = try context.fetch(FetchDescriptor<Activity>())
        XCTAssertTrue(remainingActivities.contains { $0.id == freshSiblingActivity.id })
        XCTAssertFalse(remainingActivities.contains { $0.id == freshActivity.id })
    }
}
