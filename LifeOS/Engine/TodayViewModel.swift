//
//  TodayViewModel.swift
//  LifeOS
//
//  Refactor.md Step 4: View -> ViewModel -> Service/Use Case -> Repository
//  -> SwiftData, applied to the Today screen only. Every derived value here
//  used to be a computed property directly on TodayTimelineView; the logic
//  is unchanged, only its location moved, so this is unit-testable in
//  isolation (DESIGN.md: "Business logic must be unit-testable").
//
//  Recreated fresh on every access from the View's live @Query results
//  (see TodayTimelineView.viewModel) rather than held as persisted @State —
//  it carries no state of its own, so there is no separate sync step that
//  could drift out of date against SwiftData.
//

import Foundation

@MainActor
struct TodayViewModel {
    let profile: Profile?
    let items: [CalendarItem]
    let activities: [Activity]
    let resultMeasures: [ResultMeasure]
    let currentTime: Date
    let repository: CalendarRepository

    var todayItems: [CalendarItem] {
        guard let profile else { return [] }
        let calendar = Calendar.current
        return items
            .filter { $0.profile?.id == profile.id && calendar.isSameDay($0.date, as: currentTime) }
            .sorted { ($0.plannedStart ?? .distantPast) < ($1.plannedStart ?? .distantPast) }
    }

    var summary: CompletionSummary {
        ProgressEngine.completionSummary(items: PlanningService.plannedItems(todayItems))
    }

    var activeItems: [CalendarItem] {
        todayItems.filter { $0.status == .planned || $0.status == .inProgress }
    }

    var decidedItems: [CalendarItem] {
        todayItems.filter {
            $0.status == .done || $0.status == .skipped
                || $0.status == .rescheduled || $0.status == .unplanned
        }
    }

    var overdueItems: [CalendarItem] {
        activeItems.filter { PlanningService.isOverdue($0, now: currentTime) }
    }

    var nextItem: CalendarItem? {
        activeItems.first { $0.status == .inProgress }
            ?? activeItems.first { !PlanningService.isOverdue($0, now: currentTime) }
    }

    var restOfDayItems: [CalendarItem] {
        activeItems.filter {
            $0.id != nextItem?.id && !PlanningService.isOverdue($0, now: currentTime)
        }
    }

    var dueResultMeasures: [ResultMeasure] {
        guard let profile else { return [] }
        let startOfToday = Calendar.current.startOfDay(for: currentTime)
        return resultMeasures
            .filter { measure in
                guard measure.isActive,
                      measure.goal?.profile?.id == profile.id,
                      let nextDate = measure.nextCheckInDate else { return false }
                return Calendar.current.startOfDay(for: nextDate) <= startOfToday
            }
            .sorted { ($0.nextCheckInDate ?? .distantFuture) < ($1.nextCheckInDate ?? .distantFuture) }
    }

    func generateTodayItemsIfNeeded() {
        guard let profile else { return }
        do {
            let newItems = try repository.insertMissingItems(profile: profile, date: currentTime, activities: activities)
            if !newItems.isEmpty || repository.hasChanges { repository.save() }
        } catch {
            PersistenceIssueCenter.shared.report(error)
        }
    }

    func start(_ item: CalendarItem) {
        let previousStatus = item.status
        let previousStart = item.actualStart
        item.status = .inProgress
        item.actualStart = .now
        if !repository.save() {
            item.status = previousStatus
            item.actualStart = previousStart
        }
    }

    func skip(_ item: CalendarItem) {
        let previousStatus = item.status
        item.status = .skipped
        if !repository.save() { item.status = previousStatus }
    }

    func undoSkip(_ item: CalendarItem) {
        guard item.status == .skipped else { return }
        item.status = .planned
        if !repository.save() { item.status = .skipped }
    }
}
