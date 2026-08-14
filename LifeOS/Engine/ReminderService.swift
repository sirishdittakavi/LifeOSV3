import Foundation
import UserNotifications

enum ReminderService {
    static func updateReminders(for category: AppCategory, activities: [Activity]) async {
        let center = UNUserNotificationCenter.current()
        let activityPrefixes = activities.map { "activity.\($0.id.uuidString)." }
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { identifier in
            identifier == "category.\(category.id.uuidString).weekly-review" ||
            activityPrefixes.contains { identifier.hasPrefix($0) }
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        guard category.shouldScheduleReminders else { return }

        do {
            let allowed = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard allowed else { return }

            let planned = activities
                .filter(\.isActive)
                .flatMap { activity in
                    PlanningService.reminderOccurrenceDates(for: activity).map { (activity, $0) }
                }
                .sorted { $0.1 < $1.1 }
                .prefix(48)
            for (activity, date) in planned {
                try await schedule(activity: activity, category: category, date: date, center: center)
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
        date: Date,
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
        content.categoryIdentifier = NotificationRouter.activityCategoryIdentifier
        // The tap/action payload carries stable identity (profile + activity +
        // exact occurrence) so routing/actions never depend on title text —
        // two profiles' identically-named Activities have different IDs here.
        if let profileID = activity.profile?.id {
            content.userInfo = [
                NotificationRouter.profileIDKey: profileID.uuidString,
                NotificationRouter.activityIDKey: activity.id.uuidString,
                NotificationRouter.occurrenceKey: ISO8601DateFormatter().string(from: date)
            ]
        }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date
        )
        try await center.add(UNNotificationRequest(
            identifier: identifier(activityID: activity.id, occurrence: date),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        ))
    }

    /// Shared with `cancelReminder` so the identifier used to schedule an
    /// occurrence's reminder and the identifier used to cancel it can never
    /// silently drift apart.
    private static func identifier(activityID: UUID, occurrence date: Date) -> String {
        "activity.\(activityID.uuidString).\(Int(date.timeIntervalSince1970))"
    }

    /// Cancels one specific occurrence's already-scheduled reminder — called
    /// when that occurrence is completed or skipped, so a decided Task never
    /// still fires a "do this" reminder afterward. A no-op if nothing was
    /// pending for that exact (activity, occurrence) pair.
    static func cancelReminder(activityID: UUID, occurrence date: Date) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier(activityID: activityID, occurrence: date)]
        )
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
