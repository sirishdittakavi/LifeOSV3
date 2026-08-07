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

enum PlanningService {

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
            activity.profile?.id == profile.id &&
            activity.isActive &&
            isScheduled(activity, on: dayStart, calendar: calendar)
        }

        var newItems: [CalendarItem] = []
        for activity in relevantActivities {
            for startMinute in scheduledStartMinutes(activity, on: dayStart, calendar: calendar) {
                let plannedStart = calendar.date(byAdding: .minute, value: startMinute, to: dayStart)
                let alreadyExists = existingItems.contains {
                    $0.activity?.id == activity.id &&
                    calendar.isSameDay($0.date, as: dayStart) &&
                    $0.plannedStart == plannedStart
                } || newItems.contains {
                    $0.activity?.id == activity.id && $0.plannedStart == plannedStart
                }
                guard !alreadyExists else { continue }

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
}
