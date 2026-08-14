import XCTest
import SwiftData
@testable import LifeOS

/// Confirms the Nutrition/Body Tracking types are correctly registered in
/// LifeOSSchemaV1 and round-trip through a real ModelContainer via the new
/// repositories — including the ownership invariant and safe-deletion
/// behavior (Phase 1 repository gaps) against a real ModelContext, not just
/// a fake.
@MainActor
final class NutritionComponentTests: XCTestCase {
    func testMealWithFoodEntriesPersistsAndFetchesBackThroughTheRepository() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = SwiftDataNutritionRepository(context: context)
        let profileID = UUID()

        let meal = MealEntry(profileID: profileID, mealType: .breakfast)
        let foods = [
            NutritionFoodEntry(name: "Eggs", nutrition: NutritionValue(calories: 234, proteinG: 18)),
            NutritionFoodEntry(name: "Oats", nutrition: NutritionValue(calories: 228, carbsG: 40))
        ]
        repository.insertMeal(meal, foodEntries: foods)
        meal.recomputeTotals(from: foods)
        XCTAssertTrue(repository.save())

        let fetchedMeals = try context.fetch(FetchDescriptor<MealEntry>())
        let fetchedFoods = try context.fetch(FetchDescriptor<NutritionFoodEntry>())

        XCTAssertEqual(fetchedMeals.count, 1)
        XCTAssertEqual(fetchedMeals.first?.totals.calories, 462)
        XCTAssertEqual(fetchedFoods.filter { $0.mealEntry?.id == meal.id }.count, 2)
    }

    // MARK: - Ownership invariant (1A) against a real context

    func testInsertMealEnforcesSingleOwnershipEvenIfEntryWasPreviouslyTemplateOwned() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = SwiftDataNutritionRepository(context: context)
        let profileID = UUID()

        let template = MealTemplate(profileID: profileID, name: "My Protein Breakfast")
        let entry = NutritionFoodEntry(name: "Eggs")
        repository.insertTemplate(template, foodEntries: [entry])
        try context.save()
        XCTAssertEqual(entry.mealTemplate?.id, template.id)

        let meal = MealEntry(profileID: profileID, mealType: .breakfast)
        repository.insertMeal(meal, foodEntries: [entry])
        try context.save()

        XCTAssertEqual(entry.mealEntry?.id, meal.id)
        XCTAssertNil(entry.mealTemplate)

        let all = try context.fetch(FetchDescriptor<NutritionFoodEntry>())
        XCTAssertEqual(all.count, 1, "no duplicate entry was created by the reassignment")
    }

    // MARK: - Safe parent deletion (1B) against a real context

    func testDeletingAMealRemovesItsFoodEntriesButNotOtherMealsWithoutTheCallerSupplyingChildren() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = SwiftDataNutritionRepository(context: context)
        let profileID = UUID()

        let keep = MealEntry(profileID: profileID, mealType: .lunch)
        let remove = MealEntry(profileID: profileID, mealType: .dinner)
        repository.insertMeal(keep, foodEntries: [NutritionFoodEntry(name: "Rice")])
        repository.insertMeal(remove, foodEntries: [NutritionFoodEntry(name: "Salmon")])
        try context.save()

        // Deliberately does not pass any food entries — the repository must
        // resolve them itself.
        try repository.deleteMeal(remove)
        XCTAssertTrue(repository.save())

        let remainingMeals = try context.fetch(FetchDescriptor<MealEntry>())
        let remainingFoods = try context.fetch(FetchDescriptor<NutritionFoodEntry>())
        XCTAssertEqual(remainingMeals.map(\.id), [keep.id])
        XCTAssertEqual(remainingFoods.map(\.name), ["Rice"])
    }

    func testDeletingATemplateRemovesItsFoodEntriesButNotAMealsFoodEntries() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = SwiftDataNutritionRepository(context: context)
        let profileID = UUID()

        let meal = MealEntry(profileID: profileID, mealType: .breakfast)
        repository.insertMeal(meal, foodEntries: [NutritionFoodEntry(name: "Oats")])
        let template = MealTemplate(profileID: profileID, name: "Weekend Breakfast")
        repository.insertTemplate(template, foodEntries: [NutritionFoodEntry(name: "Pancakes")])
        try context.save()

        try repository.deleteTemplate(template)
        XCTAssertTrue(repository.save())

        let remainingFoods = try context.fetch(FetchDescriptor<NutritionFoodEntry>())
        XCTAssertEqual(remainingFoods.map(\.name), ["Oats"])
    }

    func testMealTemplateUsageRoundTripsThroughSave() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = SwiftDataNutritionRepository(context: context)

        let template = MealTemplate(profileID: UUID(), name: "My Protein Breakfast", mealTypeDefault: .breakfast)
        repository.insertTemplate(template, foodEntries: [])
        template.recordUse()
        XCTAssertTrue(repository.save())

        let fetched = try context.fetch(FetchDescriptor<MealTemplate>())
        XCTAssertEqual(fetched.first?.useCount, 1)
        XCTAssertNotNil(fetched.first?.lastUsedAt)
    }

    func testBodyMetricSeedingPersistsWeightHeightAndBodyFatOncePerProfile() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = SwiftDataBodyTrackingRepository(context: context)
        let profileID = UUID()

        repository.seedDefaultDefinitionsIfNeeded(profileID: profileID, existingDefinitions: [])
        try context.save()

        var definitions = try context.fetch(FetchDescriptor<BodyMetricDefinition>())
        XCTAssertEqual(definitions.map(\.name).sorted(), ["Body Fat %", "Height", "Weight"])

        repository.seedDefaultDefinitionsIfNeeded(profileID: profileID, existingDefinitions: definitions)
        try context.save()
        definitions = try context.fetch(FetchDescriptor<BodyMetricDefinition>())
        XCTAssertEqual(definitions.count, 3)
    }

    func testBodyMetricEntryPersistsWithSnapshotFieldsIntact() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = SwiftDataBodyTrackingRepository(context: context)
        let profileID = UUID()

        let definition = BodyMetricDefinition(profileID: profileID, name: "Weight", unit: "kg", isSystemDefault: true)
        repository.insertDefinition(definition)
        let entry = BodyMetricEntry(
            profileID: profileID, bodyMetricDefinition: definition,
            nameSnapshot: "Weight", unitSnapshot: "kg", value: 78.5,
            recordedAt: .now
        )
        repository.insertEntry(entry)
        XCTAssertTrue(repository.save())

        let fetched = try context.fetch(FetchDescriptor<BodyMetricEntry>())
        XCTAssertEqual(fetched.first?.value, 78.5)
        XCTAssertEqual(fetched.first?.nameSnapshot, "Weight")
    }

    /// Locked product decision: a real (production) profile must never
    /// silently receive an assumed nutrition target. SeedData.seedIfNeeded
    /// is the actual production seeding path (LifeOSApp.LifeOSStore.prepare)
    /// — confirm it creates zero NutritionGoal records, unlike the
    /// DEBUG/-ui-testing fixture which intentionally seeds sample targets.
    func testProductionSeedDataNeverCreatesANutritionGoal() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext

        try SeedData.seedIfNeeded(context: context)

        let goals = try context.fetch(FetchDescriptor<NutritionGoal>())
        XCTAssertTrue(goals.isEmpty, "production seeding must not assume any nutrition target for a new profile")
    }

    // MARK: - V1 fixed-total Meal Template (scope correction), real ModelContainer

    /// Test 1/2/3/4: create a fixed template with a description and macro
    /// totals, persist it, then use it to log a MealEntry with the exact
    /// same totals — no food-item rows involved at all.
    func testFixedTemplatePersistsAndProducesAMealEntryWithIdenticalTotals() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = SwiftDataNutritionRepository(context: context)
        let profileID = UUID()

        let template = MealTemplate(
            profileID: profileID, name: "Coles Lamb Shank + 0.5 cup rice", mealTypeDefault: .dinner,
            details: "Coles Lamb Shank\nRice: 0.5 cup",
            totals: NutritionValue(calories: 873, proteinG: 70, carbsG: 88, fatG: 25)
        )
        repository.insertTemplate(template, foodEntries: [])
        XCTAssertTrue(repository.save())

        let meal = MealEntry(
            profileID: profileID, mealType: .dinner,
            sourceTemplateID: template.id, sourceTemplateNameSnapshot: template.name,
            details: template.details
        )
        repository.insertMeal(meal, foodEntries: [])
        meal.setTotals(template.totals)
        XCTAssertTrue(repository.save())

        let fetchedTemplates = try context.fetch(FetchDescriptor<MealTemplate>())
        let fetchedMeals = try context.fetch(FetchDescriptor<MealEntry>())
        let fetchedFoodEntries = try context.fetch(FetchDescriptor<NutritionFoodEntry>())

        XCTAssertEqual(fetchedTemplates.first?.details, "Coles Lamb Shank\nRice: 0.5 cup")
        XCTAssertEqual(fetchedTemplates.first?.totals.calories, 873)
        XCTAssertEqual(fetchedMeals.first?.totals, fetchedTemplates.first?.totals)
        XCTAssertEqual(fetchedMeals.first?.details, "Coles Lamb Shank\nRice: 0.5 cup")
        XCTAssertTrue(fetchedFoodEntries.isEmpty, "no NutritionFoodEntry rows should be created by the fixed-total flow")
    }

    /// Test 5: editing the template after logging must not change the
    /// already-persisted MealEntry.
    func testEditingAPersistedTemplateDoesNotChangeAPreviouslyLoggedMealEntry() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = SwiftDataNutritionRepository(context: context)
        let profileID = UUID()

        let template = MealTemplate(
            profileID: profileID, name: "Salmon 300g + 0.5 cup rice",
            details: "Salmon: 300g\nRice: 0.5 cup",
            totals: NutritionValue(calories: 976, proteinG: 76, carbsG: 76, fatG: 35)
        )
        repository.insertTemplate(template, foodEntries: [])
        let meal = MealEntry(
            profileID: profileID, mealType: .dinner,
            sourceTemplateID: template.id, sourceTemplateNameSnapshot: template.name, details: template.details
        )
        repository.insertMeal(meal, foodEntries: [])
        meal.setTotals(template.totals)
        try context.save()

        template.totals = NutritionValue(calories: 1000, proteinG: 80, carbsG: 80, fatG: 38)
        try context.save()

        let fetchedMeals = try context.fetch(FetchDescriptor<MealEntry>())
        XCTAssertEqual(fetchedMeals.first?.totals.calories, 976, "the historical entry keeps its own snapshot after the template changes")
    }

    /// Test 6: two different-portion templates for profileID coexist as
    /// independent rows.
    func testTwoPortionTemplatesPersistAsIndependentRows() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let repository = SwiftDataNutritionRepository(context: context)
        let profileID = UUID()

        let halfCup = MealTemplate(profileID: profileID, name: "Lamb Shank + 0.5 cup rice", totals: NutritionValue(carbsG: 88))
        let fullCup = MealTemplate(profileID: profileID, name: "Lamb Shank + 1 cup rice", totals: NutritionValue(carbsG: 126))
        repository.insertTemplate(halfCup, foodEntries: [])
        repository.insertTemplate(fullCup, foodEntries: [])
        XCTAssertTrue(repository.save())

        let fetched = try context.fetch(FetchDescriptor<MealTemplate>())
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(Set(fetched.map(\.totals.carbsG)), [88, 126])
    }
}
