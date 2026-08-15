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
    let sessions: [ActivitySession] = []
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

    /// Completes an occurrence immediately when there's nothing to record —
    /// the zero-measurement, no-legacy-target path. Mirrors
    /// `RecordActualView.save()`'s no-target Session shape (duration only,
    /// no recorded value), just without the intermediate form.
    ///
    /// `completionTime` is the exact moment Finish was tapped, passed in by
    /// the caller (`.now`) — deliberately not `currentTime`, which is the
    /// Today screen's once-a-minute refresh clock and can be stale by up to
    /// a minute relative to the actual tap.
    ///
    /// Timing source depends on whether the occurrence was actually
    /// started: an in-progress item already has a real `actualStart`, so
    /// that's preserved and duration is derived from start → completionTime
    /// (Started 6:00, Finished 6:45 must record 45 minutes, not the
    /// Activity's estimate). A still-planned item has no real start time to
    /// preserve, so the estimated duration remains the fallback, anchored
    /// to end at `completionTime`.
    ///
    /// Idempotent: a no-op once `item.status == .done`, so a duplicate tap
    /// (e.g. a fast double-tap before the UI re-renders) can never insert a
    /// second `ActivitySession` for the same occurrence. Rollback-safe: on
    /// save failure, restores status/actualStart/actualEnd to their prior
    /// values and removes the inserted Session, matching the
    /// capture-then-restore pattern `start`/`skip` already use above.
    @discardableResult
    func quickFinish(_ item: CalendarItem, at completionTime: Date) -> Bool {
        guard item.status != .done else { return false }

        let previousStatus = item.status
        let previousStart = item.actualStart
        let previousEnd = item.actualEnd

        let start: Date
        let end = completionTime
        if previousStatus == .inProgress, let realStart = previousStart {
            start = realStart
        } else {
            let durationMinutes = max(item.activity?.estimatedDurationMinutes ?? 1, 1)
            start = CompletionTiming.interval(endingAt: end, durationMinutes: durationMinutes).start
        }
        let activeSeconds = max(Int(end.timeIntervalSince(start)), 0)

        item.actualStart = start
        item.actualEnd = end
        item.status = .done

        let session = ActivitySession(
            activity: item.activity,
            calendarItem: item,
            date: item.date,
            startedAt: start,
            endedAt: end,
            actualActiveSeconds: activeSeconds,
            recordedValue: 0,
            note: ""
        )
        repository.insertSession(session)

        if repository.save() {
            return true
        }

        repository.deleteSession(session)
        item.status = previousStatus
        item.actualStart = previousStart
        item.actualEnd = previousEnd
        return false
    }

    /// Reverses only the completion evidence belonging to this exact calendar
    /// occurrence. A name, time, Activity, or Profile match alone is never
    /// enough: identical Tasks can legitimately exist in multiple profiles.
    /// If the historical data is not exactly one session, preserve it and
    /// refuse the undo rather than guessing which evidence to remove.
    @discardableResult
    func undoQuickFinish(_ item: CalendarItem) -> Bool {
        guard item.status == .done else { return false }
        let matchingSessions = sessions.filter { $0.calendarItem?.id == item.id }
        guard matchingSessions.count == 1, let session = matchingSessions.first else { return false }

        let previousStatus = item.status
        let previousStart = item.actualStart
        let previousEnd = item.actualEnd
        item.status = .planned
        item.actualStart = nil
        item.actualEnd = nil
        repository.deleteSession(session)

        if repository.save() { return true }

        repository.insertSession(session)
        item.status = previousStatus
        item.actualStart = previousStart
        item.actualEnd = previousEnd
        return false
    }
}
