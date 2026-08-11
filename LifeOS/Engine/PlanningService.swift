//
//  PlanningService.swift
//  LifeOS
//
//  DESIGN.md Section 14: "Schedule generation belongs in PlanningService"
//  and "Historical calendar items must not be regenerated destructively."
//  Pure functions — no ModelContext, no SwiftUI — so this is unit-testable
//  in isolation, per the architecture rule "Business logic must be
//  unit-testable." The call site (Today screen) is responsible for
//  inserting the returned items into SwiftData.
//

import Foundation
import SwiftData

enum PlanningService {

    /// The only persistence entry point for schedule generation. Fetching from
    /// ModelContext here avoids stale @Query snapshots and prevents Add Task,
    /// Today and Schedule from independently inserting the same occurrence.
    @discardableResult
    static func insertMissingCalendarItems(
        profile: Profile,
        date: Date,
        activities: [Activity],
        context: ModelContext,
        calendar: Calendar = .current
    ) throws -> [CalendarItem] {
        let storedItems = try context.fetch(FetchDescriptor<CalendarItem>())
        duplicateCalendarItems(in: storedItems, calendar: calendar).forEach(context.delete)
        let currentItems = try context.fetch(FetchDescriptor<CalendarItem>())
        let newItems = generateMissingCalendarItems(
            profile: profile, date: date, activities: activities,
            existingItems: currentItems, calendar: calendar
        )
        newItems.forEach(context.insert)
        return newItems
    }

    /// Canonical identity for one scheduled occurrence. Calendar dates are
    /// intentionally reduced to their day and minute so second/nanosecond
    /// differences introduced by persistence cannot create another copy.
    struct OccurrenceIdentity: Hashable {
        let profileID: UUID
        let activityID: UUID
        let day: Date
        let startMinute: Int
    }

    static func occurrenceIdentity(
        for item: CalendarItem,
        calendar: Calendar = .current
    ) -> OccurrenceIdentity? {
        guard item.source == .schedule,
              let profileID = item.profile?.id,
              let activityID = item.activity?.id,
              let plannedStart = item.plannedStart else { return nil }
        let day = calendar.startOfDay(for: item.date)
        return OccurrenceIdentity(
            profileID: profileID,
            activityID: activityID,
            day: day,
            startMinute: calendar.dateComponents([.minute], from: day, to: plannedStart).minute ?? 0
        )
    }

    /// Returns redundant records to remove at the persistence boundary. When
    /// old data already contains a collision, the record with user history is
    /// retained ahead of an untouched planned copy.
    static func duplicateCalendarItems(
        in items: [CalendarItem],
        calendar: Calendar = .current
    ) -> [CalendarItem] {
        var keeperByIdentity: [OccurrenceIdentity: CalendarItem] = [:]
        var duplicates: [CalendarItem] = []
        for item in items.sorted(by: { preferredDuplicateKeeper($0, over: $1) }) {
            guard let identity = occurrenceIdentity(for: item, calendar: calendar) else { continue }
            if keeperByIdentity[identity] == nil { keeperByIdentity[identity] = item }
            else if isUntouchedPlanned(item) { duplicates.append(item) }
        }
        return duplicates
    }

    /// Reconciles only untouched scheduled records after a Task definition is
    /// edited. Completed, skipped, rescheduled, manual, or otherwise annotated
    /// records are history and are never removed. The returned records no
    /// longer belong to the edited schedule and should be deleted by the caller.
    @discardableResult
    static func reconcileUntouchedOccurrences(
        for activity: Activity,
        in items: [CalendarItem],
        calendar: Calendar = .current
    ) -> [CalendarItem] {
        var stale: [CalendarItem] = []

        for item in items where item.activity?.id == activity.id && item.source == .schedule {
            guard isUntouchedPlanned(item) else { continue }
            let day = calendar.startOfDay(for: item.date)
            let expectedMinutes = activity.isActive
                ? scheduledStartMinutes(activity, on: day, calendar: calendar)
                : []
            guard let plannedStart = item.plannedStart else {
                stale.append(item)
                continue
            }
            let actualMinute = calendar.dateComponents(
                [.minute], from: day, to: plannedStart
            ).minute

            guard let actualMinute, expectedMinutes.contains(actualMinute) else {
                stale.append(item)
                continue
            }

            item.plannedEnd = calendar.date(
                byAdding: .minute,
                value: max(activity.estimatedDurationMinutes, 1),
                to: plannedStart
            )
        }
        return stale
    }

    /// Returns the Calendar Items that need to be created for `date` — i.e.
    /// activities scheduled for that day which don't already have an item.
    /// Never modifies or removes existing items (ADR-013 spirit: historical
    /// items are immutable facts, not regenerated).
    static func generateMissingCalendarItems(
        profile: Profile,
        date: Date,
        activities: [Activity],
        existingItems: [CalendarItem],
        calendar: Calendar = .current
    ) -> [CalendarItem] {
        let dayStart = calendar.startOfDay(for: date)

        let relevantActivities = activities.filter { activity in
            activity.profile?.id == profile.id
                && activity.profile?.isActive == true
                && activity.category?.profile?.id == profile.id
                && activity.category?.isActive == true
                && activity.isActive
                && isScheduled(activity, on: dayStart, calendar: calendar)
        }

        var newItems: [CalendarItem] = []
        var occupied = Set(existingItems.compactMap { occurrenceIdentity(for: $0, calendar: calendar) })
        for activity in relevantActivities {
            for startMinute in scheduledStartMinutes(activity, on: dayStart, calendar: calendar) {
                let plannedStart = calendar.date(byAdding: .minute, value: startMinute, to: dayStart)
                let identity = OccurrenceIdentity(profileID: profile.id, activityID: activity.id, day: dayStart, startMinute: startMinute)
                guard occupied.insert(identity).inserted else { continue }

                let plannedEnd = plannedStart.flatMap {
                    calendar.date(byAdding: .minute, value: activity.estimatedDurationMinutes, to: $0)
                }

                newItems.append(CalendarItem(
                    profile: profile,
                    activity: activity,
                    date: dayStart,
                    plannedStart: plannedStart,
                    plannedEnd: plannedEnd,
                    status: .planned,
                    source: .schedule
                ))
            }
        }
        return newItems
    }

    static func isScheduled(_ activity: Activity, on date: Date, calendar: Calendar = .current) -> Bool {
        !scheduledStartMinutes(activity, on: date, calendar: calendar).isEmpty
    }

    /// Returns every occurrence on a day, expressed as minutes after midnight.
    /// Multiple occurrences are first-class calendar items, so progress and
    /// reminders use the same schedule math as the Today timeline.
    static func scheduledStartMinutes(
        _ activity: Activity,
        on date: Date,
        calendar: Calendar = .current
    ) -> [Int] {
        guard activity.isActive, activity.category?.isActive == true else { return [] }
        let date = calendar.startOfDay(for: date)
        let startOfActivityStart = calendar.startOfDay(for: activity.startDate)
        if date < startOfActivityStart { return [] }
        if let end = activity.endDate, date > calendar.startOfDay(for: end) { return [] }

        switch activity.repeatType {
        case .once:
            return calendar.isSameDay(activity.startDate, as: date) ? [activity.plannedStartMinutes] : []
        case .daily:
            return [activity.plannedStartMinutes]
        case .selectedWeekdays:
            let weekday = calendar.component(.weekday, from: date)
            return activity.weekdays.contains(weekday) ? [activity.plannedStartMinutes] : []
        case .timesPerDay:
            return occurrenceTimes(
                count: activity.occurrencesPerDay,
                firstStartMinute: activity.plannedStartMinutes,
                intervalMinutes: activity.repeatIntervalMinutes
            )
        case .timesPerWeek:
            let selectedDays = activity.weekdays.isEmpty
                ? distributedWeekdays(count: activity.occurrencesPerWeek)
                : Array(Set(activity.weekdays)).sorted()
            let weekday = calendar.component(.weekday, from: date)
            guard let weekdayIndex = selectedDays.firstIndex(of: weekday) else { return [] }

            let total = max(1, activity.occurrencesPerWeek)
            let baseCount = total / selectedDays.count
            let extraCount = total % selectedDays.count
            let occurrencesToday = baseCount + (weekdayIndex < extraCount ? 1 : 0)
            return occurrenceTimes(
                count: occurrencesToday,
                firstStartMinute: activity.plannedStartMinutes,
                intervalMinutes: activity.repeatIntervalMinutes
            )
        }
    }

    static func distributedWeekdays(count: Int) -> [Int] {
        let preferredOrder = [2, 4, 6, 3, 5, 7, 1]
        return Array(preferredOrder.prefix(min(max(1, count), preferredOrder.count))).sorted()
    }

    static func scheduleFitsWithinDay(
        repeatType: RepeatType,
        occurrencesPerDay: Int,
        occurrencesPerWeek: Int,
        selectedWeekdayCount: Int,
        firstStartMinute: Int,
        intervalMinutes: Int
    ) -> Bool {
        let sameDayCount: Int
        switch repeatType {
        case .timesPerDay:
            sameDayCount = max(1, occurrencesPerDay)
        case .timesPerWeek:
            let dayCount = max(1, min(7, selectedWeekdayCount == 0 ? occurrencesPerWeek : selectedWeekdayCount))
            sameDayCount = Int(ceil(Double(max(1, occurrencesPerWeek)) / Double(dayCount)))
        case .once, .daily, .selectedWeekdays:
            sameDayCount = 1
        }

        guard firstStartMinute >= 0, firstStartMinute < 24 * 60 else { return false }
        return firstStartMinute + ((sameDayCount - 1) * max(1, intervalMinutes)) < 24 * 60
    }

    static func startDateIsValid(
        repeatType: RepeatType,
        startDate: Date,
        firstStartMinute: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let startDay = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: now)
        guard startDay >= today else { return false }
        guard repeatType == .once else { return true }
        guard let occurrence = calendar.date(
            byAdding: .minute, value: firstStartMinute, to: startDay
        ) else { return false }
        return occurrence > now
    }

    /// Work logged manually is already complete for its original day. If the
    /// user saves it as a repeating Task, its first obligation begins tomorrow.
    static func firstReusableDate(after loggedDate: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: loggedDate)
        return calendar.date(byAdding: .day, value: 1, to: day) ?? day
    }

    /// Concrete future dates used by local notifications. Finite dates avoid
    /// repeating notifications firing before a Task starts or after it ends.
    static func reminderOccurrenceDates(
        for activity: Activity,
        after now: Date = .now,
        horizonDays: Int = 60,
        maxCount: Int = 24,
        calendar: Calendar = .current
    ) -> [Date] {
        guard activity.isActive, activity.category?.isActive == true, maxCount > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        let activityStart = calendar.startOfDay(for: activity.startDate)
        var day = max(today, activityStart)
        let horizon = calendar.date(byAdding: .day, value: max(1, horizonDays), to: today) ?? today
        let lastDay = min(activity.endDate.map { calendar.startOfDay(for: $0) } ?? horizon, horizon)
        var dates: [Date] = []

        while day <= lastDay && dates.count < maxCount {
            for minute in scheduledStartMinutes(activity, on: day, calendar: calendar) {
                guard let occurrence = calendar.date(byAdding: .minute, value: minute, to: day),
                      occurrence > now else { continue }
                dates.append(occurrence)
                if dates.count == maxCount { break }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return dates.sorted()
    }

    static func plannedItems(_ items: [CalendarItem]) -> [CalendarItem] {
        items.filter { $0.source == .schedule && $0.status != .unplanned }
    }

    /// One occurrence of a scheduled Activity within a reconstructed period —
    /// either a real stored `CalendarItem` or a synthesized placeholder for a
    /// slot the schedule implies but that has no item yet. `activity` is nil
    /// only for `includeUnlinked` orphan items whose relationship was lost.
    struct ReconstructedOccurrence {
        let activity: Activity?
        let calendarItem: CalendarItem?
        let date: Date
        let plannedStart: Date
        let status: CalendarItemStatus
    }

    /// The canonical occurrence-reconstruction path shared by every progress
    /// engine. It merges real stored schedule-sourced `CalendarItem`s with
    /// occurrences implied by `scheduledStartMinutes` for the given
    /// `activities`, deduped by `OccurrenceIdentity` so a slot with a real
    /// item is never double-counted against its own synthesized placeholder.
    ///
    /// `activities` also scopes which stored items are considered: an item
    /// is only merged in if its Activity is one of the ones passed in (or,
    /// with `includeUnlinked`, if it has no Activity at all). Callers that
    /// want a whole-profile view pass every Activity for that profile;
    /// callers that want a category/contribution-scoped view pass just the
    /// relevant subset. Rescheduled items are excluded from the merge — that
    /// slot reverts to an ordinary `.planned` placeholder, per
    /// `periodCompletionReport`'s original behavior, so the count of what
    /// still needs a decision is preserved rather than lost through the move.
    static func reconstructedOccurrences(
        profile: Profile,
        interval: DateInterval,
        activities: [Activity],
        calendarItems: [CalendarItem],
        includeUnlinked: Bool = false,
        calendar: Calendar = .current
    ) -> [ReconstructedOccurrence] {
        let activityIDs = Set(activities.map(\.id))
        let stored = calendarItems.filter {
            $0.profile?.id == profile.id && $0.source == .schedule &&
            interval.contains($0.date) && $0.status != .rescheduled &&
            ($0.activity.map { activityIDs.contains($0.id) } ?? includeUnlinked)
        }

        var occurrences: [OccurrenceIdentity: ReconstructedOccurrence] = [:]
        var unlinked: [ReconstructedOccurrence] = []
        for item in stored {
            let occurrence = ReconstructedOccurrence(
                activity: item.activity, calendarItem: item,
                date: item.date, plannedStart: item.plannedStart ?? item.date,
                status: item.status
            )
            guard let identity = occurrenceIdentity(for: item, calendar: calendar) else {
                unlinked.append(occurrence)
                continue
            }
            occurrences[identity] = occurrence
        }

        var date = calendar.startOfDay(for: interval.start)
        while date < interval.end {
            for activity in activities where activity.profile?.id == profile.id {
                for minute in scheduledStartMinutes(activity, on: date, calendar: calendar) {
                    guard let plannedStart = calendar.date(byAdding: .minute, value: minute, to: date) else { continue }
                    let identity = OccurrenceIdentity(profileID: profile.id, activityID: activity.id, day: date, startMinute: minute)
                    if occurrences[identity] == nil {
                        occurrences[identity] = ReconstructedOccurrence(
                            activity: activity, calendarItem: nil,
                            date: date, plannedStart: plannedStart, status: .planned
                        )
                    }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }

        return Array(occurrences.values) + unlinked
    }

    static func hasHistory(
        for activity: Activity,
        on date: Date,
        in items: [CalendarItem],
        calendar: Calendar = .current
    ) -> Bool {
        items.contains { item in
            item.activity?.id == activity.id
                && calendar.isSameDay(item.date, as: date)
                && (item.source == .manual || !isUntouchedPlanned(item))
        }
    }

    static func isOverdue(_ item: CalendarItem, now: Date = .now) -> Bool {
        item.status == .planned && item.plannedStart.map { $0 < now } == true
    }

    private static func occurrenceTimes(
        count: Int,
        firstStartMinute: Int,
        intervalMinutes: Int
    ) -> [Int] {
        guard count > 0 else { return [] }
        let safeCount = count
        let safeInterval = max(1, intervalMinutes)
        return (0..<safeCount)
            .map { firstStartMinute + ($0 * safeInterval) }
            .filter { $0 >= 0 && $0 < 24 * 60 }
    }

    private static func preferredDuplicateKeeper(_ lhs: CalendarItem, over rhs: CalendarItem) -> Bool {
        func score(_ item: CalendarItem) -> Int {
            var value = 0
            if item.status != .planned { value += 4 }
            if item.actualStart != nil || item.actualEnd != nil { value += 2 }
            if !item.note.isEmpty { value += 1 }
            return value
        }
        let left = score(lhs), right = score(rhs)
        return left == right ? lhs.id.uuidString < rhs.id.uuidString : left > right
    }

    private static func isUntouchedPlanned(_ item: CalendarItem) -> Bool {
        item.status == .planned && item.actualStart == nil && item.actualEnd == nil && item.note.isEmpty
    }
}
