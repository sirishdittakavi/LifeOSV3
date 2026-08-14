//
//  NotificationScheduling.swift
//  LifeOS
//
//  Release pass: Notification Ownership. The injectable seam between
//  ReminderService/GoalReminderService/NotificationRouter's DECISION logic
//  (who gets scheduled/cancelled/routed, and why) and the real
//  UNUserNotificationCenter. Pure Swift, no UserNotifications import, so
//  it — and everything built on it — is unit-testable in the headless
//  package without a real notification runtime. RealNotificationCenter
//  (Engine/RealNotificationCenter.swift) is the only place that touches
//  UNUserNotificationCenter directly, and stays excluded from the headless
//  package like ReminderService always has been.
//

import Foundation

/// The stable identity a scheduled reminder carries for a specific
/// occurrence — profileID/activityID/occurrence, never a name/title. This is
/// exactly what NotificationRouter reads back out of a delivered
/// notification's payload.
struct NotificationOwnershipPayload: Equatable {
    var profileID: UUID?
    var activityID: UUID?
    var occurrence: Date?
}

/// A platform-neutral stand-in for `UNNotificationRequest` — everything
/// ReminderService/GoalReminderService need to describe a reminder, with
/// none of the UIKit/UserNotifications baggage.
struct PendingNotificationRequest: Equatable {
    var identifier: String
    var categoryIdentifier: String
    var title: String
    var subtitle: String
    var body: String
    /// The exact fire-time components (year/month/day/hour/minute, or a
    /// weekday-only pattern for the weekly review), matching what a real
    /// UNCalendarNotificationTrigger would be given.
    var triggerDateComponents: DateComponents
    var repeats: Bool
    var payload: NotificationOwnershipPayload
}

/// The seam ReminderService/GoalReminderService/NotificationRouter schedule
/// and cancel through. RealNotificationCenter (production) wraps
/// UNUserNotificationCenter.current(); FakeNotificationCenter (tests)
/// records everything in memory so ownership/isolation can be asserted
/// directly, per the release-pass requirement to test this without relying
/// entirely on a real UNUserNotificationCenter or XCUITest.
protocol NotificationScheduling: AnyObject {
    func requestAuthorization() async -> Bool
    func pendingRequests() async -> [PendingNotificationRequest]
    func add(_ request: PendingNotificationRequest) async
    func removePending(withIdentifiers identifiers: [String])
}

/// Shared notification-identifier constants — kept here (not in
/// NotificationRouter, which needs UNUserNotificationCenter and is excluded
/// from the headless package) so ReminderService can reference them while
/// staying UN*-free and unit-testable.
enum NotificationIdentifiers {
    static let activityCategoryIdentifier = "activity-occurrence"
    static let completeActionIdentifier = "LIFEOS_COMPLETE"
    static let skipActionIdentifier = "LIFEOS_SKIP"
}

/// Parses a delivered notification's raw userInfo dictionary back into a
/// complete ownership payload — pure, dependency-free, so "malformed
/// payload does nothing" is provable without a real notification runtime.
/// Returns nil for ANY missing or invalid field; NotificationRouter must
/// treat a nil result as a strict no-op (no mutation, no cancellation), not
/// fall back to a partial match or the currently-selected profile.
enum NotificationPayloadParser {
    static let profileIDKey = "profileID"
    static let activityIDKey = "activityID"
    static let occurrenceKey = "occurrence"

    static func parse(_ userInfo: [AnyHashable: Any]) -> NotificationOwnershipPayload? {
        guard
            let profileIDString = userInfo[profileIDKey] as? String, let profileID = UUID(uuidString: profileIDString),
            let activityIDString = userInfo[activityIDKey] as? String, let activityID = UUID(uuidString: activityIDString),
            let occurrenceString = userInfo[occurrenceKey] as? String,
            let occurrence = ISO8601DateFormatter().date(from: occurrenceString)
        else { return nil }
        return NotificationOwnershipPayload(profileID: profileID, activityID: activityID, occurrence: occurrence)
    }
}
