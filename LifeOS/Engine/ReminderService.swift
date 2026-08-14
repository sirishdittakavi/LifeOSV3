//
//  ReminderService.swift
//  LifeOS
//
//  Release pass: Notification Ownership. All decision logic (what to
//  schedule, what to cancel, what identity payload each reminder carries)
//  now lives here as plain data transformations against the injectable
//  NotificationScheduling seam, instead of calling UNUserNotificationCenter
//  directly — so this file is UN*-free and unit-testable in the headless
//  package (see NotificationOwnershipTests.swift). Production call sites
//  pass RealNotificationCenter.shared; tests pass a FakeNotificationCenter.
//

import Foundation

enum ReminderService {
    static func updateReminders(for category: AppCategory, activities: [Activity], center: NotificationScheduling) async {
        let activityPrefixes = activities.map { "activity.\($0.id.uuidString)." }
        let pending = await center.pendingRequests()
        let identifiersToCancel = pending.map(\.identifier).filter { identifier in
            identifier == categoryReviewIdentifier(categoryID: category.id) ||
            activityPrefixes.contains { identifier.hasPrefix($0) }
        }
        center.removePending(withIdentifiers: identifiersToCancel)
        guard category.shouldScheduleReminders else { return }
        guard await center.requestAuthorization() else { return }

        let planned = activities
            .filter(\.isActive)
            .flatMap { activity in
                PlanningService.reminderOccurrenceDates(for: activity).map { (activity, $0) }
            }
            .sorted { $0.1 < $1.1 }
            .prefix(48)
        for (activity, date) in planned {
            await center.add(activityRequest(activity: activity, category: category, date: date))
        }

        await center.add(PendingNotificationRequest(
            identifier: categoryReviewIdentifier(categoryID: category.id),
            categoryIdentifier: "category-weekly-review",
            title: "Review \(category.name)",
            subtitle: category.profile?.name ?? "",
            body: "Check whether this week's target is complete, on track, or needs rescheduling.",
            triggerDateComponents: DateComponents(hour: category.reminderHour, minute: category.reminderMinute, weekday: 1),
            repeats: true,
            payload: NotificationOwnershipPayload(profileID: category.profile?.id, activityID: nil, occurrence: nil)
        ))
    }

    private static func activityRequest(activity: Activity, category: AppCategory, date: Date) -> PendingNotificationRequest {
        let actionCategory = activity.category ?? category
        return PendingNotificationRequest(
            identifier: identifier(activityID: activity.id, occurrence: date),
            categoryIdentifier: NotificationIdentifiers.activityCategoryIdentifier,
            title: activity.name,
            subtitle: activity.profile?.name ?? category.profile?.name ?? "",
            body: "\(actionCategory.name) · This action supports the weekly improvement target.",
            triggerDateComponents: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            repeats: false,
            // The tap/action payload carries stable identity (profile + activity +
            // exact occurrence) so routing/actions never depend on title text —
            // two profiles' identically-named Activities have different IDs here.
            payload: NotificationOwnershipPayload(profileID: activity.profile?.id, activityID: activity.id, occurrence: date)
        )
    }

    /// Shared with `cancelReminder` so the identifier used to schedule an
    /// occurrence's reminder and the identifier used to cancel it can never
    /// silently drift apart.
    static func identifier(activityID: UUID, occurrence date: Date) -> String {
        "activity.\(activityID.uuidString).\(Int(date.timeIntervalSince1970))"
    }

    static func categoryReviewIdentifier(categoryID: UUID) -> String {
        "category.\(categoryID.uuidString).weekly-review"
    }

    /// Cancels one specific occurrence's already-scheduled reminder — called
    /// when that occurrence is completed or skipped, so a decided Task never
    /// still fires a "do this" reminder afterward. A no-op if nothing was
    /// pending for that exact (activity, occurrence) pair.
    static func cancelReminder(activityID: UUID, occurrence date: Date, center: NotificationScheduling) {
        center.removePending(withIdentifiers: [identifier(activityID: activityID, occurrence: date)])
    }

    /// Cancels EVERY pending reminder for one Activity, regardless of
    /// occurrence. Call this when an Activity is hard-deleted (no history) —
    /// `updateReminders`'s own cancellation pass only removes requests for
    /// activities present in the array it's given, so a deleted Activity
    /// that's no longer passed anywhere would otherwise leave its
    /// already-scheduled reminders pending forever.
    static func cancelAllReminders(activityID: UUID, center: NotificationScheduling) async {
        let prefix = "activity.\(activityID.uuidString)."
        let pending = await center.pendingRequests()
        let toRemove = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePending(withIdentifiers: toRemove)
    }
}

enum GoalReminderService {
    static func updateReminder(for measure: ResultMeasure, center: NotificationScheduling) async {
        let identifier = identifier(measureID: measure.id)
        center.removePending(withIdentifiers: [identifier])
        guard measure.shouldScheduleReminder, let nextDate = measure.nextCheckInDate else { return }
        guard await center.requestAuthorization() else { return }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: nextDate)
        components.hour = measure.reminderHour
        components.minute = measure.reminderMinute
        guard let fireDate = Calendar.current.date(from: components), fireDate > .now else { return }

        await center.add(PendingNotificationRequest(
            identifier: identifier,
            categoryIdentifier: "goal-check-in",
            title: "Result check-in: \(measure.name)",
            subtitle: measure.goal?.profile?.name ?? "",
            body: "Enter the latest result for \(measure.goal?.name ?? "this Goal") to see whether the plan is working.",
            triggerDateComponents: components,
            repeats: false,
            payload: NotificationOwnershipPayload(profileID: measure.goal?.profile?.id, activityID: nil, occurrence: nil)
        ))
    }

    static func identifier(measureID: UUID) -> String {
        "result-measure.\(measureID.uuidString).check-in"
    }
}
