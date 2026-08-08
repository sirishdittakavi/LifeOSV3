import Foundation

enum DashboardPeriod: String, CaseIterable, Identifiable {
    case day = "Today"
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }

    func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .day:
            let start = calendar.startOfDay(for: date)
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)!
        case .month:
            return calendar.dateInterval(of: .month, for: date)!
        }
    }
}

enum ImprovementStatus: String {
    case complete = "Complete"
    case onTrack = "On track"
    case needsAttention = "Needs attention"
    case behind = "Behind"
    case insufficientData = "Insufficient data"
    case notScheduled = "No target today"
}

enum ProgressConfidence: String {
    case high = "High confidence"
    case medium = "Medium confidence"
    case low = "Low confidence"
}

struct CategoryProgress: Identifiable {
    let category: AppCategory
    let period: DashboardPeriod
    let completedSessions: Int
    let targetSessions: Int
    let completedMinutes: Int
    let targetMinutes: Int
    let status: ImprovementStatus
    let confidence: ProgressConfidence
    let nextAction: String
    let decidedDueTasks: Int
    let dueTasks: Int

    var id: UUID { category.id }

    var sessionFraction: Double {
        guard targetSessions > 0 else { return 0 }
        return min(Double(completedSessions) / Double(targetSessions), 1)
    }

    var minuteFraction: Double? {
        guard targetMinutes > 0 else { return nil }
        return min(Double(completedMinutes) / Double(targetMinutes), 1)
    }

    var primaryFraction: Double {
        if targetSessions > 0 { return sessionFraction }
        return minuteFraction ?? 0
    }

    var progressText: String {
        var parts: [String] = []
        if targetSessions > 0 { parts.append("\(completedSessions)/\(targetSessions) sessions") }
        if targetMinutes > 0 { parts.append("\(completedMinutes)/\(targetMinutes) min") }
        return parts.isEmpty ? "No target configured" : parts.joined(separator: " · ")
    }
}

enum CategoryProgressEngine {
    static func progress(
        profile: Profile,
        category: AppCategory,
        includedCategoryIDs: Set<UUID>? = nil,
        period: DashboardPeriod,
        now: Date = .now,
        activities: [Activity],
        calendarItems: [CalendarItem],
        foodEntries: [FoodEntry],
        weightEntries: [WeightEntry],
        sportEntries: [SportEntry],
        calendar: Calendar = .current
    ) -> CategoryProgress {
        let interval = period.interval(containing: now, calendar: calendar)
        let categoryIDs = includedCategoryIDs ?? [category.id]
        let categoryActivities = activities.filter {
            $0.profile?.id == profile.id &&
            $0.category.map { categoryIDs.contains($0.id) } == true &&
            $0.isActive
        }
        let categoryItems = calendarItems.filter {
            $0.profile?.id == profile.id &&
            $0.activity?.category.map { categoryIDs.contains($0.id) } == true &&
            interval.contains($0.date)
        }
        let completedItems = categoryItems.filter { $0.status == .done }

        let scheduledDates = dates(in: interval, calendar: calendar)
        let scheduledOccurrences = scheduledDates.flatMap { date in
            categoryActivities.flatMap { activity in
                PlanningService.scheduledStartMinutes(activity, on: date, calendar: calendar).compactMap { minute in
                    calendar.date(byAdding: .minute, value: minute, to: calendar.startOfDay(for: date)).map {
                        (activity: activity, plannedStart: $0)
                    }
                }
            }
        }
        let scheduledThroughNow = scheduledOccurrences.filter { $0.plannedStart <= now }.count
        let futureScheduled = scheduledOccurrences.filter { $0.plannedStart > now }.count
        let decidedDueTasks = categoryItems.filter {
            $0.date <= now && ($0.status == .done || $0.status == .skipped || $0.status == .rescheduled)
        }.count

        let trackingKind = category.trackingKind
        let isNutrition = trackingKind == .nutrition
        let isWeight = trackingKind == .bodyWeight
        let isSport = trackingKind == .sport

        let periodFood = foodEntries.filter { $0.profile?.id == profile.id && interval.contains($0.date) }
        let foodDays = Set(periodFood.map { calendar.startOfDay(for: $0.date) }).count
        let periodWeights = weightEntries.filter { $0.profile?.id == profile.id && interval.contains($0.date) }
        let periodSport = sportEntries.filter { entry in
            guard entry.profile?.id == profile.id && interval.contains(entry.date) else { return false }
            return entry.category.map { categoryIDs.contains($0.id) } == true
        }

        var completedSessions = completedItems.count
        var completedMinutes = completedItems.reduce(0) { total, item in
            let actualMinutes = item.actualStart.flatMap { start in
                item.actualEnd.map { end in max(Int(end.timeIntervalSince(start) / 60), 0) }
            }
            return total + (actualMinutes ?? item.activity?.estimatedDurationMinutes ?? 0)
        }

        if isNutrition { completedSessions = foodDays }
        if isWeight { completedSessions = periodWeights.count }
        if isSport {
            completedSessions = max(completedSessions, periodSport.count)
            completedMinutes = max(completedMinutes, periodSport.reduce(0) { $0 + $1.durationMinutes })
        }

        let targetSessions: Int
        let targetMinutes: Int
        switch period {
        case .day:
            if isNutrition {
                targetSessions = 1
                targetMinutes = 0
            } else {
                targetSessions = scheduledOccurrences.count
                targetMinutes = scheduledOccurrences.reduce(0) { $0 + $1.activity.estimatedDurationMinutes }
            }
        case .week:
            targetSessions = category.weeklyTargetSessions
            targetMinutes = category.weeklyTargetMinutes
        case .month:
            let dayCount = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 30
            targetSessions = Int(ceil(Double(category.weeklyTargetSessions) * Double(dayCount) / 7.0))
            targetMinutes = Int(ceil(Double(category.weeklyTargetMinutes) * Double(dayCount) / 7.0))
        }

        let elapsedFraction = max(0, min(now.timeIntervalSince(interval.start) / interval.duration, 1))
        let expectedSessions = Double(targetSessions) * elapsedFraction
        let remainingDays = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: interval.end).day ?? 0)
        let flexibleFuture = (isNutrition || isWeight || isSport) ? remainingDays : 0
        let potentialSessions = completedSessions + max(futureScheduled, flexibleFuture)

        let status: ImprovementStatus
        if targetSessions == 0 && targetMinutes == 0 {
            status = period == .day ? .notScheduled : .insufficientData
        } else if completedSessions >= targetSessions && (targetMinutes == 0 || completedMinutes >= targetMinutes) {
            status = .complete
        } else if Double(completedSessions) >= expectedSessions * 0.85 {
            status = .onTrack
        } else if potentialSessions >= targetSessions {
            status = .needsAttention
        } else {
            status = .behind
        }

        let confidence: ProgressConfidence
        if status == .complete {
            confidence = .high
        } else if scheduledThroughNow > 0 {
            let completeness = Double(decidedDueTasks) / Double(scheduledThroughNow)
            confidence = completeness >= 0.8 ? .high : (completeness >= 0.4 ? .medium : .low)
        } else if isNutrition || isWeight || isSport || !categoryActivities.isEmpty {
            confidence = completedSessions > 0 ? .high : .medium
        } else {
            confidence = .low
        }

        let remaining = max(0, targetSessions - completedSessions)
        let nextAction: String
        switch status {
        case .complete:
            nextAction = "Target reached. No catch-up needed."
        case .onTrack:
            nextAction = remaining > 0 ? "\(remaining) session\(remaining == 1 ? "" : "s") remaining." : "Keep the current plan."
        case .needsAttention:
            nextAction = "Schedule or complete \(remaining) more session\(remaining == 1 ? "" : "s")."
        case .behind:
            nextAction = "The current schedule cannot meet the target. Reschedule or revise it."
        case .insufficientData:
            nextAction = "Add tasks or record activity before judging progress."
        case .notScheduled:
            nextAction = "Nothing is scheduled for this category today."
        }

        return CategoryProgress(
            category: category,
            period: period,
            completedSessions: completedSessions,
            targetSessions: targetSessions,
            completedMinutes: completedMinutes,
            targetMinutes: targetMinutes,
            status: status,
            confidence: confidence,
            nextAction: nextAction,
            decidedDueTasks: decidedDueTasks,
            dueTasks: scheduledThroughNow
        )
    }

    private static func dates(in interval: DateInterval, calendar: Calendar) -> [Date] {
        var dates: [Date] = []
        var current = calendar.startOfDay(for: interval.start)
        while current < interval.end {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }
}

// MARK: - Goal outcome and supporting-effort comparison

enum GoalProgressStatus: String {
    case achieved = "Goal reached"
    case onTrack = "On track"
    case needsAttention = "Needs review"
    case awaitingResult = "Awaiting result"
    case notEnoughEvidence = "Too early to judge"
}

struct GoalContributionProgress: Identifiable {
    let contribution: GoalAreaContribution
    let completedActions: Int
    let plannedActions: Int
    let completedMinutes: Int
    let plannedMinutes: Int

    var id: UUID { contribution.id }
    var adherenceFraction: Double? {
        guard plannedActions > 0 else { return nil }
        return min(Double(completedActions) / Double(plannedActions), 1)
    }
}

struct GoalProgress: Identifiable {
    let goal: Goal
    let primaryMeasure: ResultMeasure?
    let latestEntry: ResultEntry?
    let previousEntry: ResultEntry?
    let resultFraction: Double?
    let effortFraction: Double?
    let status: GoalProgressStatus
    let confidence: ProgressConfidence
    let nextAction: String
    let contributions: [GoalContributionProgress]

    var id: UUID { goal.id }

    var resultSummary: String {
        guard let measure = primaryMeasure else { return "Add a primary result measure" }
        guard let entry = latestEntry else {
            if let baseline = measure.baselineValue {
                let suffix = measure.unit.isEmpty ? "" : " \(measure.unit)"
                return "Baseline \(format(baseline))\(suffix)"
            }
            return "No result entered yet"
        }
        let latest = entry.numericValue.map(format) ?? entry.textValue
        let suffix = measure.unit.isEmpty ? "" : " \(measure.unit)"
        return "Latest \(latest)\(suffix)"
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

enum GoalProgressEngine {
    static func progress(
        goal: Goal,
        period: DashboardPeriod,
        now: Date = .now,
        categories: [AppCategory],
        contributions: [GoalAreaContribution],
        measures: [ResultMeasure],
        entries: [ResultEntry],
        activities: [Activity],
        calendarItems: [CalendarItem],
        calendar: Calendar = .current
    ) -> GoalProgress {
        let goalContributions = contributions.filter { $0.goal?.id == goal.id && $0.isActive }
        let interval = period.interval(containing: now, calendar: calendar)
        let dates = dates(in: interval, calendar: calendar)

        let contributionProgress = goalContributions.compactMap { contribution -> GoalContributionProgress? in
            guard let category = contribution.category else { return nil }
            let includedIDs = CategoryHierarchy.idsIncludingDescendants(of: category, in: categories)
            let includedActivities = activities.filter {
                $0.isActive && $0.category.map { includedIDs.contains($0.id) } == true
            }
            let planned = dates.reduce(0) { count, date in
                count + includedActivities.reduce(0) {
                    $0 + PlanningService.scheduledStartMinutes($1, on: date, calendar: calendar).count
                }
            }
            let items = PlanningService.plannedItems(calendarItems.filter {
                interval.contains($0.date) &&
                $0.activity?.category.map { includedIDs.contains($0.id) } == true
            })
            let completed = items.filter { $0.status == .done }
            return GoalContributionProgress(
                contribution: contribution,
                completedActions: completed.count,
                plannedActions: max(planned, items.count),
                completedMinutes: completed.reduce(0) { total, item in
                    if let start = item.actualStart, let end = item.actualEnd, end > start {
                        return total + max(1, Int(end.timeIntervalSince(start) / 60))
                    }
                    return total + (item.activity?.estimatedDurationMinutes ?? 0)
                },
                plannedMinutes: dates.reduce(0) { total, date in
                    total + includedActivities.reduce(0) { partial, activity in
                        partial + PlanningService.scheduledStartMinutes(activity, on: date, calendar: calendar).count
                            * activity.estimatedDurationMinutes
                    }
                }
            )
        }

        let effortValues = contributionProgress.compactMap(\.adherenceFraction)
        let effortFraction = effortValues.isEmpty ? nil : effortValues.reduce(0, +) / Double(effortValues.count)
        let goalMeasures = measures.filter { $0.goal?.id == goal.id && $0.isActive }
        let primary = goalMeasures.first(where: { $0.role == .primary }) ?? goalMeasures.first
        let resultEntries = primary.map { measure in
            entries.filter { $0.measure?.id == measure.id }.sorted { $0.date < $1.date }
        } ?? []
        let latest = resultEntries.last
        let previous = resultEntries.dropLast().last
        let outcomeFraction: Double?
        if let primary {
            outcomeFraction = resultFraction(for: primary, latest: latest)
        } else {
            outcomeFraction = nil
        }
        let achieved = primary.map { isAchieved(measure: $0, latest: latest) } ?? false
        let validPrimaryTarget = primary.map { measure in
            ResultMeasureValidation.isValidTarget(
                valueType: measure.valueType,
                direction: measure.direction,
                baseline: measure.baselineValue,
                target: measure.targetValue,
                minimum: measure.targetMinimum,
                maximum: measure.targetMaximum
            )
        } ?? false

        let evidenceCount = resultEntries.count + (primary?.baselineValue == nil ? 0 : 1)
        let confidence: ProgressConfidence = evidenceCount >= 3 ? .high : (evidenceCount >= 1 ? .medium : .low)
        let status: GoalProgressStatus
        let nextAction: String

        if primary == nil {
            status = .awaitingResult
            nextAction = "Add a measurable result so this Goal can be evaluated."
        } else if !validPrimaryTarget {
            status = .needsAttention
            nextAction = "Correct the Result baseline and target before evaluating this Goal."
        } else if latest == nil {
            status = .awaitingResult
            nextAction = "Enter the first result check-in. Action completion alone cannot prove improvement."
        } else if achieved {
            status = .achieved
            nextAction = "Target reached. Review whether to maintain it or set the next Goal."
        } else if primary?.valueType == .text {
            status = .notEnoughEvidence
            nextAction = "Review the written evidence. Add a numeric, rating or milestone Result if you need an on-track comparison."
        } else if evidenceCount < 2 {
            status = .notEnoughEvidence
            nextAction = "Keep following the plan and add the next scheduled result."
        } else if let targetDate = goal.targetDate,
                  let fraction = outcomeFraction,
                  targetDate > goal.createdAt {
            let elapsed = min(max(now.timeIntervalSince(goal.createdAt) / targetDate.timeIntervalSince(goal.createdAt), 0), 1)
            if fraction + 0.10 >= elapsed {
                status = .onTrack
                nextAction = "The measured result is moving at a reasonable pace toward the target."
            } else {
                status = .needsAttention
                nextAction = "The result is behind the target pace. Review the supporting Areas and Actions."
            }
        } else if let latestValue = latest?.numericValue,
                  let baseline = primary?.baselineValue,
                  isMovingInDesiredDirection(latestValue, from: baseline, measure: primary!) {
            status = .onTrack
            nextAction = "The result is moving in the desired direction. Continue until the next check-in."
        } else {
            status = .needsAttention
            nextAction = "The result is not yet moving toward the target. Review the plan after more evidence."
        }

        return GoalProgress(
            goal: goal, primaryMeasure: primary, latestEntry: latest, previousEntry: previous,
            resultFraction: outcomeFraction, effortFraction: effortFraction,
            status: status, confidence: confidence, nextAction: nextAction,
            contributions: contributionProgress
        )
    }

    private static func resultFraction(for measure: ResultMeasure, latest: ResultEntry?) -> Double? {
        guard let value = latest?.numericValue ?? measure.baselineValue else { return nil }
        switch measure.valueType {
        case .milestone:
            return value >= 1 ? 1 : 0
        case .text:
            return nil
        case .rating, .number:
            guard ResultMeasureValidation.isValidTarget(
                valueType: measure.valueType,
                direction: measure.direction,
                baseline: measure.baselineValue,
                target: measure.targetValue,
                minimum: measure.targetMinimum,
                maximum: measure.targetMaximum
            ) else { return nil }
            switch measure.direction {
            case .increase:
                guard let baseline = measure.baselineValue, let target = measure.targetValue,
                      target > baseline else { return nil }
                return min(max((value - baseline) / (target - baseline), 0), 1)
            case .decrease:
                guard let baseline = measure.baselineValue, let target = measure.targetValue,
                      target < baseline else { return nil }
                return min(max((baseline - value) / (baseline - target), 0), 1)
            case .targetRange, .maintainRange:
                guard let minimum = measure.targetMinimum, let maximum = measure.targetMaximum else { return nil }
                if (minimum...maximum).contains(value) { return 1 }
                guard let baseline = measure.baselineValue else { return 0 }
                let boundary = value < minimum ? minimum : maximum
                let initialDistance = abs(baseline - boundary)
                guard initialDistance > 0 else { return 0 }
                return min(max(1 - abs(value - boundary) / initialDistance, 0), 1)
            }
        }
    }

    private static func isAchieved(measure: ResultMeasure, latest: ResultEntry?) -> Bool {
        guard let value = latest?.numericValue else { return false }
        switch measure.valueType {
        case .milestone: return value >= 1
        case .text: return false
        case .rating, .number:
            guard ResultMeasureValidation.isValidTarget(
                valueType: measure.valueType,
                direction: measure.direction,
                baseline: measure.baselineValue,
                target: measure.targetValue,
                minimum: measure.targetMinimum,
                maximum: measure.targetMaximum
            ) else { return false }
            switch measure.direction {
            case .increase:
                guard let baseline = measure.baselineValue, let target = measure.targetValue,
                      target > baseline else { return false }
                return value >= target
            case .decrease:
                guard let baseline = measure.baselineValue, let target = measure.targetValue,
                      target < baseline else { return false }
                return value <= target
            case .targetRange, .maintainRange:
                guard let minimum = measure.targetMinimum, let maximum = measure.targetMaximum else { return false }
                return (minimum...maximum).contains(value)
            }
        }
    }

    private static func isMovingInDesiredDirection(_ value: Double, from baseline: Double, measure: ResultMeasure) -> Bool {
        switch measure.direction {
        case .increase: return value > baseline
        case .decrease: return value < baseline
        case .targetRange, .maintainRange:
            guard let minimum = measure.targetMinimum, let maximum = measure.targetMaximum else { return false }
            let baselineDistance = baseline < minimum ? minimum - baseline : (baseline > maximum ? baseline - maximum : 0)
            let valueDistance = value < minimum ? minimum - value : (value > maximum ? value - maximum : 0)
            return valueDistance < baselineDistance
        }
    }

    private static func dates(in interval: DateInterval, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var date = calendar.startOfDay(for: interval.start)
        while date < interval.end {
            result.append(date)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return result
    }
}
