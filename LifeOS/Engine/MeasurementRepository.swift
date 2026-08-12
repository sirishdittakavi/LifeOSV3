//
//  MeasurementRepository.swift
//  LifeOS
//
//  Refactor.md Phase 2: the persistence boundary for MeasurementDefinition
//  and MeasurementEntry, mirroring CalendarRepository's shape. Not yet
//  consumed by any View or ViewModel — this is foundation only.
//

import Foundation
import SwiftData

protocol MeasurementRepository {
    var hasChanges: Bool { get }
    func insertDefinition(_ definition: MeasurementDefinition)
    func insertEntry(_ entry: MeasurementEntry)
    @discardableResult func save() -> Bool
}

@MainActor
final class SwiftDataMeasurementRepository: MeasurementRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    var hasChanges: Bool { context.hasChanges }

    func insertDefinition(_ definition: MeasurementDefinition) {
        context.insert(definition)
    }

    func insertEntry(_ entry: MeasurementEntry) {
        context.insert(entry)
    }

    @discardableResult
    func save() -> Bool { context.saveOrReport() }
}
