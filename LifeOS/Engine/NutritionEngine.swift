//
//  NutritionEngine.swift
//  LifeOS
//
//  NUTRITION_MODULE_DESIGN_V1.md / NUTRITION_INTEGRATION_PLAN_V1.md: the
//  Nutrition-native counterpart to ProgressEngine.nutritionTotals — daily
//  totals, target progress, and the day-level consistency calculations
//  Nutrition Progress needs. Deliberately depends only on MealEntry/
//  NutritionFoodEntry/WaterEntry/NutritionGoal, never Activity/
//  CalendarItem/ActivitySession (NUTRITION_MODULE_DESIGN_V1.md decision 1).
//
//  ProgressEngine.nutritionTotals(profile:date:entries:[FoodEntry]) is left
//  in place and untouched — old and new calculation paths coexist until the
//  old FoodTrackerView/FoodEntry are removed in a later phase.
//

import Foundation

enum NutritionEngine {
    struct DailyTotals: Equatable {
        var calories = 0.0
        var proteinG = 0.0
        var carbsG = 0.0
        var fatG = 0.0
        var waterML = 0.0
    }

    /// Actual nutrition intake for one profile on one day, summed from that
    /// day's MealEntry totals plus that day's WaterEntry amounts.
    static func dailyTotals(
        profileID: UUID, date: Date, meals: [MealEntry], waterEntries: [WaterEntry],
        calendar: Calendar = .current
    ) -> DailyTotals {
        let dayMeals = meals.filter {
            $0.profileID == profileID && calendar.isDate($0.recordedAt, inSameDayAs: date)
        }
        let macros = NutritionValue.sum(dayMeals.map(\.totals))
        let water = waterEntries
            .filter { $0.profileID == profileID && calendar.isDate($0.recordedAt, inSameDayAs: date) }
            .reduce(0.0) { $0 + $1.amountML }

        return DailyTotals(
            calories: macros.calories, proteinG: macros.proteinG,
            carbsG: macros.carbsG, fatG: macros.fatG, waterML: water
        )
    }

    /// A day's totals against the user's own NutritionGoal, if and only if
    /// they configured one. Every target field is optional and `nil` when
    /// unconfigured — never a fallback/assumed value (no NutritionGoal
    /// record at all, or a record with a `nil` field, mean exactly the same
    /// thing: this metric has no target). Callers must treat a `nil`
    /// target/fraction as "no target configured", not as zero.
    struct TargetProgress: Equatable {
        var totals: DailyTotals
        var calorieTarget: Double?
        var proteinTarget: Double?
        var carbsTarget: Double?
        var fatTarget: Double?
        var waterTarget: Double?

        var calorieFraction: Double? { calorieTarget.map { NutritionEngine.fraction(totals.calories, of: $0) } }
        var proteinFraction: Double? { proteinTarget.map { NutritionEngine.fraction(totals.proteinG, of: $0) } }
        var carbsFraction: Double? { carbsTarget.map { NutritionEngine.fraction(totals.carbsG, of: $0) } }
        var fatFraction: Double? { fatTarget.map { NutritionEngine.fraction(totals.fatG, of: $0) } }
        var waterFraction: Double? { waterTarget.map { NutritionEngine.fraction(totals.waterML, of: $0) } }
    }

    static func targetProgress(
        profileID: UUID, date: Date, meals: [MealEntry], waterEntries: [WaterEntry],
        goal: NutritionGoal?, calendar: Calendar = .current
    ) -> TargetProgress {
        let totals = dailyTotals(profileID: profileID, date: date, meals: meals, waterEntries: waterEntries, calendar: calendar)
        return TargetProgress(
            totals: totals,
            calorieTarget: goal?.calorieTarget,
            proteinTarget: goal?.proteinTargetG,
            carbsTarget: goal?.carbsTargetG,
            fatTarget: goal?.fatTargetG,
            waterTarget: goal?.waterTargetML
        )
    }

    /// A daily target multiplied out to a target for `days` days — e.g. a
    /// 220g/day protein target derives a 1540g target over 7 days. The user
    /// only ever configures the daily figure; every other period is always
    /// derived from it, never entered separately.
    static func derivedTarget(dailyTarget: Double, days: Int) -> Double {
        dailyTarget * Double(days)
    }

    static func fraction(_ value: Double, of target: Double) -> Double {
        guard target > 0, value.isFinite else { return 0 }
        return min(max(value / target, 0), 1)
    }

    /// Standard energy-from-macros formula (4 kcal/g protein & carbs, 9
    /// kcal/g fat). Informational only -- used to flag an internally
    /// inconsistent manual entry, never to override or auto-fill the
    /// user's directly-entered Calories field. A meal stays one fixed,
    /// user-entered set of totals (AddEditMealView.swift's locked decision);
    /// LifeOS never computes nutrition from macros/ingredients on the
    /// user's behalf.
    static func caloriesFromMacros(proteinG: Double, carbsG: Double, fatG: Double) -> Double {
        4 * proteinG + 4 * carbsG + 9 * fatG
    }

    /// A manually-entered meal/template's totals must never be negative --
    /// there's no such thing as "-50 calories" or "-10g protein".
    static func isValidMacroEntry(_ value: NutritionValue) -> Bool {
        value.calories >= 0 && value.proteinG >= 0 && value.carbsG >= 0 && value.fatG >= 0
    }

    /// An unset (nil) daily target means "not tracked" and is always valid;
    /// a set target must never be negative -- there's no such thing as a
    /// "-2000 kcal/day" target.
    static func isValidDailyTarget(_ value: Double?) -> Bool {
        value.map { $0 >= 0 } ?? true
    }

    /// A tracked macro/water metric for consistency counting and Goal
    /// linkage — plain-language cases only, no technical terms surfaced.
    enum Metric: String, CaseIterable, Identifiable, Hashable {
        case calories, protein, carbs, fat, water
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .calories: return "Calories"
            case .protein: return "Protein"
            case .carbs: return "Carbs"
            case .fat: return "Fat"
            case .water: return "Water"
            }
        }

        fileprivate func value(in totals: DailyTotals) -> Double {
            switch self {
            case .calories: return totals.calories
            case .protein: return totals.proteinG
            case .carbs: return totals.carbsG
            case .fat: return totals.fatG
            case .water: return totals.waterML
            }
        }

        fileprivate func target(in progress: TargetProgress) -> Double? {
            switch self {
            case .calories: return progress.calorieTarget
            case .protein: return progress.proteinTarget
            case .carbs: return progress.carbsTarget
            case .fat: return progress.fatTarget
            case .water: return progress.waterTarget
            }
        }

        fileprivate func target(in goal: NutritionGoal) -> Double? {
            switch self {
            case .calories: return goal.calorieTarget
            case .protein: return goal.proteinTargetG
            case .carbs: return goal.carbsTargetG
            case .fat: return goal.fatTargetG
            case .water: return goal.waterTargetML
            }
        }
    }

    /// Days within `interval` where `metric`'s total met or exceeded its
    /// target, e.g. "Protein target days: 26/30" (NUTRITION_MODULE_DESIGN_V1.md
    /// mockup Screen 07). `totalDays` is the number of calendar days in the
    /// interval, not just days with any logging, so an unlogged day counts
    /// as a missed day rather than being silently excluded. Returns `nil`
    /// (not a bogus 0/N) when the user hasn't configured a target for this
    /// metric — there is nothing to be consistent against.
    static func consistencyDays(
        profileID: UUID, interval: DateInterval, metric: Metric,
        meals: [MealEntry], waterEntries: [WaterEntry], goal: NutritionGoal?,
        calendar: Calendar = .current
    ) -> (achieved: Int, totalDays: Int)? {
        guard let goal, let target = metric.target(in: goal) else { return nil }

        var achieved = 0
        var totalDays = 0
        var day = calendar.startOfDay(for: interval.start)
        let end = interval.end

        while day < end {
            totalDays += 1
            let totals = dailyTotals(profileID: profileID, date: day, meals: meals, waterEntries: waterEntries, calendar: calendar)
            if metric.value(in: totals) >= target {
                achieved += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return (achieved, totalDays)
    }

    /// Sum of a metric across an interval — used by Goal linkage, mirroring
    /// ProgressEngine.measurementTotal's shape for MeasurementDefinition.
    static func metricTotal(
        profileID: UUID, metric: Metric, interval: DateInterval,
        meals: [MealEntry], waterEntries: [WaterEntry], calendar: Calendar = .current
    ) -> Double {
        var total = 0.0
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            let totals = dailyTotals(profileID: profileID, date: day, meals: meals, waterEntries: waterEntries, calendar: calendar)
            total += metric.value(in: totals)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return total
    }

    /// Relevance ordering for Meal Templates: favorites first, then most
    /// recently used, then most-used, matching NUTRITION_MODULE_DESIGN_V1.md
    /// §9 Screen 05 ("Favorites" section pinned above "All templates").
    static func sortedByRelevance(_ templates: [MealTemplate]) -> [MealTemplate] {
        templates.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            switch (lhs.lastUsedAt, rhs.lastUsedAt) {
            case let (.some(l), .some(r)) where l != r: return l > r
            case (.some, .none): return true
            case (.none, .some): return false
            default: break
            }
            if lhs.useCount != rhs.useCount { return lhs.useCount > rhs.useCount }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

enum BodyTrackingEngine {
    /// Most recent entry for a definition, at or before `date`.
    static func latestEntry(definitionID: UUID, entries: [BodyMetricEntry], on date: Date = .now) -> BodyMetricEntry? {
        entries
            .filter { $0.bodyMetricDefinition?.id == definitionID && $0.recordedAt <= date }
            .max { $0.recordedAt < $1.recordedAt }
    }

    /// Change from the oldest entry within `interval` to the latest overall
    /// entry — the "-3.5kg" style trend figure, not a day-by-day series.
    static func trend(definitionID: UUID, entries: [BodyMetricEntry], interval: DateInterval) -> Double? {
        let scoped = entries
            .filter { $0.bodyMetricDefinition?.id == definitionID && interval.contains($0.recordedAt) }
            .sorted { $0.recordedAt < $1.recordedAt }
        guard let first = scoped.first, let last = scoped.last, first.id != last.id else { return nil }
        return last.value - first.value
    }
}
