//
//  NotificationRouter.swift
//  LifeOS
//
//  Owns local-notification identity end to end: registers the actionable
//  "Complete"/"Skip" category, and resolves a tapped/actioned notification
//  back to the exact CalendarItem it was for — using the profileID +
//  activityID + occurrence payload ReminderService embeds (LifeOS fix pass:
//  Notification Ownership), never a title/name match. A default tap
//  publishes a deep link for RootTabView to switch to the right Profile and
//  Today tab; a Complete/Skip action mutates the store directly through the
//  same CalendarRepository/TodayViewModel boundary the UI uses, so it can
//  never diverge from what tapping the on-screen row would have done.
//
//  Excluded from the headless SPM package (see Package.swift), like
//  ReminderService.swift — UNUserNotificationCenterDelegate needs a real
//  notification runtime. The actual profile/activity/occurrence resolution
//  logic (the part a leak could hide in) lives in
//  PlanningService.resolveCalendarItem, a plain dependency-free function
//  that IS unit-tested — see PlanningServiceTests.swift.
//

import Foundation
import UserNotifications
import SwiftData

@MainActor
final class NotificationRouter: NSObject, ObservableObject {
    static let shared = NotificationRouter()

    static let activityCategoryIdentifier = "activity-occurrence"
    static let completeActionIdentifier = "LIFEOS_COMPLETE"
    static let skipActionIdentifier = "LIFEOS_SKIP"
    static let profileIDKey = "profileID"
    static let activityIDKey = "activityID"
    static let occurrenceKey = "occurrence"

    struct DeepLink: Equatable {
        let profileID: UUID
        let activityID: UUID
        let occurrence: Date
    }

    /// Set by RootTabView after handling, so the same tap doesn't re-fire.
    @Published var pendingDeepLink: DeepLink?

    private var container: ModelContainer?

    private override init() { super.init() }

    func configure(container: ModelContainer) {
        self.container = container
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.activityCategoryIdentifier,
                actions: [
                    UNNotificationAction(identifier: Self.completeActionIdentifier, title: "Complete", options: []),
                    UNNotificationAction(identifier: Self.skipActionIdentifier, title: "Skip", options: [])
                ],
                intentIdentifiers: [],
                options: []
            )
        ])
    }

    private func handle(actionIdentifier: String, userInfo: [AnyHashable: Any]) {
        guard
            let profileIDString = userInfo[Self.profileIDKey] as? String, let profileID = UUID(uuidString: profileIDString),
            let activityIDString = userInfo[Self.activityIDKey] as? String, let activityID = UUID(uuidString: activityIDString),
            let occurrenceString = userInfo[Self.occurrenceKey] as? String,
            let occurrence = ISO8601DateFormatter().date(from: occurrenceString)
        else { return }

        switch actionIdentifier {
        case Self.completeActionIdentifier:
            performOwned(profileID: profileID, activityID: activityID, occurrence: occurrence) { item, repository in
                _ = TodayViewModel(
                    profile: item.profile, items: [item], activities: [], resultMeasures: [],
                    currentTime: .now, repository: repository
                ).quickFinish(item, at: .now)
                ReminderService.cancelReminder(activityID: activityID, occurrence: occurrence)
            }
        case Self.skipActionIdentifier:
            performOwned(profileID: profileID, activityID: activityID, occurrence: occurrence) { item, repository in
                TodayViewModel(
                    profile: item.profile, items: [item], activities: [], resultMeasures: [],
                    currentTime: .now, repository: repository
                ).skip(item)
                ReminderService.cancelReminder(activityID: activityID, occurrence: occurrence)
            }
        default:
            // Default tap (or "View"): hand off to RootTabView rather than
            // acting here — opening the right screen is UI-layer work.
            pendingDeepLink = DeepLink(profileID: profileID, activityID: activityID, occurrence: occurrence)
        }
    }

    private func performOwned(
        profileID: UUID, activityID: UUID, occurrence: Date,
        action: (CalendarItem, CalendarRepository) -> Void
    ) {
        guard let container else { return }
        let context = container.mainContext
        guard let items = try? context.fetch(FetchDescriptor<CalendarItem>(
            predicate: #Predicate { $0.activity?.id == activityID }
        )) else { return }
        guard let item = PlanningService.resolveCalendarItem(
            profileID: profileID, activityID: activityID, occurrence: occurrence, in: items
        ) else { return }
        action(item, SwiftDataCalendarRepository(context: context))
    }
}

extension NotificationRouter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            self.handle(actionIdentifier: actionIdentifier, userInfo: userInfo)
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
