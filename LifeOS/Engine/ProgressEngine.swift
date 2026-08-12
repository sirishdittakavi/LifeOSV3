//
//  ProgressEngine.swift
//  LifeOS
//
//  Implements DESIGN.md Section 10a (Daily Progress Tracking vs Actual).
//  Deliberately kept separate from calendar item completion status
//  (Section 9/10) — this engine answers "how much did I actually log
//  against my targets today," not "how many items did I check off."
//  No blended score: the doc is explicit that these stay two honest,
//  separate views rather than one misleading combined number.
//

import Foundation

struct DailyActivityProgress: Identifiable {
    let activity: Activity
    var id: UUID { activity.id }

    let actual: Double

    var target: Double? { activity.targetValue }

    /// Capped at 100% for any score/color coding — the actual, uncapped
    /// number is always available via `actual` and must always be shown too.
    var cappedFraction: Double {
        guard let target, target > 0 else { return 0 }
        return min(actual / target, 1.0)
    }
}

struct CompletionSummary {
    let done: Int
    let skipped: Int
    let remaining: Int
    let total: Int

    var percentComplete: Double {
        guard total > 0 else { return 0 }
        return Double(done) / Double(total)
    }
}

struct CompletionBucket: Identifiable {
    let date: Date
    let done: Int
    let total: Int
    var id: Date { date }
}

struct PeriodCompletionReport {
    let done: Int
    let skipped: Int
    let missed: Int
    let remaining: Int
    let buckets: [CompletionBucket]
    var total: Int { done + skipped + missed + remaining }
    var percentComplete: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

/// Actual nutrition intake for one day. Previously computed independently
/// (and identically) in FoodTrackerView and TodayTimelineView's plan-card
/// nutrition snapshot — DESIGN.md §9 explicitly warns against "independent
/// Protein totals on Dashboard and Nutrition." Both now call
/// ProgressEngine.nutritionTotals instead.
struct NutritionTotals {
    var calories = 0.0
    var protein = 0.0
    var carbs = 0.0
    var fat = 0.0
    var water = 0.0
}

enum ProgressEngine {
    static func nutritionTotals(
        profile: Profile, date: Date, entries: [FoodEntry], calendar: Calendar = .current
    ) -> NutritionTotals {
        let dayEntries = entries.filter {
            $0.profile?.id == profile.id && !$0.isMealPlanItem && calendar.isSameDay($0.date, as: date)
        }
        var totals = NutritionTotals()
        for entry in dayEntries {
            totals.calories += entry.calories
            totals.protein += entry.proteinGrams
            totals.carbs += entry.carbohydrateGrams
            totals.fat += entry.fatGrams
            totals.water += entry.waterMilliliters
        }
        return totals
    }


    static func periodCompletionReport(
        profile: Profile, interval: DateInterval, items: [CalendarItem],
        activities: [Activity] = [],
        now: Date = .now, calendar: Calendar = .current
    ) -> PeriodCompletionReport {
        let planned = PlanningService.reconstructedOccurrences(
            profile: profile, interval: interval, activities: activities,
            calendarItems: items, includeUnlinked: true, calendar: calendar
        )
        let done = planned.filter { $0.status == .done }.count
        let skipped = planned.filter { $0.status == .skipped }.count
        let pending = planned.filter { $0.status == .planned || $0.status == .inProgress }
        let missed = pending.filter { $0.status == .planned && $0.plannedStart < now }.count
        var bucketDate = calendar.startOfDay(for: interval.start)
        var buckets: [CompletionBucket] = []
        while bucketDate < interval.end {
            let dayItems = planned.filter { calendar.isDate($0.date, inSameDayAs: bucketDate) }
            buckets.append(CompletionBucket(
                date: bucketDate,
                done: dayItems.filter { $0.status == .done }.count,
                total: dayItems.count
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: bucketDate) else { break }
            bucketDate = next
        }
        return PeriodCompletionReport(
            done: done, skipped: skipped, missed: missed,
            remaining: pending.count - missed, buckets: buckets
        )
    }

    /// Section 10a: target vs. actual for every tracked (targetValue != nil)
    /// activity belonging to `profile`, for a single day. Activities without
    /// a target are intentionally excluded — they're tracked by completion
    /// status only (Section 10), not penalized for lacking a number.
    static func dailyProgress(
        profile: Profile,
        date: Date,
        activities: [Activity],
        sessions: [ActivitySession],
        calendar: Calendar = .current
    ) -> [DailyActivityProgress] {
        let trackedActivities = activities.filter {
            $0.profile?.id == profile.id && $0.isActive && $0.targetValue != nil
        }

        return trackedActivities.map { activity in
            let daySessions = sessions.filter {
                $0.activity?.id == activity.id && calendar.isSameDay($0.date, as: date)
            }
            let actual = daySessions.reduce(0.0) { $0 + $1.recordedValue }
            return DailyActivityProgress(activity: activity, actual: actual)
        }
    }

    /// Section 9/12: completion counts by Calendar Item status, for the
    /// "4 done · 1 skipped · 2 remaining" header on the Today screen.
    static func completionSummary(items: [CalendarItem]) -> CompletionSummary {
        let done = items.filter { $0.status == .done }.count
        let skipped = items.filter { $0.status == .skipped }.count
        let remaining = items.filter { $0.status == .planned || $0.status == .inProgress }.count
        return CompletionSummary(done: done, skipped: skipped, remaining: remaining, total: items.count)
    }

    /// Refactor.md Phase 2 / DOMAIN_MODEL_V2_PROPOSAL.md §2.9c: sums the
    /// MeasurementEntry values for one MeasurementDefinition, optionally
    /// bounded to a date range. Matches by the entry's live
    /// `measurementDefinition` link when present; falls back to a
    /// `nameSnapshot` match when it's nil (a definition renamed, archived,
    /// or deleted since the entry was recorded) — this is what lets a
    /// historical entry keep contributing to totals even after its
    /// definition no longer exists, per the entry's own historical-snapshot
    /// design (Models.swift's MeasurementEntry doc comment).
    ///
    /// Not wired into any Goal, View, or ViewModel yet — this is the
    /// generalization of the same `min(current/target, 1)` shape
    /// `ProgressMetric.progress` already uses, applied to a summed series
    /// instead of a single scalar. No new progress formula is introduced.
    static func measurementTotal(
        for definition: MeasurementDefinition,
        entries: [MeasurementEntry],
        interval: DateInterval? = nil
    ) -> Double {
        entries
            .filter { entry in
                let matchesDefinition = entry.measurementDefinition?.id == definition.id
                    || (entry.measurementDefinition == nil && entry.nameSnapshot == definition.name)
                guard matchesDefinition else { return false }
                guard let interval else { return true }
                return interval.contains(entry.recordedAt)
            }
            .reduce(0.0) { $0 + ($1.numericValue ?? 0) }
    }
}
