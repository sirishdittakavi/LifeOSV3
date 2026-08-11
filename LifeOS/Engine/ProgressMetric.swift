//
//  ProgressMetric.swift
//  LifeOS
//
//  Refactor.md Step 7 / DESIGN.md §8: a generic progress shape so callers
//  never need separate hard-coded dashboard logic for Protein, Baseball,
//  Coding, etc. Built from the existing canonical engines (CategoryProgressEngine,
//  GoalProgressEngine — already unified in Step 1) rather than recomputing
//  anything. Not wired into any View yet — this is the shared read-model
//  piece of DESIGN.md §9's CalendarItems/Sessions/FoodLogEntries/Measurements/
//  Goals -> TodaySummaryService -> TodayViewModel -> Today UI diagram; wiring
//  it into UI is a later, separate change, not part of this step.
//

import Foundation

struct ProgressMetric: Identifiable {
    let id: UUID
    let title: String
    let currentValue: Double
    let targetValue: Double?
    let unit: String
    let statusText: String
    let destinationCategoryID: UUID?
    let destinationGoalID: UUID?

    /// Capped at 100% for score/color coding — callers that need the real,
    /// uncapped number still have it via currentValue/targetValue directly.
    var progress: Double {
        guard let targetValue, targetValue > 0 else { return 0 }
        return min(currentValue / targetValue, 1.0)
    }
}

enum ProgressMetricBuilder {
    static func metric(from progress: CategoryProgress) -> ProgressMetric {
        let target = progress.targetMinutes > 0 ? progress.targetMinutes : progress.targetSessions
        let current = progress.targetMinutes > 0 ? progress.completedMinutes : progress.completedSessions
        return ProgressMetric(
            id: progress.category.id,
            title: progress.category.name,
            currentValue: Double(current),
            targetValue: target > 0 ? Double(target) : nil,
            unit: progress.targetMinutes > 0 ? "min" : "sessions",
            statusText: progress.status.rawValue,
            destinationCategoryID: progress.category.id,
            destinationGoalID: nil
        )
    }

    static func metric(from progress: GoalProgress) -> ProgressMetric {
        ProgressMetric(
            id: progress.goal.id,
            title: progress.goal.name,
            currentValue: (progress.resultFraction ?? 0) * 100,
            targetValue: 100,
            unit: "%",
            statusText: progress.status.rawValue,
            destinationCategoryID: nil,
            destinationGoalID: progress.goal.id
        )
    }

    static func metric(from progress: DailyActivityProgress) -> ProgressMetric {
        ProgressMetric(
            id: progress.activity.id,
            title: progress.activity.name,
            currentValue: progress.actual,
            targetValue: progress.target,
            unit: progress.activity.targetUnit ?? "",
            statusText: progress.target == nil ? "No target set" : "",
            destinationCategoryID: progress.activity.category?.id,
            destinationGoalID: nil
        )
    }

    static func metric(nutrition totals: NutritionTotals, profile: Profile) -> ProgressMetric {
        ProgressMetric(
            id: profile.id,
            title: "Protein",
            currentValue: totals.protein,
            targetValue: profile.proteinGoalGrams,
            unit: "g",
            statusText: "",
            destinationCategoryID: nil,
            destinationGoalID: nil
        )
    }
}
