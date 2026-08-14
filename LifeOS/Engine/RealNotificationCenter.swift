//
//  RealNotificationCenter.swift
//  LifeOS
//
//  Release pass: Notification Ownership. The only file that touches
//  UNUserNotificationCenter directly — a thin translation layer between
//  ReminderService/NotificationRouter's platform-neutral
//  PendingNotificationRequest and the real UN* API. Excluded from the
//  headless package (see Package.swift), like ReminderService always was
//  before this pass, and NotificationRouter still is.
//

import Foundation
import UserNotifications

final class RealNotificationCenter: NotificationScheduling {
    static let shared = RealNotificationCenter()
    private let center = UNUserNotificationCenter.current()
    private let iso8601 = ISO8601DateFormatter()

    private init() {}

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func pendingRequests() async -> [PendingNotificationRequest] {
        await center.pendingNotificationRequests().map { request in
            let userInfo = request.content.userInfo
            return PendingNotificationRequest(
                identifier: request.identifier,
                categoryIdentifier: request.content.categoryIdentifier,
                title: request.content.title,
                subtitle: request.content.subtitle,
                body: request.content.body,
                triggerDateComponents: (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents ?? DateComponents(),
                repeats: request.trigger?.repeats ?? false,
                payload: NotificationOwnershipPayload(
                    profileID: (userInfo[NotificationRouter.profileIDKey] as? String).flatMap(UUID.init(uuidString:)),
                    activityID: (userInfo[NotificationRouter.activityIDKey] as? String).flatMap(UUID.init(uuidString:)),
                    occurrence: (userInfo[NotificationRouter.occurrenceKey] as? String).flatMap(iso8601.date(from:))
                )
            )
        }
    }

    func add(_ request: PendingNotificationRequest) async {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.subtitle = request.subtitle
        content.body = request.body
        content.sound = .default
        content.categoryIdentifier = request.categoryIdentifier

        var userInfo: [String: String] = [:]
        if let profileID = request.payload.profileID { userInfo[NotificationRouter.profileIDKey] = profileID.uuidString }
        if let activityID = request.payload.activityID { userInfo[NotificationRouter.activityIDKey] = activityID.uuidString }
        if let occurrence = request.payload.occurrence { userInfo[NotificationRouter.occurrenceKey] = iso8601.string(from: occurrence) }
        content.userInfo = userInfo

        let trigger = UNCalendarNotificationTrigger(dateMatching: request.triggerDateComponents, repeats: request.repeats)
        try? await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
    }

    func removePending(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
