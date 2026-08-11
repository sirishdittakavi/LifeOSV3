//
//  CalendarRepository.swift
//  LifeOS
//
//  Refactor.md Step 4: the persistence boundary for the Today screen.
//  TodayViewModel depends on this protocol, not on ModelContext directly,
//  so its logic is testable with a fake and the View never touches
//  ModelContext for CalendarItem writes itself.
//

import Foundation
import SwiftData

protocol CalendarRepository {
    var hasChanges: Bool { get }
    func insertMissingItems(profile: Profile, date: Date, activities: [Activity]) throws -> [CalendarItem]
    @discardableResult func save() -> Bool
}

@MainActor
final class SwiftDataCalendarRepository: CalendarRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    var hasChanges: Bool { context.hasChanges }

    func insertMissingItems(profile: Profile, date: Date, activities: [Activity]) throws -> [CalendarItem] {
        try PlanningService.insertMissingCalendarItems(
            profile: profile, date: date, activities: activities, context: context
        )
    }

    @discardableResult
    func save() -> Bool { context.saveOrReport() }
}
