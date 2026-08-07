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

        let lowerName = category.name.lowercased()
        let isNutrition = lowerName.contains("nutrition") || lowerName.contains("food")
        let isWeight = lowerName.contains("weight") || lowerName.contains("body development") || lowerName.contains("body composition")
        let isSport = category.pillar == .sport

        let periodFood = foodEntries.filter { $0.profile?.id == profile.id && interval.contains($0.date) }
        let foodDays = Set(periodFood.map { calendar.startOfDay(for: $0.date) }).count
        let periodWeights = weightEntries.filter { $0.profile?.id == profile.id && interval.contains($0.date) }
        let periodSport = sportEntries.filter { entry in
            guard entry.profile?.id == profile.id && interval.contains(entry.date) else { return false }
            return entry.category.map { categoryIDs.contains($0.id) } == true
        }

        var completedSessions = completedItems.count
        var completedMinutes = completedItems.reduce(0) {
            $0 + ($1.activity?.estimatedDurationMinutes ?? 0)
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
