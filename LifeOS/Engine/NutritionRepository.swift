//
//  NutritionRepository.swift
//  LifeOS
//
//  NUTRITION_MODULE_DESIGN_V1.md / NUTRITION_INTEGRATION_PLAN_V1.md: the
//  persistence boundary for MealEntry, MealTemplate, NutritionFoodEntry,
//  WaterEntry, and NutritionGoal, mirroring CalendarRepository/
//  MeasurementRepository's shape.
//
//  Ownership invariant: a NutritionFoodEntry belongs to exactly one of
//  MealEntry or MealTemplate, never both, never neither once inserted. The
//  model itself permits both/neither (two plain optional back-references,
//  matching this codebase's no-@Relationship convention), so insertMeal/
//  insertTemplate enforce the invariant here by assigning the correct
//  parent and clearing the other, regardless of what the caller had set.
//
//  Deletion resolves children itself (a FetchDescriptor scoped to the
//  parent's id) instead of requiring the caller to supply the complete
//  child array, so a caller with a stale/partial list can never orphan
//  NutritionFoodEntry rows.
//

import Foundation
import SwiftData

protocol NutritionRepository {
    var hasChanges: Bool { get }

    /// Inserts `meal` and `foodEntries`, assigning each entry's `mealEntry`
    /// to `meal` and clearing `mealTemplate` — the ownership invariant is
    /// enforced here, not left to the caller.
    func insertMeal(_ meal: MealEntry, foodEntries: [NutritionFoodEntry])
    /// Explicit, separate from editing — removes the meal and every
    /// NutritionFoodEntry that belongs to it from history entirely (§4a:
    /// deletion is distinct from correction). Resolves those children
    /// itself; the caller does not supply them.
    func deleteMeal(_ meal: MealEntry) throws

    /// Inserts `template` and `foodEntries`, assigning each entry's
    /// `mealTemplate` to `template` and clearing `mealEntry`.
    func insertTemplate(_ template: MealTemplate, foodEntries: [NutritionFoodEntry])
    func deleteTemplate(_ template: MealTemplate) throws

    func insertWaterEntry(_ entry: WaterEntry)
    func deleteWaterEntry(_ entry: WaterEntry)

    func insertGoal(_ goal: NutritionGoal)

    @discardableResult func save() -> Bool
}

@MainActor
final class SwiftDataNutritionRepository: NutritionRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    var hasChanges: Bool { context.hasChanges }

    func insertMeal(_ meal: MealEntry, foodEntries: [NutritionFoodEntry]) {
        context.insert(meal)
        for entry in foodEntries {
            entry.mealEntry = meal
            entry.mealTemplate = nil
            context.insert(entry)
        }
    }

    func deleteMeal(_ meal: MealEntry) throws {
        let mealID = meal.id
        let children = try context.fetch(
            FetchDescriptor<NutritionFoodEntry>(predicate: #Predicate { $0.mealEntry?.id == mealID })
        )
        for child in children { context.delete(child) }
        context.delete(meal)
    }

    func insertTemplate(_ template: MealTemplate, foodEntries: [NutritionFoodEntry]) {
        context.insert(template)
        for entry in foodEntries {
            entry.mealTemplate = template
            entry.mealEntry = nil
            context.insert(entry)
        }
    }

    func deleteTemplate(_ template: MealTemplate) throws {
        let templateID = template.id
        let children = try context.fetch(
            FetchDescriptor<NutritionFoodEntry>(predicate: #Predicate { $0.mealTemplate?.id == templateID })
        )
        for child in children { context.delete(child) }
        context.delete(template)
    }

    func insertWaterEntry(_ entry: WaterEntry) { context.insert(entry) }
    func deleteWaterEntry(_ entry: WaterEntry) { context.delete(entry) }

    func insertGoal(_ goal: NutritionGoal) { context.insert(goal) }

    @discardableResult
    func save() -> Bool { context.saveOrReport() }
}
