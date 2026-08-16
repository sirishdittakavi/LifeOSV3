import XCTest
import SwiftData
@testable import LifeOS

/// Phase 5 / Chunk 1: the 3-step Add Goal flow (AddGoalView,
/// ImprovementDashboardView.swift) must persist strictly to the existing
/// Goal / ResultMeasure / GoalAreaContribution schema -- no new model types
/// -- and each of the four Result sources (Manual, Activity measurement,
/// Nutrition metric, Body metric) must gate save() correctly. AddGoalView's
/// canSave/save() are private, so this exercises the extracted
/// AddGoalValidation gate directly and mirrors save()'s exact graph shape.
@MainActor
final class AddGoalGraphTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try LifeOSDataStore.makeContainer(inMemory: true)
    }

    // MARK: - Validation: base fields

    func testCannotSaveWithAnEmptyGoalName() {
        XCTAssertFalse(AddGoalValidation.canSave(
            name: "", measureName: "Score", selectedAreaIDs: [UUID()],
            valueType: .number, direction: .increase, baseline: 0, target: 10, minimum: 0, maximum: 0,
            resultSource: .manual, selectedMeasurementDefinitionID: nil,
            selectedNutritionMetric: nil, selectedBodyMetricDefinitionID: nil
        ))
    }

    func testCannotSaveWithAnEmptyMeasureName() {
        XCTAssertFalse(AddGoalValidation.canSave(
            name: "Feel confident in maths", measureName: "  ", selectedAreaIDs: [UUID()],
            valueType: .number, direction: .increase, baseline: 0, target: 10, minimum: 0, maximum: 0,
            resultSource: .manual, selectedMeasurementDefinitionID: nil,
            selectedNutritionMetric: nil, selectedBodyMetricDefinitionID: nil
        ))
    }

    func testCannotSaveWithNoSupportingPlanSelected() {
        XCTAssertFalse(AddGoalValidation.canSave(
            name: "Feel confident in maths", measureName: "Mock-test score", selectedAreaIDs: [],
            valueType: .number, direction: .increase, baseline: 0, target: 10, minimum: 0, maximum: 0,
            resultSource: .manual, selectedMeasurementDefinitionID: nil,
            selectedNutritionMetric: nil, selectedBodyMetricDefinitionID: nil
        ))
    }

    func testCannotSaveWithAnInvalidNumericTarget() {
        // decrease direction with a target above baseline is invalid.
        XCTAssertFalse(AddGoalValidation.canSave(
            name: "Lose weight", measureName: "Body weight", selectedAreaIDs: [UUID()],
            valueType: .number, direction: .decrease, baseline: 80, target: 85, minimum: 0, maximum: 0,
            resultSource: .manual, selectedMeasurementDefinitionID: nil,
            selectedNutritionMetric: nil, selectedBodyMetricDefinitionID: nil
        ))
    }

    // MARK: - Validation: per Result-source gating

    func testManualResultSourceNeedsNoLinkedDefinition() {
        XCTAssertTrue(AddGoalValidation.canSave(
            name: "Feel confident in maths", measureName: "Mock-test score", selectedAreaIDs: [UUID()],
            valueType: .number, direction: .increase, baseline: 50, target: 90, minimum: 0, maximum: 0,
            resultSource: .manual, selectedMeasurementDefinitionID: nil,
            selectedNutritionMetric: nil, selectedBodyMetricDefinitionID: nil
        ))
    }

    func testActivityMeasurementSourceRequiresASelectedDefinition() {
        XCTAssertFalse(AddGoalValidation.canSave(
            name: "Throw harder", measureName: "Throwing velocity", selectedAreaIDs: [UUID()],
            valueType: .number, direction: .increase, baseline: 60, target: 70, minimum: 0, maximum: 0,
            resultSource: .activityMeasurement, selectedMeasurementDefinitionID: nil,
            selectedNutritionMetric: nil, selectedBodyMetricDefinitionID: nil
        ))
        XCTAssertTrue(AddGoalValidation.canSave(
            name: "Throw harder", measureName: "Throwing velocity", selectedAreaIDs: [UUID()],
            valueType: .number, direction: .increase, baseline: 60, target: 70, minimum: 0, maximum: 0,
            resultSource: .activityMeasurement, selectedMeasurementDefinitionID: UUID(),
            selectedNutritionMetric: nil, selectedBodyMetricDefinitionID: nil
        ))
    }

    func testNutritionMetricSourceRequiresASelectedMetric() {
        XCTAssertFalse(AddGoalValidation.canSave(
            name: "Eat more protein", measureName: "Daily protein", selectedAreaIDs: [UUID()],
            valueType: .number, direction: .increase, baseline: 80, target: 150, minimum: 0, maximum: 0,
            resultSource: .nutritionMetric, selectedMeasurementDefinitionID: nil,
            selectedNutritionMetric: nil, selectedBodyMetricDefinitionID: nil
        ))
        XCTAssertTrue(AddGoalValidation.canSave(
            name: "Eat more protein", measureName: "Daily protein", selectedAreaIDs: [UUID()],
            valueType: .number, direction: .increase, baseline: 80, target: 150, minimum: 0, maximum: 0,
            resultSource: .nutritionMetric, selectedMeasurementDefinitionID: nil,
            selectedNutritionMetric: .protein, selectedBodyMetricDefinitionID: nil
        ))
    }

    func testBodyMetricSourceRequiresASelectedDefinition() {
        XCTAssertFalse(AddGoalValidation.canSave(
            name: "Reach race weight", measureName: "Body weight", selectedAreaIDs: [UUID()],
            valueType: .number, direction: .decrease, baseline: 82, target: 78, minimum: 0, maximum: 0,
            resultSource: .bodyMetric, selectedMeasurementDefinitionID: nil,
            selectedNutritionMetric: nil, selectedBodyMetricDefinitionID: nil
        ))
        XCTAssertTrue(AddGoalValidation.canSave(
            name: "Reach race weight", measureName: "Body weight", selectedAreaIDs: [UUID()],
            valueType: .number, direction: .decrease, baseline: 82, target: 78, minimum: 0, maximum: 0,
            resultSource: .bodyMetric, selectedMeasurementDefinitionID: nil,
            selectedNutritionMetric: nil, selectedBodyMetricDefinitionID: UUID()
        ))
    }

    func testMilestoneAndTextResultsSkipLinkedDefinitionRequirementRegardlessOfSource() {
        XCTAssertTrue(AddGoalValidation.canSave(
            name: "Run a 5k", measureName: "Finished a 5k", selectedAreaIDs: [UUID()],
            valueType: .milestone, direction: .increase, baseline: 0, target: 0, minimum: 0, maximum: 0,
            resultSource: .activityMeasurement, selectedMeasurementDefinitionID: nil,
            selectedNutritionMetric: nil, selectedBodyMetricDefinitionID: nil
        ))
    }

    // MARK: - Graph persistence: strictly the existing schema

    /// Mirrors AddGoalView.save() exactly for a manual-check-in Result:
    /// Goal -> primary ResultMeasure, Goal -> GoalAreaContribution -> AppCategory.
    /// No new model type is introduced.
    func testAddGoalGraphPersistsGoalMeasureAndContributionsForEverySelectedArea() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = Profile(name: "Aanya", kind: .child, colorToken: "purple")
        let maths = AppCategory(profile: profile, name: "Maths", symbol: "sum", colorToken: "blue", pillar: .learning)
        let scienceClub = AppCategory(profile: profile, name: "Science Club", symbol: "atom", colorToken: "green", pillar: .learning)
        context.insert(profile)
        context.insert(maths)
        context.insert(scienceClub)
        try context.save()

        let goal = Goal(profile: profile, name: "Feel confident in maths", purpose: "Build exam confidence")
        context.insert(goal)
        let measure = ResultMeasure(
            goal: goal, name: "Mock-test score", valueType: .number, unit: "%",
            direction: .increase, baselineValue: 55, targetValue: 85,
            cadence: .monthly, nextCheckInDate: Calendar.current.date(byAdding: .month, value: 1, to: .now),
            reminderEnabled: true, reminderHour: 18, reminderMinute: 0
        )
        context.insert(measure)
        let contributions = [maths, scienceClub].map { area in
            let contribution = GoalAreaContribution(
                goal: goal, category: area, statement: "\(area.name) supports \(goal.name).",
                weeklyTargetSessions: area.weeklyTargetSessions, weeklyTargetMinutes: area.weeklyTargetMinutes
            )
            context.insert(contribution)
            return contribution
        }
        try context.save()

        let storedGoals = try context.fetch(FetchDescriptor<Goal>())
        XCTAssertEqual(storedGoals.count, 1)
        let storedMeasures = try context.fetch(FetchDescriptor<ResultMeasure>())
        XCTAssertEqual(storedMeasures.count, 1)
        XCTAssertEqual(storedMeasures.first?.goal?.id, storedGoals.first?.id)
        XCTAssertEqual(storedMeasures.first?.cadence, .monthly)

        let storedContributions = try context.fetch(FetchDescriptor<GoalAreaContribution>())
        XCTAssertEqual(storedContributions.count, 2, "one GoalAreaContribution must be created per selected Plan")
        XCTAssertEqual(Set(storedContributions.compactMap { $0.category?.name }), Set(["Maths", "Science Club"]))
        XCTAssertTrue(storedContributions.allSatisfy { $0.goal?.id == storedGoals.first?.id })
        XCTAssertEqual(contributions.count, 2)
    }

    /// The Activity-measurement Result source persists as a link (an existing
    /// field on ResultMeasure), not as a new schema type.
    func testAddGoalGraphPersistsAnActivityMeasurementLink() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let baseball = AppCategory(profile: profile, name: "Baseball", symbol: "figure.baseball", colorToken: "orange", pillar: .sport)
        let throwing = Activity(profile: profile, category: baseball, name: "Throwing practice", plannedStartMinutes: 600, estimatedDurationMinutes: 20)
        let definition = MeasurementDefinition(activity: throwing, name: "Velocity", type: .count, unit: "mph", sortOrder: 0)
        context.insert(profile)
        context.insert(baseball)
        context.insert(throwing)
        context.insert(definition)
        try context.save()

        let goal = Goal(profile: profile, name: "Throw 70 mph")
        context.insert(goal)
        let measure = ResultMeasure(
            goal: goal, name: "Throwing velocity", valueType: .number, unit: "mph",
            direction: .increase, baselineValue: 60, targetValue: 70,
            linkedMeasurementDefinitionID: definition.id
        )
        context.insert(measure)
        let contribution = GoalAreaContribution(goal: goal, category: baseball)
        context.insert(contribution)
        try context.save()

        let stored = try context.fetch(FetchDescriptor<ResultMeasure>())
        XCTAssertEqual(stored.first?.linkedMeasurementDefinitionID, definition.id)
        XCTAssertNil(stored.first?.linkedNutritionMetric)
        XCTAssertNil(stored.first?.linkedBodyMetricDefinitionID)
    }

    /// The Nutrition-metric Result source likewise persists onto the same
    /// ResultMeasure record via its existing linkedNutritionMetric field.
    func testAddGoalGraphPersistsANutritionMetricLink() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let nutrition = AppCategory(profile: profile, name: "Nutrition", symbol: "fork.knife", colorToken: "green", pillar: .nutrition, trackingKind: .nutrition)
        context.insert(profile)
        context.insert(nutrition)
        try context.save()

        let goal = Goal(profile: profile, name: "Eat more protein")
        context.insert(goal)
        let measure = ResultMeasure(
            goal: goal, name: "Daily protein", valueType: .number, unit: "g",
            direction: .increase, baselineValue: 80, targetValue: 150,
            linkedNutritionMetric: .protein
        )
        context.insert(measure)
        let contribution = GoalAreaContribution(goal: goal, category: nutrition)
        context.insert(contribution)
        try context.save()

        let stored = try context.fetch(FetchDescriptor<ResultMeasure>())
        XCTAssertEqual(stored.first?.linkedNutritionMetric, .protein)
        XCTAssertNil(stored.first?.linkedMeasurementDefinitionID)
    }

    /// The Body-metric Result source persists via the existing
    /// linkedBodyMetricDefinitionID field, matching the other two linkages.
    func testAddGoalGraphPersistsABodyMetricLink() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let body = AppCategory(profile: profile, name: "Body", symbol: "figure", colorToken: "teal", pillar: .physical, trackingKind: .bodyWeight)
        let definition = BodyMetricDefinition(profileID: profile.id, name: "Weight", unit: "kg", isSystemDefault: true, sortOrder: 0)
        context.insert(profile)
        context.insert(body)
        context.insert(definition)
        try context.save()

        let goal = Goal(profile: profile, name: "Reach race weight")
        context.insert(goal)
        let measure = ResultMeasure(
            goal: goal, name: "Body weight", valueType: .number, unit: "kg",
            direction: .decrease, baselineValue: 82, targetValue: 78,
            linkedBodyMetricDefinitionID: definition.id
        )
        context.insert(measure)
        let contribution = GoalAreaContribution(goal: goal, category: body)
        context.insert(contribution)
        try context.save()

        let stored = try context.fetch(FetchDescriptor<ResultMeasure>())
        XCTAssertEqual(stored.first?.linkedBodyMetricDefinitionID, definition.id)
        XCTAssertNil(stored.first?.linkedNutritionMetric)
    }

    func testAddGoalGraphKeepsTwoProfilesFullyIsolated() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let vihaan = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let parent = Profile(name: "Parent", kind: .parent, colorToken: "green")
        context.insert(vihaan)
        context.insert(parent)
        let area = AppCategory(profile: vihaan, name: "Baseball", symbol: "figure.baseball", colorToken: "orange")
        let goal = Goal(profile: vihaan, name: "Throw 70 mph")
        let measure = ResultMeasure(goal: goal, name: "Velocity", direction: .increase, baselineValue: 60, targetValue: 70)
        let contribution = GoalAreaContribution(goal: goal, category: area)
        context.insert(area)
        context.insert(goal)
        context.insert(measure)
        context.insert(contribution)
        try context.save()

        let goals = try context.fetch(FetchDescriptor<Goal>())
        XCTAssertEqual(goals.filter { $0.profile?.id == vihaan.id }.count, 1)
        XCTAssertEqual(goals.filter { $0.profile?.id == parent.id }.count, 0)
    }
}
