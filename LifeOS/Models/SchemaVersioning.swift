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

import SwiftData

enum LifeOSSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    /// Release contract used by migration tests. Never change this value or
    /// roster after V1 ships; add a new versioned schema instead.
    static let releaseFingerprint = "LifeOSSchemaV1:1.0.0:Profile,SavedCategoryTemplate,AppCategory,Goal,GoalAreaContribution,ResultMeasure,ResultEntry,Activity,CalendarItem,ActivitySession,FoodEntry,WeightEntry,SportEntry"

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
            SportEntry.self
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
