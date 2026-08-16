import XCTest
import SwiftData
@testable import LifeOS

/// Phase 4 / Chunk 1: Guided first-time setup (LifeOSOnboardingView,
/// RootTabView.swift) must persist the complete graph its `createLifeOS()`
/// builds -- Goal -> primary ResultMeasure -> AppCategory ->
/// GoalAreaContribution -> Activity -> CalendarItem -- and must reject
/// empty intent, outcome, plan name, and task input before that graph is
/// ever constructed. LifeOSOnboardingView is `private`, so this mirrors its
/// exact construction (same shape as testGoalGraphPersistsWithRelationshipsAndProfileIsolation
/// below) and exercises the extracted OnboardingValidation gates directly.
@MainActor
final class OnboardingGraphPersistenceTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try LifeOSDataStore.makeContainer(inMemory: true)
    }

    // MARK: - Validation

    func testCannotContinuePastIntentWithEmptyOrWhitespaceOnlyText() {
        XCTAssertFalse(OnboardingValidation.canContinueFromIntent(""))
        XCTAssertFalse(OnboardingValidation.canContinueFromIntent("   "))
        XCTAssertTrue(OnboardingValidation.canContinueFromIntent("Get stronger"))
    }

    func testCannotContinuePastOutcomeWithEmptyName() {
        XCTAssertFalse(OnboardingValidation.canContinueFromOutcome(
            outcomeName: "", valueType: .number, direction: .increase,
            target: 10, minimum: 0, maximum: 0
        ))
    }

    func testCannotContinuePastOutcomeWithAnInvalidNumericTarget() {
        // Increase direction with a target at or below the implicit 0 baseline.
        XCTAssertFalse(OnboardingValidation.canContinueFromOutcome(
            outcomeName: "Bench press", valueType: .number, direction: .increase,
            target: 0, minimum: 0, maximum: 0
        ))
    }

    func testCanContinuePastOutcomeWithAValidNumericTarget() {
        XCTAssertTrue(OnboardingValidation.canContinueFromOutcome(
            outcomeName: "Bench press", valueType: .number, direction: .increase,
            target: 80, minimum: 0, maximum: 0
        ))
    }

    func testMilestoneAndTextOutcomesSkipNumericTargetValidation() {
        XCTAssertTrue(OnboardingValidation.canContinueFromOutcome(
            outcomeName: "Ran a 5k", valueType: .milestone, direction: .increase,
            target: 0, minimum: 0, maximum: 0
        ))
        XCTAssertTrue(OnboardingValidation.canContinueFromOutcome(
            outcomeName: "How I felt", valueType: .text, direction: .increase,
            target: 0, minimum: 0, maximum: 0
        ))
    }

    func testCannotCreateWithAnEmptyPlanName() {
        XCTAssertFalse(OnboardingValidation.canCreate(
            areaName: "  ", taskNamesAndWeekdays: [(name: "Practice", weekdays: [2, 4])]
        ))
    }

    func testCannotCreateWithNoTasks() {
        XCTAssertFalse(OnboardingValidation.canCreate(areaName: "Strength Training", taskNamesAndWeekdays: []))
    }

    func testCannotCreateWithATaskThatHasAnEmptyName() {
        XCTAssertFalse(OnboardingValidation.canCreate(
            areaName: "Strength Training", taskNamesAndWeekdays: [(name: "  ", weekdays: [2, 4])]
        ))
    }

    func testCannotCreateWithATaskThatHasNoWeekdaysSelected() {
        XCTAssertFalse(OnboardingValidation.canCreate(
            areaName: "Strength Training", taskNamesAndWeekdays: [(name: "Practice", weekdays: [])]
        ))
    }

    func testCanCreateWithAValidPlanAndAtLeastOneCompleteTask() {
        XCTAssertTrue(OnboardingValidation.canCreate(
            areaName: "Strength Training", taskNamesAndWeekdays: [(name: "Bench press practice", weekdays: [2, 4, 6])]
        ))
    }

    // MARK: - Graph persistence

    /// Mirrors LifeOSOnboardingView.createLifeOS() exactly: one AppCategory,
    /// one Goal with a primary ResultMeasure, one GoalAreaContribution
    /// linking them, one or more Activities, then calendar generation.
    func testOnboardingGraphPersistsGoalMeasureCategoryContributionActivityAndCalendarItem() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        context.insert(profile)

        let areaName = "Strength Training"
        let improvement = "Get stronger"
        let category = AppCategory(
            profile: profile, name: areaName, symbol: "sparkles", colorToken: "blue",
            pillar: .life, trackingKind: .tasks,
            purpose: "Move \(areaName) forward through consistent action.",
            weeklyTargetSessions: 3, weeklyTargetMinutes: 90
        )
        let goal = Goal(profile: profile, name: improvement, targetDate: nil)
        let measure = ResultMeasure(
            goal: goal, name: "Bench press", role: .primary, valueType: .number,
            unit: "kg", direction: .increase, targetValue: 80
        )
        let contribution = GoalAreaContribution(
            goal: goal, category: category, statement: "\(areaName) supports \(improvement).",
            weeklyTargetSessions: category.weeklyTargetSessions, weeklyTargetMinutes: category.weeklyTargetMinutes
        )
        context.insert(category)
        context.insert(goal)
        context.insert(measure)
        context.insert(contribution)

        // .daily/every weekday, not a fixed subset -- this proves generation
        // works regardless of which real-world weekday the test happens to
        // run on; selectedWeekdays recurrence itself is covered by
        // PlanningServiceTests.
        let activity = Activity(
            profile: profile, category: category, name: "Bench press practice",
            source: .template, repeatType: .selectedWeekdays, weekdays: Array(1...7),
            plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 30
        )
        context.insert(activity)
        try context.save()

        let today = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month, .day], from: .now))!
        let generated = try PlanningService.insertMissingCalendarItems(
            profile: profile, date: today, activities: [activity], context: context
        )
        try context.save()

        // Goal -> primary ResultMeasure
        let storedGoals = try context.fetch(FetchDescriptor<Goal>())
        XCTAssertEqual(storedGoals.count, 1)
        let storedGoal = try XCTUnwrap(storedGoals.first)
        XCTAssertEqual(storedGoal.profile?.id, profile.id)
        let storedMeasures = try context.fetch(FetchDescriptor<ResultMeasure>())
        XCTAssertEqual(storedMeasures.count, 1)
        XCTAssertEqual(storedMeasures.first?.goal?.id, storedGoal.id)
        XCTAssertEqual(storedMeasures.first?.role, .primary)

        // Goal -> GoalAreaContribution -> AppCategory
        let storedContributions = try context.fetch(FetchDescriptor<GoalAreaContribution>())
        XCTAssertEqual(storedContributions.count, 1)
        XCTAssertEqual(storedContributions.first?.goal?.id, storedGoal.id)
        XCTAssertEqual(storedContributions.first?.category?.name, areaName)

        // AppCategory -> Activity -> CalendarItem
        let storedActivities = try context.fetch(FetchDescriptor<Activity>())
        XCTAssertEqual(storedActivities.count, 1)
        XCTAssertEqual(storedActivities.first?.category?.id, storedContributions.first?.category?.id)
        XCTAssertEqual(storedActivities.first?.profile?.id, profile.id)

        XCTAssertFalse(generated.isEmpty, "an onboarding Task scheduled for today must generate at least one occurrence immediately")
        let storedItems = try context.fetch(FetchDescriptor<CalendarItem>())
        XCTAssertTrue(storedItems.allSatisfy { $0.activity?.id == storedActivities.first?.id })
        XCTAssertTrue(storedItems.allSatisfy { $0.profile?.id == profile.id })
    }

    func testOnboardingGraphKeepsTwoProfilesFullyIsolated() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let vihaan = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let parent = Profile(name: "Parent", kind: .parent, colorToken: "green")
        context.insert(vihaan)
        context.insert(parent)

        let category = AppCategory(profile: vihaan, name: "Reading", symbol: "book", colorToken: "blue", pillar: .learning)
        let goal = Goal(profile: vihaan, name: "Read more")
        let measure = ResultMeasure(goal: goal, name: "Books finished", role: .primary, valueType: .number, direction: .increase, targetValue: 12)
        let contribution = GoalAreaContribution(goal: goal, category: category)
        context.insert(category)
        context.insert(goal)
        context.insert(measure)
        context.insert(contribution)
        try context.save()

        let goals = try context.fetch(FetchDescriptor<Goal>())
        let categories = try context.fetch(FetchDescriptor<AppCategory>())
        XCTAssertEqual(goals.filter { $0.profile?.id == vihaan.id }.count, 1)
        XCTAssertEqual(goals.filter { $0.profile?.id == parent.id }.count, 0)
        XCTAssertEqual(categories.filter { $0.profile?.id == parent.id }.count, 0)
    }
}
