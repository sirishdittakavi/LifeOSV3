//
//  BodyTrackingRepository.swift
//  LifeOS
//
//  NUTRITION_MODULE_DESIGN_V1.md / NUTRITION_INTEGRATION_PLAN_V1.md Phase 1:
//  the persistence boundary for BodyMetricDefinition/BodyMetricEntry,
//  mirroring MeasurementRepository's shape. Not yet consumed by any View or
//  ViewModel — this is foundation only.
//

import Foundation
import SwiftData

protocol BodyTrackingRepository {
    var hasChanges: Bool { get }

    func insertDefinition(_ definition: BodyMetricDefinition)
    func insertEntry(_ entry: BodyMetricEntry)
    func deleteEntry(_ entry: BodyMetricEntry)

    /// Seeds Weight/Height/Body Fat % as isSystemDefault definitions for a
    /// profile that has none yet, so the data-driven model is visible in
    /// the UI without hardcoding these three into any View
    /// (NUTRITION_MODULE_DESIGN_V1.md §8 note 3). No-ops if the profile
    /// already has any BodyMetricDefinition.
    func seedDefaultDefinitionsIfNeeded(profileID: UUID, existingDefinitions: [BodyMetricDefinition])

    @discardableResult func save() -> Bool
}

@MainActor
final class SwiftDataBodyTrackingRepository: BodyTrackingRepository {
    private let context: ModelContext

    /// (name, unit) — order also seeds sortOrder.
    static let defaultMetrics: [(name: String, unit: String)] = [
        ("Weight", "kg"),
        ("Height", "cm"),
        ("Body Fat %", "%")
    ]

    init(context: ModelContext) {
        self.context = context
    }

    var hasChanges: Bool { context.hasChanges }

    func insertDefinition(_ definition: BodyMetricDefinition) { context.insert(definition) }
    func insertEntry(_ entry: BodyMetricEntry) { context.insert(entry) }
    func deleteEntry(_ entry: BodyMetricEntry) { context.delete(entry) }

    func seedDefaultDefinitionsIfNeeded(profileID: UUID, existingDefinitions: [BodyMetricDefinition]) {
        let hasAny = existingDefinitions.contains { $0.profileID == profileID }
        guard !hasAny else { return }

        for (index, metric) in Self.defaultMetrics.enumerated() {
            let definition = BodyMetricDefinition(
                profileID: profileID, name: metric.name, unit: metric.unit,
                isSystemDefault: true, sortOrder: index
            )
            context.insert(definition)
        }
    }

    @discardableResult
    func save() -> Bool { context.saveOrReport() }
}
