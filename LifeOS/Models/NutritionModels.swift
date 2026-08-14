//
//  NutritionModels.swift
//  LifeOS
//
//  Nutrition module v1, per NUTRITION_MODULE_DESIGN_V1.md. A specialised,
//  standalone module — deliberately not modeled as an Activity or synthetic
//  Activity, and not sharing MeasurementDefinition/MeasurementEntry, which
//  are Activity-scoped (see that file's design rationale §4). All types
//  here are Profile-scoped instead, matching this module's own cadence.
//
//  Phase 1 scope: models + repositories + tests only. Views, the old
//  FoodTrackerView/WeightTrackerView, and Profile's legacy nutrition/weight
//  goal fields are untouched — see NUTRITION_INTEGRATION_PLAN_V1.md §3/§5.
//  NutritionFoodEntry is named to avoid colliding with the existing
//  FoodEntry in Models.swift, which this module is planned to replace in a
//  later phase.
//

import Foundation
import SwiftData

// MARK: - NutritionValue

/// Macro/calorie totals. Plain value type, not a @Model, so it can be
/// stored inline (MealEntry.totals) and reused for future AI/photo
/// estimation without depending on FoodEntry's identity.
struct NutritionValue: Codable, Equatable {
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    // Future-proofing per NUTRITION_MODULE_DESIGN_V1.md §4 — unused in v1.
    var fiberG: Double?
    var sugarG: Double?
    var sodiumMg: Double?

    init(
        calories: Double = 0, proteinG: Double = 0, carbsG: Double = 0, fatG: Double = 0,
        fiberG: Double? = nil, sugarG: Double? = nil, sodiumMg: Double? = nil
    ) {
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.sodiumMg = sodiumMg
    }

    static let zero = NutritionValue()

    static func sum(_ values: [NutritionValue]) -> NutritionValue {
        values.reduce(.zero) { total, value in
            NutritionValue(
                calories: total.calories + value.calories,
                proteinG: total.proteinG + value.proteinG,
                carbsG: total.carbsG + value.carbsG,
                fatG: total.fatG + value.fatG
            )
        }
    }
}

// MARK: - NutritionFoodEntry (legacy — not used by the current UI)
//
// V1 scope correction (meal template simplification): a MealTemplate/
// MealEntry is now one fixed, user-entered total (see their `totals`/
// `details` fields) rather than a sum of individually-tracked foods. This
// type is kept in the schema — not removed — to avoid a migration/schema
// risk for a feature that was never fully wired into any shipped flow, but
// no current View creates, edits, or reads NutritionFoodEntry rows. The
// repository methods that accept a `foodEntries` array still exist and
// work (ownership invariant, safe deletion), they're simply always called
// with `[]` now. This is explicitly NOT the "Saved Food" concept ruled out
// for V1: entries here were always per-meal, user-entered, and never
// shared/reused across templates or scaled by serving size.

@Model
final class NutritionFoodEntry {
    var id: UUID
    var name: String
    var servingSize: Double
    var servingUnit: String
    var nutrition: NutritionValue
    var mealEntry: MealEntry?
    var mealTemplate: MealTemplate?
    // Extension point for future barcode/DB lookup — nil in v1, per
    // NUTRITION_MODULE_DESIGN_V1.md §6, no schema change needed later.
    var externalSourceID: String?
    var externalSourceType: String?

    init(
        name: String, servingSize: Double = 1, servingUnit: String = "serving",
        nutrition: NutritionValue = .zero, mealEntry: MealEntry? = nil, mealTemplate: MealTemplate? = nil,
        externalSourceID: String? = nil, externalSourceType: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.servingSize = servingSize
        self.servingUnit = servingUnit
        self.nutrition = nutrition
        self.mealEntry = mealEntry
        self.mealTemplate = mealTemplate
        self.externalSourceID = externalSourceID
        self.externalSourceType = externalSourceType
    }
}

// MARK: - MealTemplate

/// V1 locked decision: a MealTemplate is ONE complete meal configuration
/// with fixed, user-entered nutrition totals — not a collection of
/// individually-tracked foods. `details` is free-text ("Coles Lamb Shank /
/// Rice: 0.5 cup"), and `totals` is exactly what the user typed in, never
/// computed/derived from ingredients or scaled from another template. A
/// different portion (e.g. 1 cup rice instead of 0.5) is simply a different
/// MealTemplate — LifeOS never multiplies or scales one template into
/// another. See "Fix User-Defined Nutrition Targets" / meal template scope
/// correction for the full rationale.
@Model
final class MealTemplate {
    var id: UUID
    var profileID: UUID
    var name: String
    var mealTypeDefaultRaw: String?
    /// Free-text description of what the meal is, e.g. "Coles Lamb Shank\nRice: 0.5 cup".
    /// Never parsed or used for calculation — display only.
    var details: String
    /// User-entered fixed totals for this template — not derived from any
    /// food/ingredient breakdown.
    var totals: NutritionValue
    var isFavorite: Bool
    var useCount: Int
    var lastUsedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var mealTypeDefault: MealType? {
        get { mealTypeDefaultRaw.flatMap { MealType(rawValue: $0) } }
        set { mealTypeDefaultRaw = newValue?.rawValue }
    }

    init(
        profileID: UUID, name: String, mealTypeDefault: MealType? = nil,
        details: String = "", totals: NutritionValue = .zero,
        isFavorite: Bool = false, useCount: Int = 0, lastUsedAt: Date? = nil, createdAt: Date = .now
    ) {
        self.id = UUID()
        self.profileID = profileID
        self.name = name
        self.mealTypeDefaultRaw = mealTypeDefault?.rawValue
        self.details = details
        self.totals = totals
        self.isFavorite = isFavorite
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    /// Called each time this template is used to log a meal — the usage
    /// signal that "relevance" sorting (favorite first, then most-used/
    /// most-recent) is built on.
    func recordUse(at date: Date = .now) {
        useCount += 1
        lastUsedAt = date
        updatedAt = date
    }
}

// MARK: - MealEntry

/// The historical record of one real-world meal. Editable in place for
/// normal user corrections (mealType, recordedAt, food entries) — not
/// immutable-once-created. id/profileID/createdAt/sourceTemplate* never
/// change after creation. See NUTRITION_MODULE_DESIGN_V1.md §4a.
@Model
final class MealEntry {
    var id: UUID
    var profileID: UUID
    var mealTypeRaw: String
    var recordedAt: Date
    var createdAt: Date
    var updatedAt: Date
    var sourceTemplateID: UUID?
    var sourceTemplateNameSnapshot: String?
    /// Free-text description of what was eaten, e.g. "Coles Lamb Shank /
    /// Rice: 0.5 cup" — copied from the source MealTemplate's `details`
    /// when logged from a template, or typed directly for a manual/quick
    /// entry. Display only, never parsed.
    var details: String
    /// User-entered fixed totals — set directly (see `setTotals`), or via
    /// the legacy `recomputeTotals(from:)` food-entry sum. Never hand-edited
    /// outside those two methods.
    var totals: NutritionValue
    var lastEditedAt: Date?
    var editCount: Int

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    init(
        profileID: UUID, mealType: MealType, recordedAt: Date = .now,
        sourceTemplateID: UUID? = nil, sourceTemplateNameSnapshot: String? = nil,
        details: String = "", totals: NutritionValue = .zero
    ) {
        self.id = UUID()
        self.profileID = profileID
        self.mealTypeRaw = mealType.rawValue
        self.recordedAt = recordedAt
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
        self.sourceTemplateID = sourceTemplateID
        self.sourceTemplateNameSnapshot = sourceTemplateNameSnapshot
        self.details = details
        self.totals = totals
        self.lastEditedAt = nil
        self.editCount = 0
    }

    /// V1 fixed-total flow: sets `totals` directly to what the user typed
    /// and records the edit — no food-item breakdown, no calculation.
    func setTotals(_ newTotals: NutritionValue, editedAt: Date = .now) {
        totals = newTotals
        updatedAt = editedAt
        lastEditedAt = editedAt
        editCount += 1
    }

    /// Legacy path from the earlier per-food-item design: sums the given
    /// food entries into `totals`. Not used by the current (V1 fixed-total)
    /// UI, kept only because NutritionFoodEntry itself is kept (see that
    /// type's doc comment) and existing callers/tests still exercise it.
    func recomputeTotals(from foodEntries: [NutritionFoodEntry], editedAt: Date = .now) {
        totals = NutritionValue.sum(foodEntries.map(\.nutrition))
        updatedAt = editedAt
        lastEditedAt = editedAt
        editCount += 1
    }
}

// MARK: - WaterEntry

@Model
final class WaterEntry {
    var id: UUID
    var profileID: UUID
    var recordedAt: Date
    var amountML: Double
    var createdAt: Date
    var updatedAt: Date

    init(profileID: UUID, recordedAt: Date = .now, amountML: Double) {
        self.id = UUID()
        self.profileID = profileID
        self.recordedAt = recordedAt
        self.amountML = amountML
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
    }
}

// MARK: - NutritionGoal

/// User-configured daily Nutrition targets. LifeOS never assumes or
/// prescribes a value here — every field is optional, `nil` by default,
/// and stays `nil` until the user explicitly sets it in Nutrition Targets.
/// No age/sex/height/weight/activity-level intake and no BMR-style
/// calculation ever populates these — see NUTRITION_MODULE_DESIGN_V1.md's
/// "locked product decision" that targets are entirely user-declared.
@Model
final class NutritionGoal {
    var id: UUID
    var profileID: UUID
    var calorieTarget: Double?
    var proteinTargetG: Double?
    var carbsTargetG: Double?
    var fatTargetG: Double?
    var waterTargetML: Double?
    var createdAt: Date
    var updatedAt: Date

    init(
        profileID: UUID, calorieTarget: Double? = nil, proteinTargetG: Double? = nil,
        carbsTargetG: Double? = nil, fatTargetG: Double? = nil, waterTargetML: Double? = nil
    ) {
        self.id = UUID()
        self.profileID = profileID
        self.calorieTarget = calorieTarget
        self.proteinTargetG = proteinTargetG
        self.carbsTargetG = carbsTargetG
        self.fatTargetG = fatTargetG
        self.waterTargetML = waterTargetML
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
    }
}

// MARK: - Body Tracking (BodyMetricDefinition / BodyMetricEntry)
//
// Data-driven, Profile-scoped sibling of MeasurementDefinition/
// MeasurementEntry — deliberately not that type, since MeasurementDefinition
// is owned by an Activity and body metrics (Weight/Height/Body Fat %, plus
// user-added custom metrics) are not activity-scoped. Reuses that pattern's
// snapshot approach so entries stay interpretable if a definition is later
// renamed or deleted.

@Model
final class BodyMetricDefinition {
    var id: UUID
    var profileID: UUID
    var name: String
    var unit: String
    var isSystemDefault: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        profileID: UUID, name: String, unit: String,
        isSystemDefault: Bool = false, sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.profileID = profileID
        self.name = name
        self.unit = unit
        self.isSystemDefault = isSystemDefault
        self.sortOrder = sortOrder
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
    }
}

@Model
final class BodyMetricEntry {
    var id: UUID
    var profileID: UUID
    var bodyMetricDefinition: BodyMetricDefinition?
    var nameSnapshot: String
    var unitSnapshot: String
    var value: Double
    var recordedAt: Date
    var createdAt: Date
    var updatedAt: Date

    init(
        profileID: UUID, bodyMetricDefinition: BodyMetricDefinition?,
        nameSnapshot: String, unitSnapshot: String, value: Double, recordedAt: Date = .now
    ) {
        self.id = UUID()
        self.profileID = profileID
        self.bodyMetricDefinition = bodyMetricDefinition
        self.nameSnapshot = nameSnapshot
        self.unitSnapshot = unitSnapshot
        self.value = value
        self.recordedAt = recordedAt
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
    }
}
