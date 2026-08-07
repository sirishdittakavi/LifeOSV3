import Foundation
import UserNotifications

enum ReminderService {
    static func updateReminders(for category: AppCategory, activities: [Activity]) async {
        let center = UNUserNotificationCenter.current()
        let identifiers = reminderIdentifiers(category: category, activities: activities)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        guard category.shouldScheduleReminders else { return }

        do {
            let allowed = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard allowed else { return }

            for activity in activities where activity.isActive {
                try await schedule(activity: activity, category: category, center: center)
            }

            let reviewContent = UNMutableNotificationContent()
            reviewContent.title = "Review \(category.name)"
            if let profileName = category.profile?.name {
                reviewContent.subtitle = profileName
            }
            reviewContent.body = "Check whether this week's target is complete, on track, or needs rescheduling."
            reviewContent.sound = .default
            let reviewComponents = DateComponents(
                calendar: .current,
                timeZone: .current,
                hour: category.reminderHour,
                minute: category.reminderMinute,
                weekday: 1
            )
            try await center.add(UNNotificationRequest(
                identifier: "category.\(category.id.uuidString).weekly-review",
                content: reviewContent,
                trigger: UNCalendarNotificationTrigger(dateMatching: reviewComponents, repeats: true)
            ))
        } catch {
            // Reminder permission and scheduling errors never block local tracking.
        }
    }

    private static func schedule(
        activity: Activity,
        category: AppCategory,
        center: UNUserNotificationCenter
    ) async throws {
        let content = UNMutableNotificationContent()
        let actionCategory = activity.category ?? category
        content.title = activity.name
        if let profileName = activity.profile?.name ?? category.profile?.name {
            content.subtitle = profileName
        }
        content.body = "\(actionCategory.name) · This action supports the weekly improvement target."
        content.sound = .default

        switch activity.repeatType {
        case .daily:
            try await addDailyReminder(
                activity: activity, content: content, minuteOfDay: activity.plannedStartMinutes,
                identifierSuffix: "daily", center: center
            )
        case .selectedWeekdays:
            for weekday in activity.weekdays {
                try await addWeeklyReminder(
                    activity: activity, content: content, weekday: weekday,
                    minuteOfDay: activity.plannedStartMinutes,
                    identifierSuffix: "weekday.\(weekday)", center: center
                )
            }
        case .timesPerDay:
            let startMinutes = repeatedMinutes(
                count: activity.occurrencesPerDay,
                first: activity.plannedStartMinutes,
                interval: activity.repeatIntervalMinutes
            )
            for (index, minuteOfDay) in startMinutes.enumerated() {
                try await addDailyReminder(
                    activity: activity, content: content, minuteOfDay: minuteOfDay,
                    identifierSuffix: "multiple-daily.\(index)", center: center
                )
            }
        case .timesPerWeek:
            let weekdays = activity.weekdays.isEmpty
                ? PlanningService.distributedWeekdays(count: activity.occurrencesPerWeek)
                : Array(Set(activity.weekdays)).sorted()
            let total = max(1, activity.occurrencesPerWeek)
            for (weekdayIndex, weekday) in weekdays.enumerated() {
                let count = total / weekdays.count + (weekdayIndex < total % weekdays.count ? 1 : 0)
                let startMinutes = repeatedMinutes(
                    count: count,
                    first: activity.plannedStartMinutes,
                    interval: activity.repeatIntervalMinutes
                )
                for (occurrenceIndex, minuteOfDay) in startMinutes.enumerated() {
                    try await addWeeklyReminder(
                        activity: activity, content: content, weekday: weekday,
                        minuteOfDay: minuteOfDay,
                        identifierSuffix: "weekly.\(weekday).\(occurrenceIndex)", center: center
                    )
                }
            }
        case .once:
            let hour = activity.plannedStartMinutes / 60
            let minute = activity.plannedStartMinutes % 60
            var components = Calendar.current.dateComponents([.year, .month, .day], from: activity.startDate)
            components.hour = hour
            components.minute = minute
            guard let fireDate = Calendar.current.date(from: components), fireDate > .now else { return }
            try await center.add(UNNotificationRequest(
                identifier: "activity.\(activity.id.uuidString).once",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            ))
        }
    }

    private static func addDailyReminder(
        activity: Activity,
        content: UNNotificationContent,
        minuteOfDay: Int,
        identifierSuffix: String,
        center: UNUserNotificationCenter
    ) async throws {
        let components = DateComponents(
            calendar: .current, timeZone: .current,
            hour: minuteOfDay / 60, minute: minuteOfDay % 60
        )
        try await center.add(UNNotificationRequest(
            identifier: "activity.\(activity.id.uuidString).\(identifierSuffix)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        ))
    }

    private static func addWeeklyReminder(
        activity: Activity,
        content: UNNotificationContent,
        weekday: Int,
        minuteOfDay: Int,
        identifierSuffix: String,
        center: UNUserNotificationCenter
    ) async throws {
        let components = DateComponents(
            calendar: .current, timeZone: .current,
            hour: minuteOfDay / 60, minute: minuteOfDay % 60, weekday: weekday
        )
        try await center.add(UNNotificationRequest(
            identifier: "activity.\(activity.id.uuidString).\(identifierSuffix)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        ))
    }

    private static func repeatedMinutes(count: Int, first: Int, interval: Int) -> [Int] {
        guard count > 0 else { return [] }
        return (0..<count)
            .map { first + ($0 * max(1, interval)) }
            .filter { $0 < 24 * 60 }
    }

    private static func reminderIdentifiers(category: AppCategory, activities: [Activity]) -> [String] {
        var identifiers = ["category.\(category.id.uuidString).weekly-review"]
        for activity in activities {
            identifiers.append("activity.\(activity.id.uuidString).daily")
            identifiers.append("activity.\(activity.id.uuidString).once")
            identifiers.append(contentsOf: (1...7).map { "activity.\(activity.id.uuidString).weekday.\($0)" })
            identifiers.append(contentsOf: (0..<64).map { "activity.\(activity.id.uuidString).multiple-daily.\($0)" })
            for weekday in 1...7 {
                identifiers.append(contentsOf: (0..<64).map {
                    "activity.\(activity.id.uuidString).weekly.\(weekday).\($0)"
                })
            }
        }
        return identifiers
    }
}

enum GoalReminderService {
    static func updateReminder(for measure: ResultMeasure) async {
        let center = UNUserNotificationCenter.current()
        let identifier = "result-measure.\(measure.id.uuidString).check-in"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard measure.shouldScheduleReminder,
              let nextDate = measure.nextCheckInDate else { return }

        do {
            let allowed = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard allowed else { return }

            let content = UNMutableNotificationContent()
            content.title = "Result check-in: \(measure.name)"
            if let profileName = measure.goal?.profile?.name {
                content.subtitle = profileName
            }
            content.body = "Enter the latest result for \(measure.goal?.name ?? "this Goal") to see whether the plan is working."
            content.sound = .default

            var components = Calendar.current.dateComponents([.year, .month, .day], from: nextDate)
            components.hour = measure.reminderHour
            components.minute = measure.reminderMinute
            guard let fireDate = Calendar.current.date(from: components), fireDate > .now else { return }

            try await center.add(UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            ))
        } catch {
            // Result reminders never block saving a Goal or check-in.
        }
    }
}
