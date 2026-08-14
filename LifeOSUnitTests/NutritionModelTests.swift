import XCTest
@testable import LifeOS

/// NUTRITION_INTEGRATION_PLAN_V1.md Phase 1: construction and behavior
/// tests for the new, still-inert Nutrition/Body Tracking models. Nothing
/// here exercises a Repository, Engine, or View — those are later phases.
final class NutritionModelTests: XCTestCase {
    func testNutritionValueSumAddsCaloriesAndMacrosAcrossEntries() {
        let eggs = NutritionValue(calories: 234, proteinG: 18, carbsG: 2, fatG: 16)
        let oats = NutritionValue(calories: 228, proteinG: 8, carbsG: 40, fatG: 4)

        let total = NutritionValue.sum([eggs, oats])

        XCTAssertEqual(total.calories, 462)
        XCTAssertEqual(total.proteinG, 26)
        XCTAssertEqual(total.carbsG, 42)
        XCTAssertEqual(total.fatG, 20)
    }

    func testNutritionValueSumOfEmptyArrayIsZero() {
        XCTAssertEqual(NutritionValue.sum([]), .zero)
    }

    func testNutritionFoodEntryDefaultsToOneServingAndZeroNutrition() {
        let entry = NutritionFoodEntry(name: "Oats")
        XCTAssertEqual(entry.servingSize, 1)
        XCTAssertEqual(entry.servingUnit, "serving")
        XCTAssertEqual(entry.nutrition, .zero)
        XCTAssertNil(entry.mealEntry)
        XCTAssertNil(entry.mealTemplate)
        XCTAssertNil(entry.externalSourceID, "barcode/AI lookup extension point unused in v1")
    }

    func testMealEntryStartsWithZeroTotalsAndNoEditHistory() {
        let profileID = UUID()
        let meal = MealEntry(profileID: profileID, mealType: .breakfast)

        XCTAssertEqual(meal.profileID, profileID)
        XCTAssertEqual(meal.mealType, .breakfast)
        XCTAssertEqual(meal.totals, .zero)
        XCTAssertNil(meal.lastEditedAt)
        XCTAssertEqual(meal.editCount, 0)
        XCTAssertNil(meal.sourceTemplateID)
        XCTAssertEqual(meal.createdAt, meal.updatedAt)
    }

    func testMealEntryRecomputeTotalsSumsFoodEntriesAndTracksTheEdit() {
        let meal = MealEntry(profileID: UUID(), mealType: .lunch)
        let foods = [
            NutritionFoodEntry(name: "Chicken", nutrition: NutritionValue(calories: 300, proteinG: 40)),
            NutritionFoodEntry(name: "Rice", nutrition: NutritionValue(calories: 200, carbsG: 45))
        ]
        let editTime = TestFixtures.date(2026, 1, 5, hour: 12)

        meal.recomputeTotals(from: foods, editedAt: editTime)

        XCTAssertEqual(meal.totals.calories, 500)
        XCTAssertEqual(meal.totals.proteinG, 40)
        XCTAssertEqual(meal.totals.carbsG, 45)
        XCTAssertEqual(meal.lastEditedAt, editTime)
        XCTAssertEqual(meal.updatedAt, editTime)
        XCTAssertEqual(meal.editCount, 1)
    }

    func testMealEntryEditCountAccumulatesAcrossMultipleCorrections() {
        let meal = MealEntry(profileID: UUID(), mealType: .dinner)
        meal.recomputeTotals(from: [])
        meal.recomputeTotals(from: [NutritionFoodEntry(name: "Salmon", nutrition: NutritionValue(calories: 400))])

        XCTAssertEqual(meal.editCount, 2)
        XCTAssertEqual(meal.totals.calories, 400)
    }

    func testMealEntrySourceTemplateSnapshotSurvivesIndependentlyOfFoodEdits() {
        let templateID = UUID()
        let meal = MealEntry(
            profileID: UUID(), mealType: .breakfast,
            sourceTemplateID: templateID, sourceTemplateNameSnapshot: "My Protein Breakfast"
        )

        // Editing the meal's foods afterward must not rewrite provenance.
        meal.recomputeTotals(from: [NutritionFoodEntry(name: "Extra banana", nutrition: NutritionValue(calories: 100))])

        XCTAssertEqual(meal.sourceTemplateID, templateID)
        XCTAssertEqual(meal.sourceTemplateNameSnapshot, "My Protein Breakfast")
    }

    func testMealTemplateRecordUseIncrementsCountAndStampsLastUsed() {
        let template = MealTemplate(profileID: UUID(), name: "My Protein Breakfast", mealTypeDefault: .breakfast)
        XCTAssertEqual(template.useCount, 0)
        XCTAssertNil(template.lastUsedAt)
        XCTAssertFalse(template.isFavorite)

        let usedAt = TestFixtures.date(2026, 1, 12, hour: 7, minute: 40)
        template.recordUse(at: usedAt)

        XCTAssertEqual(template.useCount, 1)
        XCTAssertEqual(template.lastUsedAt, usedAt)
        XCTAssertEqual(template.updatedAt, usedAt)

        template.recordUse(at: TestFixtures.date(2026, 1, 13, hour: 7, minute: 40))
        XCTAssertEqual(template.useCount, 2)
    }

    // MARK: - V1 fixed-total Meal Template (scope correction)

    /// Test 1 + 2: a template is one fixed, user-entered set of totals.
    func testCreatingAFixedMealTemplateStoresUserEnteredMacroTotals() {
        let template = MealTemplate(
            profileID: UUID(), name: "Coles Lamb Shank + 0.5 cup rice", mealTypeDefault: .dinner,
            details: "Coles Lamb Shank\nRice: 0.5 cup",
            totals: NutritionValue(calories: 873, proteinG: 70, carbsG: 88, fatG: 25)
        )

        XCTAssertEqual(template.name, "Coles Lamb Shank + 0.5 cup rice")
        XCTAssertEqual(template.totals.calories, 873)
        XCTAssertEqual(template.totals.proteinG, 70)
        XCTAssertEqual(template.totals.carbsG, 88)
        XCTAssertEqual(template.totals.fatG, 25)
    }

    /// Test 3: descriptive portion text is a plain string, never parsed.
    func testMealTemplateDetailsHoldsFreeformPortionText() {
        let template = MealTemplate(
            profileID: UUID(), name: "Salmon 300g + 0.5 cup rice",
            details: "Salmon: 300g\nRice: 0.5 cup",
            totals: NutritionValue(calories: 976, proteinG: 76, carbsG: 76, fatG: 35)
        )

        XCTAssertEqual(template.details, "Salmon: 300g\nRice: 0.5 cup")
    }

    /// Test 8: no automatic nutrition calculation — a template's totals are
    /// exactly what was passed in, never derived from `details`.
    func testMealTemplateNeverComputesTotalsFromDetails() {
        let template = MealTemplate(
            profileID: UUID(), name: "Anything",
            details: "Rice: 1 cup, Chicken: 300g, Broccoli: 200g",
            totals: NutritionValue(calories: 500, proteinG: 40, carbsG: 50, fatG: 10)
        )
        // The totals are whatever was supplied — LifeOS has no ingredient
        // database and performs no computation from the description text.
        XCTAssertEqual(template.totals, NutritionValue(calories: 500, proteinG: 40, carbsG: 50, fatG: 10))
    }

    /// Test 4: using a template creates a MealEntry with the same totals —
    /// a plain copy, no scaling.
    func testMealEntryCanBeGivenATemplatesSnapshotDirectly() {
        let template = MealTemplate(
            profileID: UUID(), name: "Lamb Shank + 0.5 cup rice",
            details: "Coles Lamb Shank\nRice: 0.5 cup",
            totals: NutritionValue(calories: 873, proteinG: 70, carbsG: 88, fatG: 25)
        )

        let meal = MealEntry(
            profileID: template.profileID, mealType: .dinner,
            sourceTemplateID: template.id, sourceTemplateNameSnapshot: template.name,
            details: template.details
        )
        meal.setTotals(template.totals)

        XCTAssertEqual(meal.totals, template.totals)
        XCTAssertEqual(meal.details, template.details)
        XCTAssertEqual(meal.sourceTemplateID, template.id)
    }

    /// Test 5: editing a template afterward must not rewrite a MealEntry
    /// that was already logged from it — the entry holds its own copy.
    func testHistoricalMealEntryUnaffectedByLaterTemplateEdit() {
        let template = MealTemplate(
            profileID: UUID(), name: "Lamb Shank + 0.5 cup rice",
            details: "Coles Lamb Shank\nRice: 0.5 cup",
            totals: NutritionValue(calories: 873, proteinG: 70, carbsG: 88, fatG: 25)
        )
        let meal = MealEntry(
            profileID: template.profileID, mealType: .dinner,
            sourceTemplateID: template.id, sourceTemplateNameSnapshot: template.name,
            details: template.details
        )
        meal.setTotals(template.totals)

        // The template is edited later (e.g. the user corrects a typo'd value).
        template.totals = NutritionValue(calories: 900, proteinG: 72, carbsG: 90, fatG: 26)
        template.details = "Coles Lamb Shank\nRice: 0.6 cup"

        XCTAssertEqual(meal.totals, NutritionValue(calories: 873, proteinG: 70, carbsG: 88, fatG: 25), "the logged meal keeps its own snapshot")
        XCTAssertEqual(meal.details, "Coles Lamb Shank\nRice: 0.5 cup")
    }

    /// Test 6: a different portion is simply a different, separate
    /// template — LifeOS never derives/scales one from another.
    func testTwoDifferentPortionTemplatesCoexistIndependently() {
        let profileID = UUID()
        let halfCup = MealTemplate(
            profileID: profileID, name: "Coles Lamb Shank + 0.5 cup rice",
            details: "Coles Lamb Shank\nRice: 0.5 cup",
            totals: NutritionValue(calories: 873, proteinG: 70, carbsG: 88, fatG: 25)
        )
        let fullCup = MealTemplate(
            profileID: profileID, name: "Coles Lamb Shank + 1 cup rice",
            details: "Coles Lamb Shank\nRice: 1 cup",
            totals: NutritionValue(calories: 1046, proteinG: 70, carbsG: 126, fatG: 25)
        )

        XCTAssertNotEqual(halfCup.id, fullCup.id)
        XCTAssertEqual(halfCup.totals.carbsG, 88)
        XCTAssertEqual(fullCup.totals.carbsG, 126)
        // Confirms fullCup's totals were supplied directly, not derived by
        // doubling halfCup's rice-attributable carbs or any other scaling.
        XCTAssertNotEqual(fullCup.totals.carbsG, halfCup.totals.carbsG * 2)
    }

    /// Test 7: a Quick Macro entry (name + totals, no food breakdown) can
    /// become a reusable template.
    func testQuickMacroMealCanBeSavedAsATemplate() {
        let quickMeal = MealEntry(
            profileID: UUID(), mealType: .snack, details: "Something I ate"
        )
        quickMeal.setTotals(NutritionValue(calories: 976, proteinG: 76, carbsG: 76, fatG: 35))

        let template = MealTemplate(
            profileID: quickMeal.profileID, name: "Something I ate", mealTypeDefault: quickMeal.mealType,
            details: quickMeal.details, totals: quickMeal.totals
        )

        XCTAssertEqual(template.totals, quickMeal.totals)
        XCTAssertEqual(template.details, "Something I ate")
    }

    func testWaterEntryStoresAmountAndTimestamps() {
        let recordedAt = TestFixtures.date(2026, 1, 5, hour: 9)
        let entry = WaterEntry(profileID: UUID(), recordedAt: recordedAt, amountML: 500)

        XCTAssertEqual(entry.amountML, 500)
        XCTAssertEqual(entry.recordedAt, recordedAt)
        XCTAssertEqual(entry.createdAt, entry.updatedAt)
    }

    /// Locked product decision: LifeOS never assumes or prescribes a
    /// nutrition target. A freshly created NutritionGoal must start with
    /// every field nil, not a suggested/default value.
    func testNutritionGoalHasNoAssumedDefaultTargets() {
        let goal = NutritionGoal(profileID: UUID())

        XCTAssertNil(goal.calorieTarget)
        XCTAssertNil(goal.proteinTargetG)
        XCTAssertNil(goal.carbsTargetG)
        XCTAssertNil(goal.fatTargetG)
        XCTAssertNil(goal.waterTargetML)
    }

    func testNutritionGoalSupportsSettingOnlyASubsetOfTargets() {
        // User B from the product brief: only Protein and Water configured.
        let goal = NutritionGoal(profileID: UUID(), proteinTargetG: 100, waterTargetML: 2000)

        XCTAssertEqual(goal.proteinTargetG, 100)
        XCTAssertEqual(goal.waterTargetML, 2000)
        XCTAssertNil(goal.calorieTarget)
        XCTAssertNil(goal.carbsTargetG)
        XCTAssertNil(goal.fatTargetG)
    }

    func testBodyMetricDefinitionConstructsWithUnitAndSystemDefaultFlag() {
        let profileID = UUID()
        let definition = BodyMetricDefinition(profileID: profileID, name: "Weight", unit: "kg", isSystemDefault: true, sortOrder: 0)

        XCTAssertEqual(definition.profileID, profileID)
        XCTAssertEqual(definition.name, "Weight")
        XCTAssertEqual(definition.unit, "kg")
        XCTAssertTrue(definition.isSystemDefault)
    }

    func testBodyMetricEntrySnapshotsSurviveWithoutALiveDefinitionLink() {
        let profileID = UUID()
        // No bodyMetricDefinition link at all — the entry must still be
        // fully interpretable from its own snapshot fields alone, mirroring
        // MeasurementEntry's rationale (DOMAIN_MODEL_V2_PROPOSAL.md §2.8).
        let entry = BodyMetricEntry(
            profileID: profileID, bodyMetricDefinition: nil,
            nameSnapshot: "Weight", unitSnapshot: "kg", value: 78.5
        )

        XCTAssertNil(entry.bodyMetricDefinition)
        XCTAssertEqual(entry.nameSnapshot, "Weight")
        XCTAssertEqual(entry.unitSnapshot, "kg")
        XCTAssertEqual(entry.value, 78.5)
    }

    func testResultMeasureCanLinkToANutritionMetricOrABodyMetricDefinitionButDefaultsToNeither() {
        let plainMeasure = ResultMeasure(goal: nil, name: "Manual thing")
        XCTAssertNil(plainMeasure.linkedNutritionMetric)
        XCTAssertNil(plainMeasure.linkedBodyMetricDefinitionID)

        let nutritionLinked = ResultMeasure(goal: nil, name: "Protein", linkedNutritionMetric: .protein)
        XCTAssertEqual(nutritionLinked.linkedNutritionMetric, .protein)
        XCTAssertEqual(nutritionLinked.linkedNutritionMetricRaw, "protein")

        let definitionID = UUID()
        let bodyLinked = ResultMeasure(goal: nil, name: "Weight", linkedBodyMetricDefinitionID: definitionID)
        XCTAssertEqual(bodyLinked.linkedBodyMetricDefinitionID, definitionID)
    }

    func testBodyMetricEntryCanLinkToALiveDefinition() {
        let definition = BodyMetricDefinition(profileID: UUID(), name: "Body Fat %", unit: "%")
        let entry = BodyMetricEntry(
            profileID: definition.profileID, bodyMetricDefinition: definition,
            nameSnapshot: "Body Fat %", unitSnapshot: "%", value: 18.2
        )

        XCTAssertEqual(entry.bodyMetricDefinition?.id, definition.id)
    }
}
