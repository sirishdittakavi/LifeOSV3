//
//  TaskOccurrenceActions.swift
//  LifeOS
//
//  Exceptional single-occurrence actions owned by Task Detail (v3 rebuild
//  Chunk 4). Every operation is scoped by the CalendarItem's/Activity's own
//  identity -- never by Task name, time, or profile name -- so acting on one
//  occurrence can never affect another occurrence, another Task, or another
//  profile's identically named/scheduled Task.
//

import Foundation
import SwiftData

@MainActor
enum TaskOccurrenceActions {
    /// Skips exactly `item`. Returns `false` (and rolls back) if the save
    /// fails; no other CalendarItem is read or written.
    @discardableResult
    static func skip(_ item: CalendarItem, context: ModelContext) -> Bool {
        let previousStatus = item.status
        item.status = .skipped
        if context.saveOrReport() { return true }
        item.status = previousStatus
        return false
    }

    /// Moves exactly `item` to `newDate`: `item` itself is marked
    /// `.rescheduled` (excluded from due/decided counting, matching every
    /// other `.rescheduled` read site in the app) and a new CalendarItem is
    /// inserted at the new date/time for `item`'s own profile and the given
    /// Activity. Returns the new CalendarItem on success, or `nil` (with
    /// both mutations rolled back) if the save fails.
    @discardableResult
    static func reschedule(_ item: CalendarItem, activity: Activity, to newDate: Date, context: ModelContext) -> CalendarItem? {
        let previousStatus = item.status
        item.status = .rescheduled

        let calendar = Calendar.current
        let plannedEnd = calendar.date(byAdding: .minute, value: activity.estimatedDurationMinutes, to: newDate)
        let replacement = CalendarItem(
            profile: item.profile, activity: activity,
            date: calendar.startOfDay(for: newDate),
            plannedStart: newDate, plannedEnd: plannedEnd,
            status: .planned, source: .manual
        )
        context.insert(replacement)

        if context.saveOrReport() { return replacement }
        item.status = previousStatus
        context.delete(replacement)
        _ = context.saveOrReport()
        return nil
    }
}
