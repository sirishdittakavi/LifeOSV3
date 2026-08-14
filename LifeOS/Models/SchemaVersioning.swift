//
//  SchemaVersioning.swift
//  LifeOS
//
//  Version 1 is the persistence contract established before the first
//  public release. Every app and component-test container must use this
//  schema and migration plan rather than constructing an independent list.
//
//  Before an incompatible @Model change ships:
//  1. Preserve the released V1 model definitions as immutable historical
//     types. Do not edit a released schema to describe the new model shape.
//  2. Define LifeOSSchemaV2 with the new types.
//  3. Add V2 to LifeOSMigrationPlan.schemas and a tested migration stage.
//  4. Test a real copy of a V1 store before increasing the app version.
//
//  Merely adding V2 while changing the types referenced by V1 would not
//  preserve history. The component tests lock the current model roster and
//  exercise container creation through this plan, but a stored-data fixture
//  is still required for every future migration.
//
//  Exception (IMPLEMENTATION_PHASE_PLAN_V2.md §0): LifeOS has no production
//  release yet, so "never change the roster after V1 ships" doesn't apply —
//  there is nothing released to preserve compatibility with. Phase 1 adds
//  Relationship/MeasurementDefinition/MeasurementEntry directly to this
//  roster rather than through a versioned V2 migration. This exception ends
//  the moment LifeOS actually ships to real users; all guidance above this
//  note applies again in full from that point on.
//
//  Same exception covers the Nutrition module additions below
//  (NUTRITION_MODULE_DESIGN_V1.md / NUTRITION_INTEGRATION_PLAN_V1.md Phase
//  1). FoodEntry/WeightEntry stay in the roster for now — their Views
//  (FoodTrackerView/WeightTrackerView) are untouched in this phase; removal
//  is a later phase per the integration plan §3/§5.
//

import SwiftData

enum LifeOSSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    /// Release contract used by migration tests. Never change this value or
    /// roster after V1 ships; add a new versioned schema instead.
    /// (Pre-release exception above still applies as of Phase 1.)
    static let releaseFingerprint = "LifeOSSchemaV1:1.0.0:Profile,SavedCategoryTemplate,AppCategory,Goal,GoalAreaContribution,ResultMeasure,ResultEntry,Activity,CalendarItem,ActivitySession,FoodEntry,WeightEntry,SportEntry,Relationship,MeasurementDefinition,MeasurementEntry,NutritionGoal,MealTemplate,MealEntry,NutritionFoodEntry,WaterEntry,BodyMetricDefinition,BodyMetricEntry"

    static var models: [any PersistentModel.Type] {
        [
            Profile.self,
            SavedCategoryTemplate.self,
            AppCategory.self,
            Goal.self,
            GoalAreaContribution.self,
            ResultMeasure.self,
            ResultEntry.self,
            Activity.self,
            CalendarItem.self,
            ActivitySession.self,
            FoodEntry.self,
            WeightEntry.self,
            SportEntry.self,
            Relationship.self,
            MeasurementDefinition.self,
            MeasurementEntry.self,
            NutritionGoal.self,
            MealTemplate.self,
            MealEntry.self,
            NutritionFoodEntry.self,
            WaterEntry.self,
            BodyMetricDefinition.self,
            BodyMetricEntry.self
        ]
    }
}

enum LifeOSMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LifeOSSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum LifeOSDataStore {
    static var schema: Schema { Schema(versionedSchema: LifeOSSchemaV1.self) }

    static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let schema = self.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: schema,
            migrationPlan: LifeOSMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
