//
//  RelationshipRepository.swift
//  LifeOS
//
//  Refactor.md Phase 2: the persistence boundary for Relationship,
//  mirroring CalendarRepository's shape. Data-layer only — no permission
//  enforcement, sharing, or notifications here or anywhere yet.
//

import Foundation
import SwiftData

protocol RelationshipRepository {
    var hasChanges: Bool { get }
    func insert(_ relationship: Relationship)
    @discardableResult func save() -> Bool
}

@MainActor
final class SwiftDataRelationshipRepository: RelationshipRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    var hasChanges: Bool { context.hasChanges }

    func insert(_ relationship: Relationship) {
        context.insert(relationship)
    }

    @discardableResult
    func save() -> Bool { context.saveOrReport() }
}
