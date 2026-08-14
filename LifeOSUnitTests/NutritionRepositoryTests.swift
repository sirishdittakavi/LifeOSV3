import XCTest
@testable import LifeOS

/// Repository-protocol tests against a fake, mirroring
/// MeasurementRepositoryTests's shape. No ModelContext, no SwiftUI, and
/// nothing here is wired into any View/ViewModel yet.

private final class FakeNutritionRepository: NutritionRepository {
    var hasChanges = false
    var saveResult = true
    var insertedMeals: [MealEntry] = []
    var insertedFoodEntries: [NutritionFoodEntry] = []
    var deletedMeals: [MealEntry] = []
    var insertedTemplates: [MealTemplate] = []
    var deletedTemplates: [MealTemplate] = []
    var insertedWaterEntries: [WaterEntry] = []
    var deletedWaterEntries: [WaterEntry] = []
    var insertedGoals: [NutritionGoal] = []
    var deleteError: Error?

    func insertMeal(_ meal: MealEntry, foodEntries: [NutritionFoodEntry]) {
        insertedMeals.append(meal)
        for entry in foodEntries {
            entry.mealEntry = meal
            entry.mealTemplate = nil
            insertedFoodEntries.append(entry)
        }
    }

    func deleteMeal(_ meal: MealEntry) throws {
        if let deleteError { throw deleteError }
        insertedFoodEntries.removeAll { $0.mealEntry?.id == meal.id }
        deletedMeals.append(meal)
    }

    func insertTemplate(_ template: MealTemplate, foodEntries: [NutritionFoodEntry]) {
        insertedTemplates.append(template)
        for entry in foodEntries {
            entry.mealTemplate = template
            entry.mealEntry = nil
            insertedFoodEntries.append(entry)
        }
    }

    func deleteTemplate(_ template: MealTemplate) throws {
        if let deleteError { throw deleteError }
        insertedFoodEntries.removeAll { $0.mealTemplate?.id == template.id }
        deletedTemplates.append(template)
    }

    func insertWaterEntry(_ entry: WaterEntry) { insertedWaterEntries.append(entry) }
    func deleteWaterEntry(_ entry: WaterEntry) { deletedWaterEntries.append(entry) }
    func insertGoal(_ goal: NutritionGoal) { insertedGoals.append(goal) }

    @discardableResult func save() -> Bool { saveResult }
}

private final class FakeBodyTrackingRepository: BodyTrackingRepository {
    var hasChanges = false
    var saveResult = true
    var insertedDefinitions: [BodyMetricDefinition] = []
    var insertedEntries: [BodyMetricEntry] = []
    var deletedEntries: [BodyMetricEntry] = []

    func insertDefinition(_ definition: BodyMetricDefinition) { insertedDefinitions.append(definition) }
    func insertEntry(_ entry: BodyMetricEntry) { insertedEntries.append(entry) }
    func deleteEntry(_ entry: BodyMetricEntry) { deletedEntries.append(entry) }

    func seedDefaultDefinitionsIfNeeded(profileID: UUID, existingDefinitions: [BodyMetricDefinition]) {
        guard !existingDefinitions.contains(where: { $0.profileID == profileID }) else { return }
        for (index, metric) in SwiftDataBodyTrackingRepository.defaultMetrics.enumerated() {
            insertedDefinitions.append(
                BodyMetricDefinition(profileID: profileID, name: metric.name, unit: metric.unit, isSystemDefault: true, sortOrder: index)
            )
        }
    }

    @discardableResult func save() -> Bool { saveResult }
}

final class NutritionRepositoryTests: XCTestCase {
    func testInsertMealAlsoInsertsItsFoodEntries() {
        let repository = FakeNutritionRepository()
        let meal = MealEntry(profileID: UUID(), mealType: .breakfast)
        let foods = [NutritionFoodEntry(name: "Eggs"), NutritionFoodEntry(name: "Oats")]

        repository.insertMeal(meal, foodEntries: foods)

        XCTAssertEqual(repository.insertedMeals.map(\.id), [meal.id])
        XCTAssertEqual(repository.insertedFoodEntries.map(\.id), foods.map(\.id))
    }

    // MARK: - Ownership invariant (1A)

    func testInsertMealAssignsMealOwnershipAndClearsAnyTemplateLink() {
        let repository = FakeNutritionRepository()
        let template = MealTemplate(profileID: UUID(), name: "Stray template")
        let entry = NutritionFoodEntry(name: "Eggs")
        // Simulate a caller that mistakenly left the other parent set.
        entry.mealTemplate = template

        let meal = MealEntry(profileID: UUID(), mealType: .breakfast)
        repository.insertMeal(meal, foodEntries: [entry])

        XCTAssertEqual(entry.mealEntry?.id, meal.id)
        XCTAssertNil(entry.mealTemplate, "insertMeal must enforce exactly one parent, even if the caller set both")
    }

    func testInsertTemplateAssignsTemplateOwnershipAndClearsAnyMealLink() {
        let repository = FakeNutritionRepository()
        let meal = MealEntry(profileID: UUID(), mealType: .lunch)
        let entry = NutritionFoodEntry(name: "Rice")
        entry.mealEntry = meal

        let template = MealTemplate(profileID: UUID(), name: "Quick Lunch")
        repository.insertTemplate(template, foodEntries: [entry])

        XCTAssertEqual(entry.mealTemplate?.id, template.id)
        XCTAssertNil(entry.mealEntry, "insertTemplate must enforce exactly one parent, even if the caller set both")
    }

    func testReassigningAnEntryFromOneMealToAnotherLeavesExactlyOneOwner() {
        let repository = FakeNutritionRepository()
        let firstMeal = MealEntry(profileID: UUID(), mealType: .breakfast)
        let secondMeal = MealEntry(profileID: UUID(), mealType: .lunch)
        let entry = NutritionFoodEntry(name: "Leftover chicken")

        repository.insertMeal(firstMeal, foodEntries: [entry])
        XCTAssertEqual(entry.mealEntry?.id, firstMeal.id)

        repository.insertMeal(secondMeal, foodEntries: [entry])
        XCTAssertEqual(entry.mealEntry?.id, secondMeal.id)
        XCTAssertNil(entry.mealTemplate)
    }

    // MARK: - Safe parent deletion (1B)

    func testDeleteMealResolvesAndRemovesItsOwnFoodEntriesWithoutTheCallerSupplyingThem() throws {
        let repository = FakeNutritionRepository()
        let meal = MealEntry(profileID: UUID(), mealType: .dinner)
        let foods = [NutritionFoodEntry(name: "Salmon"), NutritionFoodEntry(name: "Rice")]
        repository.insertMeal(meal, foodEntries: foods)

        try repository.deleteMeal(meal)

        XCTAssertEqual(repository.deletedMeals.map(\.id), [meal.id])
        XCTAssertTrue(repository.insertedFoodEntries.isEmpty, "deleteMeal must resolve and remove its own children")
    }

    func testDeleteMealDoesNotTouchAnotherMealsFoodEntries() throws {
        let repository = FakeNutritionRepository()
        let keep = MealEntry(profileID: UUID(), mealType: .breakfast)
        let remove = MealEntry(profileID: UUID(), mealType: .dinner)
        repository.insertMeal(keep, foodEntries: [NutritionFoodEntry(name: "Oats")])
        repository.insertMeal(remove, foodEntries: [NutritionFoodEntry(name: "Salmon")])

        try repository.deleteMeal(remove)

        XCTAssertEqual(repository.insertedFoodEntries.count, 1)
        XCTAssertEqual(repository.insertedFoodEntries.first?.mealEntry?.id, keep.id)
    }

    func testDeleteTemplateResolvesAndRemovesItsOwnFoodEntries() throws {
        let repository = FakeNutritionRepository()
        let template = MealTemplate(profileID: UUID(), name: "My Protein Breakfast")
        repository.insertTemplate(template, foodEntries: [NutritionFoodEntry(name: "Eggs"), NutritionFoodEntry(name: "Oats")])

        try repository.deleteTemplate(template)

        XCTAssertEqual(repository.deletedTemplates.map(\.id), [template.id])
        XCTAssertTrue(repository.insertedFoodEntries.isEmpty)
    }

    func testInsertAndDeleteWaterEntry() {
        let repository = FakeNutritionRepository()
        let entry = WaterEntry(profileID: UUID(), amountML: 500)

        repository.insertWaterEntry(entry)
        XCTAssertEqual(repository.insertedWaterEntries.map(\.id), [entry.id])

        repository.deleteWaterEntry(entry)
        XCTAssertEqual(repository.deletedWaterEntries.map(\.id), [entry.id])
    }

    func testInsertGoal() {
        let repository = FakeNutritionRepository()
        let goal = NutritionGoal(profileID: UUID())

        repository.insertGoal(goal)

        XCTAssertEqual(repository.insertedGoals.map(\.id), [goal.id])
    }

    func testSaveDelegatesToTheUnderlyingStoreResult() {
        let repository = FakeNutritionRepository()
        XCTAssertTrue(repository.save())
        repository.saveResult = false
        XCTAssertFalse(repository.save())
    }
}

final class BodyTrackingRepositoryTests: XCTestCase {
    func testInsertAndDeleteEntryDelegateToTheUnderlyingStore() {
        let repository = FakeBodyTrackingRepository()
        let definition = BodyMetricDefinition(profileID: UUID(), name: "Weight", unit: "kg")
        let entry = BodyMetricEntry(
            profileID: definition.profileID, bodyMetricDefinition: definition,
            nameSnapshot: "Weight", unitSnapshot: "kg", value: 78.5
        )

        repository.insertDefinition(definition)
        repository.insertEntry(entry)
        XCTAssertEqual(repository.insertedDefinitions.map(\.id), [definition.id])
        XCTAssertEqual(repository.insertedEntries.map(\.id), [entry.id])

        repository.deleteEntry(entry)
        XCTAssertEqual(repository.deletedEntries.map(\.id), [entry.id])
    }

    func testSeedDefaultDefinitionsCreatesWeightHeightAndBodyFatForANewProfile() {
        let repository = FakeBodyTrackingRepository()
        let profileID = UUID()

        repository.seedDefaultDefinitionsIfNeeded(profileID: profileID, existingDefinitions: [])

        XCTAssertEqual(repository.insertedDefinitions.map(\.name), ["Weight", "Height", "Body Fat %"])
        XCTAssertTrue(repository.insertedDefinitions.allSatisfy { $0.isSystemDefault })
        XCTAssertEqual(repository.insertedDefinitions.map(\.sortOrder), [0, 1, 2])
    }

    func testSeedDefaultDefinitionsDoesNothingWhenProfileAlreadyHasDefinitions() {
        let repository = FakeBodyTrackingRepository()
        let profileID = UUID()
        let existing = [BodyMetricDefinition(profileID: profileID, name: "Waist", unit: "cm")]

        repository.seedDefaultDefinitionsIfNeeded(profileID: profileID, existingDefinitions: existing)

        XCTAssertTrue(repository.insertedDefinitions.isEmpty, "must not duplicate seeding for a profile that already has custom metrics")
    }

    func testSeedDefaultDefinitionsIsPerProfile() {
        let repository = FakeBodyTrackingRepository()
        let profileA = UUID()
        let profileB = UUID()
        let existingForA = [BodyMetricDefinition(profileID: profileA, name: "Weight", unit: "kg")]

        repository.seedDefaultDefinitionsIfNeeded(profileID: profileB, existingDefinitions: existingForA)

        XCTAssertEqual(repository.insertedDefinitions.count, 3, "profile B has no definitions of its own yet, despite profile A having one")
    }
}
