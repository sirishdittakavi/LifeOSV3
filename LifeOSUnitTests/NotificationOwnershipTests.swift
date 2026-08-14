import XCTest
import SwiftData
@testable import LifeOS

/// LifeOS XCUITest and Notification Ownership Release Pass — Section 3.
/// Proves notification ownership/isolation without relying on a real
/// UNUserNotificationCenter, using the injectable NotificationScheduling
/// seam (ReminderService/GoalReminderService now depend on it instead of
/// calling UN* directly). "Parent" and "Child" below are two ordinary
/// Profiles with deliberately identical Area/Activity/Goal/measure names —
/// this repo's Relationship model is not wired into any UI (see the
/// Profile Isolation audit), so these tests exercise plain multi-profile
/// isolation, not a parent/child permission model.
private final class FakeNotificationCenter: NotificationScheduling {
    var authorizationGranted = true
    private(set) var addedRequests: [PendingNotificationRequest] = []
    private(set) var cancelledIdentifiers: [String] = []

    /// Currently-pending set, derived from add/remove calls — mirrors what
    /// UNUserNotificationCenter.pendingNotificationRequests() would return.
    private(set) var pending: [PendingNotificationRequest] = []

    func requestAuthorization() async -> Bool { authorizationGranted }

    func pendingRequests() async -> [PendingNotificationRequest] { pending }

    func add(_ request: PendingNotificationRequest) async {
        addedRequests.append(request)
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
    }

    func removePending(withIdentifiers identifiers: [String]) {
        cancelledIdentifiers.append(contentsOf: identifiers)
        pending.removeAll { identifiers.contains($0.identifier) }
    }
}

@MainActor
final class NotificationOwnershipTests: XCTestCase {
    // MARK: - Fixtures

    private struct Fixture {
        let parentProfile: Profile
        let childProfile: Profile
        let parentCategory: AppCategory
        let childCategory: AppCategory
        let parentActivity: Activity
        let childActivity: Activity
    }

    /// Parent and Child, with intentionally identical Area/Activity names
    /// and identical schedules — the exact trap the release pass calls out.
    private func makeFixture(startDate: Date = TestFixtures.date(2026, 6, 1)) -> Fixture {
        let parentProfile = Profile(name: "Parent", kind: .individual, colorToken: "blue")
        let childProfile = Profile(name: "Child", kind: .child, colorToken: "orange")
        let parentCategory = AppCategory(
            profile: parentProfile, name: "Baseball", symbol: "figure.baseball", colorToken: "blue",
            pillar: .sport, trackingKind: .sport
        )
        let childCategory = AppCategory(
            profile: childProfile, name: "Baseball", symbol: "figure.baseball", colorToken: "orange",
            pillar: .sport, trackingKind: .sport
        )
        parentCategory.reminderEnabled = true
        childCategory.reminderEnabled = true
        let parentActivity = Activity(
            profile: parentProfile, category: parentCategory, name: "Hitting Practice",
            repeatType: .daily, weekdays: Array(1...7),
            plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 30, startDate: startDate
        )
        let childActivity = Activity(
            profile: childProfile, category: childCategory, name: "Hitting Practice",
            repeatType: .daily, weekdays: Array(1...7),
            plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 30, startDate: startDate
        )
        return Fixture(
            parentProfile: parentProfile, childProfile: childProfile,
            parentCategory: parentCategory, childCategory: childCategory,
            parentActivity: parentActivity, childActivity: childActivity
        )
    }

    // MARK: - Unit: identifier construction / payload parsing

    func testActivityIdentifierIsUniquePerActivityAndOccurrence() {
        let idA = ReminderService.identifier(activityID: UUID(), occurrence: TestFixtures.date(2026, 6, 1, hour: 18))
        let idB = ReminderService.identifier(activityID: UUID(), occurrence: TestFixtures.date(2026, 6, 1, hour: 18))
        XCTAssertNotEqual(idA, idB, "two different Activities at the identical time must not collide")

        let activityID = UUID()
        let idSameActivityDifferentTime = ReminderService.identifier(activityID: activityID, occurrence: TestFixtures.date(2026, 6, 1, hour: 19))
        let idSameActivitySameTime1 = ReminderService.identifier(activityID: activityID, occurrence: TestFixtures.date(2026, 6, 1, hour: 18))
        let idSameActivitySameTime2 = ReminderService.identifier(activityID: activityID, occurrence: TestFixtures.date(2026, 6, 1, hour: 18))
        XCTAssertNotEqual(idSameActivitySameTime1, idSameActivityDifferentTime)
        XCTAssertEqual(idSameActivitySameTime1, idSameActivitySameTime2, "identical (activity, occurrence) must be deterministic/stable")
    }

    func testCategoryReviewAndGoalCheckInIdentifiersAreKeyedByOwnID() {
        let categoryA = UUID(); let categoryB = UUID()
        XCTAssertNotEqual(
            ReminderService.categoryReviewIdentifier(categoryID: categoryA),
            ReminderService.categoryReviewIdentifier(categoryID: categoryB)
        )
        let measureA = UUID(); let measureB = UUID()
        XCTAssertNotEqual(GoalReminderService.identifier(measureID: measureA), GoalReminderService.identifier(measureID: measureB))
    }

    func testPayloadParserAcceptsOnlyACompleteValidPayload() {
        let profileID = UUID().uuidString
        let activityID = UUID().uuidString
        let occurrence = ISO8601DateFormatter().string(from: TestFixtures.date(2026, 6, 1, hour: 18))

        XCTAssertNotNil(NotificationPayloadParser.parse([
            "profileID": profileID, "activityID": activityID, "occurrence": occurrence
        ]))
    }

    func testPayloadParserRejectsEveryFormOfMalformedPayload() {
        let profileID = UUID().uuidString
        let activityID = UUID().uuidString
        let occurrence = ISO8601DateFormatter().string(from: TestFixtures.date(2026, 6, 1, hour: 18))
        let valid: [AnyHashable: Any] = ["profileID": profileID, "activityID": activityID, "occurrence": occurrence]

        func without(_ key: String) -> [AnyHashable: Any] {
            var copy = valid; copy.removeValue(forKey: key); return copy
        }
        func replacing(_ key: String, with value: Any) -> [AnyHashable: Any] {
            var copy = valid; copy[key] = value; return copy
        }

        XCTAssertNil(NotificationPayloadParser.parse(without("profileID")), "missing profileID")
        XCTAssertNil(NotificationPayloadParser.parse(replacing("profileID", with: "not-a-uuid")), "invalid profileID")
        XCTAssertNil(NotificationPayloadParser.parse(without("activityID")), "missing activityID")
        XCTAssertNil(NotificationPayloadParser.parse(replacing("activityID", with: "not-a-uuid")), "invalid activityID")
        XCTAssertNil(NotificationPayloadParser.parse(without("occurrence")), "missing occurrence")
        XCTAssertNil(NotificationPayloadParser.parse(replacing("occurrence", with: "not-a-date")), "invalid occurrence timestamp")
        XCTAssertNil(NotificationPayloadParser.parse([:]), "completely empty payload")
    }

    /// Excludes the once-a-week "category review" identifier (unaffected by
    /// an Activity's own schedule change) so comparisons focus on the
    /// per-occurrence activity identifiers that should actually change.
    private func staleChildActivityIdentifiers(_ identifiers: Set<String>) -> Set<String> {
        identifiers.filter { !$0.contains("weekly-review") }
    }

    // MARK: - Scheduling isolation

    func testIdenticalParentAndChildTasksCreateSeparateNotificationRequests() async {
        let fixture = makeFixture()
        let parentCenter = FakeNotificationCenter()
        let childCenter = FakeNotificationCenter()

        await ReminderService.updateReminders(for: fixture.parentCategory, activities: [fixture.parentActivity], center: parentCenter)
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: childCenter)

        let parentActivityRequests = parentCenter.addedRequests.filter { $0.payload.activityID == fixture.parentActivity.id }
        let childActivityRequests = childCenter.addedRequests.filter { $0.payload.activityID == fixture.childActivity.id }
        XCTAssertFalse(parentActivityRequests.isEmpty)
        XCTAssertFalse(childActivityRequests.isEmpty)

        let parentIdentifiers = Set(parentActivityRequests.map(\.identifier))
        let childIdentifiers = Set(childActivityRequests.map(\.identifier))
        XCTAssertTrue(parentIdentifiers.isDisjoint(with: childIdentifiers), "identical name/time must still produce different identifiers")

        XCTAssertTrue(parentActivityRequests.allSatisfy { $0.payload.profileID == fixture.parentProfile.id })
        XCTAssertTrue(childActivityRequests.allSatisfy { $0.payload.profileID == fixture.childProfile.id })
        XCTAssertTrue(parentActivityRequests.allSatisfy { $0.payload.activityID == fixture.parentActivity.id })
        XCTAssertTrue(childActivityRequests.allSatisfy { $0.payload.activityID == fixture.childActivity.id })
    }

    /// Both profiles share ONE notification center in production (one
    /// device, one UNUserNotificationCenter) — this is the realistic
    /// shared-center configuration the isolation tests below use.
    func testSchedulingChildRemindersDoesNotReplaceParentReminders() async {
        let fixture = makeFixture()
        let center = FakeNotificationCenter()

        await ReminderService.updateReminders(for: fixture.parentCategory, activities: [fixture.parentActivity], center: center)
        let parentCountAfterParentSchedule = center.pending.filter { $0.payload.profileID == fixture.parentProfile.id }.count
        XCTAssertGreaterThan(parentCountAfterParentSchedule, 0)

        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)

        let parentCountAfterChildSchedule = center.pending.filter { $0.payload.profileID == fixture.parentProfile.id }.count
        let childCount = center.pending.filter { $0.payload.profileID == fixture.childProfile.id }.count
        XCTAssertEqual(parentCountAfterChildSchedule, parentCountAfterParentSchedule, "scheduling Child must not touch Parent's pending requests")
        XCTAssertGreaterThan(childCount, 0)
    }

    func testSchedulingParentRemindersDoesNotReplaceChildReminders() async {
        let fixture = makeFixture()
        let center = FakeNotificationCenter()

        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)
        let childCountAfterChildSchedule = center.pending.filter { $0.payload.profileID == fixture.childProfile.id }.count
        XCTAssertGreaterThan(childCountAfterChildSchedule, 0)

        await ReminderService.updateReminders(for: fixture.parentCategory, activities: [fixture.parentActivity], center: center)

        let childCountAfterParentSchedule = center.pending.filter { $0.payload.profileID == fixture.childProfile.id }.count
        XCTAssertEqual(childCountAfterParentSchedule, childCountAfterChildSchedule, "scheduling Parent must not touch Child's pending requests")
    }

    func testReschedulingChildReplacesOnlyChildRequests() async {
        let fixture = makeFixture()
        let center = FakeNotificationCenter()
        await ReminderService.updateReminders(for: fixture.parentCategory, activities: [fixture.parentActivity], center: center)
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)
        let parentIdentifiersBefore = Set(center.pending.filter { $0.payload.profileID == fixture.parentProfile.id }.map(\.identifier))
        let childIdentifiersBefore = Set(center.pending.filter { $0.payload.profileID == fixture.childProfile.id }.map(\.identifier))

        // Reschedule Child at a new time — different from the old 18:00,
        // so every activity occurrence identifier is guaranteed to change
        // (same time + overlapping weekday could otherwise coincidentally
        // reuse an identifier, which wouldn't be a bug, just a false
        // negative in this assertion).
        fixture.childActivity.plannedStartMinutes = 21 * 60
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)

        let parentIdentifiersAfter = Set(center.pending.filter { $0.payload.profileID == fixture.parentProfile.id }.map(\.identifier))
        let childIdentifiersAfter = Set(center.pending.filter { $0.payload.profileID == fixture.childProfile.id }.map(\.identifier))
        let childActivityIdentifiersBefore = staleChildActivityIdentifiers(childIdentifiersBefore)
        let childActivityIdentifiersAfter = staleChildActivityIdentifiers(childIdentifiersAfter)

        XCTAssertEqual(parentIdentifiersBefore, parentIdentifiersAfter, "Parent's identifiers must be untouched by rescheduling Child")
        XCTAssertTrue(childActivityIdentifiersBefore.isDisjoint(with: childActivityIdentifiersAfter), "Child's stale schedule identifiers must be replaced")
    }

    func testRepeatedReminderUpdateDoesNotDuplicateRequests() async {
        let fixture = makeFixture()
        let center = FakeNotificationCenter()

        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)
        let firstIdentifiers = center.pending.map(\.identifier).sorted()

        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)
        let secondIdentifiers = center.pending.map(\.identifier).sorted()

        XCTAssertEqual(firstIdentifiers, secondIdentifiers, "repeated scheduling must produce one request per occurrence, not duplicates")
        XCTAssertEqual(Set(center.pending.map(\.identifier)).count, center.pending.count, "no duplicate identifiers ever pending")
    }

    // MARK: - Completion/cancellation isolation

    func testCompletingChildTaskCancelsOnlyChildOccurrenceNotification() async {
        let fixture = makeFixture()
        let center = FakeNotificationCenter()
        await ReminderService.updateReminders(for: fixture.parentCategory, activities: [fixture.parentActivity], center: center)
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)

        let childOccurrence = try! XCTUnwrap(
            center.pending.first { $0.payload.activityID == fixture.childActivity.id }?.payload.occurrence
        )
        let parentOccurrence = try! XCTUnwrap(
            center.pending.first { $0.payload.activityID == fixture.parentActivity.id }?.payload.occurrence
        )
        let parentIdentifier = ReminderService.identifier(activityID: fixture.parentActivity.id, occurrence: parentOccurrence)
        let childIdentifier = ReminderService.identifier(activityID: fixture.childActivity.id, occurrence: childOccurrence)
        let otherChildOccurrenceIdentifiers = center.pending
            .filter { $0.payload.activityID == fixture.childActivity.id && $0.identifier != childIdentifier }
            .map(\.identifier)

        ReminderService.cancelReminder(activityID: fixture.childActivity.id, occurrence: childOccurrence, center: center)

        XCTAssertFalse(center.pending.contains { $0.identifier == childIdentifier }, "the completed Child occurrence must be cancelled")
        XCTAssertTrue(center.pending.contains { $0.identifier == parentIdentifier }, "Parent's occurrence must remain")
        for identifier in otherChildOccurrenceIdentifiers {
            XCTAssertTrue(center.pending.contains { $0.identifier == identifier }, "other Child occurrences must remain")
        }
    }

    func testCompletingParentTaskCancelsOnlyParentOccurrenceNotification() async {
        let fixture = makeFixture()
        let center = FakeNotificationCenter()
        await ReminderService.updateReminders(for: fixture.parentCategory, activities: [fixture.parentActivity], center: center)
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)

        let parentOccurrence = try! XCTUnwrap(center.pending.first { $0.payload.activityID == fixture.parentActivity.id }?.payload.occurrence)
        let childIdentifier = try! XCTUnwrap(center.pending.first { $0.payload.activityID == fixture.childActivity.id }?.identifier)
        let parentIdentifier = ReminderService.identifier(activityID: fixture.parentActivity.id, occurrence: parentOccurrence)

        ReminderService.cancelReminder(activityID: fixture.parentActivity.id, occurrence: parentOccurrence, center: center)

        XCTAssertFalse(center.pending.contains { $0.identifier == parentIdentifier })
        XCTAssertTrue(center.pending.contains { $0.identifier == childIdentifier }, "Child's request must remain untouched")
    }

    /// Skip uses the exact same cancelReminder call as complete (see
    /// TodayTimelineView/ImprovementCategoryDetailView) — proving the
    /// underlying cancellation primitive is isolated proves both actions.
    func testSkippingChildTaskCancelsOnlyChildOccurrenceNotification() async {
        let fixture = makeFixture()
        let center = FakeNotificationCenter()
        await ReminderService.updateReminders(for: fixture.parentCategory, activities: [fixture.parentActivity], center: center)
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)
        let childOccurrence = try! XCTUnwrap(center.pending.first { $0.payload.activityID == fixture.childActivity.id }?.payload.occurrence)
        let parentIdentifier = try! XCTUnwrap(center.pending.first { $0.payload.activityID == fixture.parentActivity.id }?.identifier)

        ReminderService.cancelReminder(activityID: fixture.childActivity.id, occurrence: childOccurrence, center: center)

        XCTAssertFalse(center.pending.contains { $0.payload.activityID == fixture.childActivity.id && $0.payload.occurrence == childOccurrence })
        XCTAssertTrue(center.pending.contains { $0.identifier == parentIdentifier })
    }

    func testSkippingParentTaskCancelsOnlyParentOccurrenceNotification() async {
        let fixture = makeFixture()
        let center = FakeNotificationCenter()
        await ReminderService.updateReminders(for: fixture.parentCategory, activities: [fixture.parentActivity], center: center)
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)
        let parentOccurrence = try! XCTUnwrap(center.pending.first { $0.payload.activityID == fixture.parentActivity.id }?.payload.occurrence)
        let childIdentifier = try! XCTUnwrap(center.pending.first { $0.payload.activityID == fixture.childActivity.id }?.identifier)

        ReminderService.cancelReminder(activityID: fixture.parentActivity.id, occurrence: parentOccurrence, center: center)

        XCTAssertFalse(center.pending.contains { $0.payload.activityID == fixture.parentActivity.id && $0.payload.occurrence == parentOccurrence })
        XCTAssertTrue(center.pending.contains { $0.identifier == childIdentifier })
    }

    func testDisablingChildActivityCancelsOnlyChildActivityNotifications() async {
        let fixture = makeFixture()
        let center = FakeNotificationCenter()
        await ReminderService.updateReminders(for: fixture.parentCategory, activities: [fixture.parentActivity], center: center)
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)
        let parentIdentifiersBefore = Set(center.pending.filter { $0.payload.profileID == fixture.parentProfile.id }.map(\.identifier))
        XCTAssertFalse(center.pending.filter { $0.payload.activityID == fixture.childActivity.id }.isEmpty)

        fixture.childActivity.isActive = false
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)

        XCTAssertTrue(center.pending.filter { $0.payload.activityID == fixture.childActivity.id }.isEmpty, "disabled Child Activity must have no pending requests")
        XCTAssertEqual(Set(center.pending.filter { $0.payload.profileID == fixture.parentProfile.id }.map(\.identifier)), parentIdentifiersBefore)
    }

    func testDisablingChildCategoryRemindersCancelsOnlyChildCategoryNotifications() async {
        let fixture = makeFixture()
        let center = FakeNotificationCenter()
        await ReminderService.updateReminders(for: fixture.parentCategory, activities: [fixture.parentActivity], center: center)
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)
        let parentIdentifiersBefore = Set(center.pending.filter { $0.payload.profileID == fixture.parentProfile.id }.map(\.identifier))

        fixture.childCategory.reminderEnabled = false
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)

        XCTAssertTrue(center.pending.filter { $0.payload.profileID == fixture.childProfile.id }.isEmpty, "disabling Child's category reminders must clear all of Child's requests")
        XCTAssertEqual(Set(center.pending.filter { $0.payload.profileID == fixture.parentProfile.id }.map(\.identifier)), parentIdentifiersBefore)
    }

    func testEditingChildScheduleReplacesOnlyChildNotifications() async {
        let fixture = makeFixture()
        let center = FakeNotificationCenter()
        await ReminderService.updateReminders(for: fixture.parentCategory, activities: [fixture.parentActivity], center: center)
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)
        let parentIdentifiersBefore = Set(center.pending.filter { $0.payload.profileID == fixture.parentProfile.id }.map(\.identifier))
        let staleChildIdentifiers = Set(center.pending.filter { $0.payload.activityID == fixture.childActivity.id }.map(\.identifier))

        fixture.childActivity.weekdays = [2, 4, 6]
        fixture.childActivity.repeatType = .timesPerWeek
        fixture.childActivity.occurrencesPerWeek = 3
        // Different time too — a schedule and its edited replacement can
        // otherwise coincidentally share an identifier (same activity, same
        // time, a day that happens to fall in both the old and new weekday
        // sets), which would be a false failure here, not a real bug.
        fixture.childActivity.plannedStartMinutes = 21 * 60
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)

        let newChildIdentifiers = Set(center.pending.filter { $0.payload.activityID == fixture.childActivity.id }.map(\.identifier))
        XCTAssertTrue(staleChildIdentifiers.isDisjoint(with: newChildIdentifiers), "old Child schedule identifiers must be gone")
        XCTAssertEqual(Set(center.pending.filter { $0.payload.profileID == fixture.parentProfile.id }.map(\.identifier)), parentIdentifiersBefore)
    }

    /// Regression: EditTaskView.deleteOrArchive excludes a hard-deleted
    /// (no-history) Activity from the `remainingActivities` array it passes
    /// to updateReminders — see LifeOS/Views/EditTaskView.swift's
    /// `deleteOrArchive()`. Because ReminderService's cancellation pass only
    /// removes requests whose identifier prefix matches an activity that IS
    /// in the array it's given, a deleted-with-no-history Activity's
    /// already-scheduled reminders were never cancelled and would fire
    /// forever referencing a Task that no longer exists.
    func testDeletingOrArchivingChildTaskCancelsOnlyChildNotifications() async {
        let fixture = makeFixture()
        let center = FakeNotificationCenter()
        await ReminderService.updateReminders(for: fixture.parentCategory, activities: [fixture.parentActivity], center: center)
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)
        let parentIdentifiersBefore = Set(center.pending.filter { $0.payload.profileID == fixture.parentProfile.id }.map(\.identifier))
        XCTAssertFalse(center.pending.filter { $0.payload.activityID == fixture.childActivity.id }.isEmpty)

        // Mirrors EditTaskView.deleteOrArchive's fixed call — see the fix in
        // ReminderService.cancelAllReminders, called explicitly for the
        // hard-deleted Activity before refreshing the category's remaining
        // (now activity-less) schedule.
        await ReminderService.cancelAllReminders(activityID: fixture.childActivity.id, center: center)
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [], center: center)

        XCTAssertTrue(center.pending.filter { $0.payload.activityID == fixture.childActivity.id }.isEmpty, "a hard-deleted Child Activity's reminders must never remain pending")
        XCTAssertEqual(Set(center.pending.filter { $0.payload.profileID == fixture.parentProfile.id }.map(\.identifier)), parentIdentifiersBefore, "Parent must be untouched by deleting a Child Task")
    }

    // MARK: - Notification action routing (simulating NotificationRouter's
    // exact composition of NotificationPayloadParser + PlanningService.resolveCalendarItem
    // + TodayViewModel, since NotificationRouter itself needs a real
    // UNUserNotificationCenterDelegate runtime and can't run headlessly).

    private func simulateAction(
        actionIdentifier: String, userInfo: [AnyHashable: Any],
        items: [CalendarItem], repository: CalendarRepository
    ) {
        guard let payload = NotificationPayloadParser.parse(userInfo),
              let profileID = payload.profileID, let activityID = payload.activityID, let occurrence = payload.occurrence,
              let item = PlanningService.resolveCalendarItem(profileID: profileID, activityID: activityID, occurrence: occurrence, in: items)
        else { return }

        let viewModel = TodayViewModel(profile: item.profile, items: [item], activities: [], resultMeasures: [], currentTime: .now, repository: repository)
        switch actionIdentifier {
        case NotificationIdentifiers.completeActionIdentifier: _ = viewModel.quickFinish(item, at: .now)
        case NotificationIdentifiers.skipActionIdentifier: viewModel.skip(item)
        default: break
        }
    }

    private func makeCalendarItemPair(_ fixture: Fixture, occurrence: Date) -> (parent: CalendarItem, child: CalendarItem) {
        let parentItem = CalendarItem(profile: fixture.parentProfile, activity: fixture.parentActivity, date: TestFixtures.date(2026, 6, 1), plannedStart: occurrence)
        let childItem = CalendarItem(profile: fixture.childProfile, activity: fixture.childActivity, date: TestFixtures.date(2026, 6, 1), plannedStart: occurrence)
        return (parentItem, childItem)
    }

    /// SwiftData's insert(_:) is generic over PersistentModel, so a mixed
    /// array of model types can't be `.forEach(context.insert)`'d directly —
    /// this fixture-registration helper inserts each fixture object with
    /// its own concrete type.
    private func insertFixture(_ fixture: Fixture, _ context: ModelContext) {
        context.insert(fixture.parentProfile); context.insert(fixture.childProfile)
        context.insert(fixture.parentCategory); context.insert(fixture.childCategory)
        context.insert(fixture.parentActivity); context.insert(fixture.childActivity)
    }

    private func payload(profileID: UUID, activityID: UUID, occurrence: Date) -> [AnyHashable: Any] {
        [
            NotificationPayloadParser.profileIDKey: profileID.uuidString,
            NotificationPayloadParser.activityIDKey: activityID.uuidString,
            NotificationPayloadParser.occurrenceKey: ISO8601DateFormatter().string(from: occurrence)
        ]
    }

    func testChildNotificationCompleteActionCompletesOnlyChildTask() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let fixture = makeFixture()
        let occurrence = TestFixtures.date(2026, 6, 1, hour: 18)
        let (parentItem, childItem) = makeCalendarItemPair(fixture, occurrence: occurrence)
        insertFixture(fixture, context)
        context.insert(parentItem); context.insert(childItem)
        try context.save()

        let repository = SwiftDataCalendarRepository(context: context)
        simulateAction(
            actionIdentifier: NotificationIdentifiers.completeActionIdentifier,
            userInfo: payload(profileID: fixture.childProfile.id, activityID: fixture.childActivity.id, occurrence: occurrence),
            items: [parentItem, childItem], repository: repository
        )

        XCTAssertEqual(childItem.status, .done)
        XCTAssertEqual(parentItem.status, .planned)
        let sessions = try context.fetch(FetchDescriptor<ActivitySession>())
        XCTAssertEqual(sessions.filter { $0.activity?.id == fixture.childActivity.id }.count, 1)
        XCTAssertEqual(sessions.filter { $0.activity?.id == fixture.parentActivity.id }.count, 0)
    }

    func testParentNotificationCompleteActionCompletesOnlyParentTask() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let fixture = makeFixture()
        let occurrence = TestFixtures.date(2026, 6, 1, hour: 18)
        let (parentItem, childItem) = makeCalendarItemPair(fixture, occurrence: occurrence)
        insertFixture(fixture, context)
        context.insert(parentItem); context.insert(childItem)
        try context.save()

        let repository = SwiftDataCalendarRepository(context: context)
        simulateAction(
            actionIdentifier: NotificationIdentifiers.completeActionIdentifier,
            userInfo: payload(profileID: fixture.parentProfile.id, activityID: fixture.parentActivity.id, occurrence: occurrence),
            items: [parentItem, childItem], repository: repository
        )

        XCTAssertEqual(parentItem.status, .done)
        XCTAssertEqual(childItem.status, .planned)
    }

    func testChildNotificationSkipActionSkipsOnlyChildTask() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let fixture = makeFixture()
        let occurrence = TestFixtures.date(2026, 6, 1, hour: 18)
        let (parentItem, childItem) = makeCalendarItemPair(fixture, occurrence: occurrence)
        insertFixture(fixture, context)
        context.insert(parentItem); context.insert(childItem)
        try context.save()

        let repository = SwiftDataCalendarRepository(context: context)
        simulateAction(
            actionIdentifier: NotificationIdentifiers.skipActionIdentifier,
            userInfo: payload(profileID: fixture.childProfile.id, activityID: fixture.childActivity.id, occurrence: occurrence),
            items: [parentItem, childItem], repository: repository
        )

        XCTAssertEqual(childItem.status, .skipped)
        XCTAssertEqual(parentItem.status, .planned)
    }

    func testRepeatedCompleteNotificationActionIsIdempotent() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let fixture = makeFixture()
        let occurrence = TestFixtures.date(2026, 6, 1, hour: 18)
        let (parentItem, childItem) = makeCalendarItemPair(fixture, occurrence: occurrence)
        insertFixture(fixture, context)
        context.insert(parentItem); context.insert(childItem)
        try context.save()

        let repository = SwiftDataCalendarRepository(context: context)
        let userInfo = payload(profileID: fixture.childProfile.id, activityID: fixture.childActivity.id, occurrence: occurrence)
        simulateAction(actionIdentifier: NotificationIdentifiers.completeActionIdentifier, userInfo: userInfo, items: [parentItem, childItem], repository: repository)
        simulateAction(actionIdentifier: NotificationIdentifiers.completeActionIdentifier, userInfo: userInfo, items: [parentItem, childItem], repository: repository)

        let sessions = try context.fetch(FetchDescriptor<ActivitySession>())
        XCTAssertEqual(sessions.filter { $0.activity?.id == fixture.childActivity.id }.count, 1, "repeated Complete action must not create a second session")
    }

    /// The uniqueness invariant (one session per occurrence) is enforced by
    /// TodayViewModel.quickFinish's own `guard item.status != .done` — the
    /// same guard both the UI and the notification action path go through —
    /// so a notification action "racing" a UI tap on the same occurrence
    /// (simulated here as back-to-back calls against the same item) can
    /// never create two sessions.
    func testNotificationCompleteAndUICompleteRaceCreatesOneSession() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let fixture = makeFixture()
        let occurrence = TestFixtures.date(2026, 6, 1, hour: 18)
        let (_, childItem) = makeCalendarItemPair(fixture, occurrence: occurrence)
        context.insert(fixture.childProfile); context.insert(fixture.childCategory)
        context.insert(fixture.childActivity); context.insert(childItem)
        try context.save()

        let repository = SwiftDataCalendarRepository(context: context)
        let userInfo = payload(profileID: fixture.childProfile.id, activityID: fixture.childActivity.id, occurrence: occurrence)
        // "UI" completion.
        let uiViewModel = TodayViewModel(profile: fixture.childProfile, items: [childItem], activities: [], resultMeasures: [], currentTime: .now, repository: repository)
        XCTAssertTrue(uiViewModel.quickFinish(childItem, at: .now))
        // "Notification" completion of the same occurrence, arriving after.
        simulateAction(actionIdentifier: NotificationIdentifiers.completeActionIdentifier, userInfo: userInfo, items: [childItem], repository: repository)

        let sessions = try context.fetch(FetchDescriptor<ActivitySession>())
        XCTAssertEqual(sessions.count, 1)
    }

    func testNotificationActionWithMismatchedProfileAndActivityDoesNothing() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let fixture = makeFixture()
        let occurrence = TestFixtures.date(2026, 6, 1, hour: 18)
        let (parentItem, childItem) = makeCalendarItemPair(fixture, occurrence: occurrence)
        insertFixture(fixture, context)
        context.insert(parentItem); context.insert(childItem)
        try context.save()

        let repository = SwiftDataCalendarRepository(context: context)
        // Child's profileID paired with Parent's activityID — a forged/corrupt payload.
        simulateAction(
            actionIdentifier: NotificationIdentifiers.completeActionIdentifier,
            userInfo: payload(profileID: fixture.childProfile.id, activityID: fixture.parentActivity.id, occurrence: occurrence),
            items: [parentItem, childItem], repository: repository
        )

        XCTAssertEqual(parentItem.status, .planned)
        XCTAssertEqual(childItem.status, .planned)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ActivitySession>()).isEmpty)
    }

    func testNotificationActionWithWrongOccurrenceDoesNothing() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let fixture = makeFixture()
        let occurrence = TestFixtures.date(2026, 6, 1, hour: 18)
        let (_, childItem) = makeCalendarItemPair(fixture, occurrence: occurrence)
        context.insert(fixture.childProfile); context.insert(fixture.childCategory)
        context.insert(fixture.childActivity); context.insert(childItem)
        try context.save()

        let repository = SwiftDataCalendarRepository(context: context)
        let wrongOccurrence = occurrence.addingTimeInterval(3600)
        simulateAction(
            actionIdentifier: NotificationIdentifiers.completeActionIdentifier,
            userInfo: payload(profileID: fixture.childProfile.id, activityID: fixture.childActivity.id, occurrence: wrongOccurrence),
            items: [childItem], repository: repository
        )

        XCTAssertEqual(childItem.status, .planned)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ActivitySession>()).isEmpty)
    }

    func testMalformedNotificationPayloadDoesNothing() throws {
        let container = try LifeOSDataStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let fixture = makeFixture()
        let occurrence = TestFixtures.date(2026, 6, 1, hour: 18)
        let (_, childItem) = makeCalendarItemPair(fixture, occurrence: occurrence)
        context.insert(fixture.childProfile); context.insert(fixture.childCategory)
        context.insert(fixture.childActivity); context.insert(childItem)
        try context.save()
        let repository = SwiftDataCalendarRepository(context: context)

        let malformedPayloads: [[AnyHashable: Any]] = [
            [:],
            ["activityID": fixture.childActivity.id.uuidString, "occurrence": ISO8601DateFormatter().string(from: occurrence)],
            ["profileID": fixture.childProfile.id.uuidString, "occurrence": ISO8601DateFormatter().string(from: occurrence)],
            ["profileID": fixture.childProfile.id.uuidString, "activityID": fixture.childActivity.id.uuidString],
            ["profileID": "not-a-uuid", "activityID": fixture.childActivity.id.uuidString, "occurrence": ISO8601DateFormatter().string(from: occurrence)],
            ["profileID": fixture.childProfile.id.uuidString, "activityID": "not-a-uuid", "occurrence": ISO8601DateFormatter().string(from: occurrence)],
            ["profileID": fixture.childProfile.id.uuidString, "activityID": fixture.childActivity.id.uuidString, "occurrence": "not-a-date"]
        ]

        for userInfo in malformedPayloads {
            simulateAction(actionIdentifier: NotificationIdentifiers.completeActionIdentifier, userInfo: userInfo, items: [childItem], repository: repository)
        }

        XCTAssertEqual(childItem.status, .planned, "no malformed payload may mutate the Task")
        XCTAssertTrue(try context.fetch(FetchDescriptor<ActivitySession>()).isEmpty, "no malformed payload may create a session")
    }

    // MARK: - Category-review notification ownership

    func testParentAndChildCategoryReviewsHaveIndependentIdentifiers() async {
        let fixture = makeFixture()
        let center = FakeNotificationCenter()
        await ReminderService.updateReminders(for: fixture.parentCategory, activities: [fixture.parentActivity], center: center)
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)

        let parentReview = ReminderService.categoryReviewIdentifier(categoryID: fixture.parentCategory.id)
        let childReview = ReminderService.categoryReviewIdentifier(categoryID: fixture.childCategory.id)
        XCTAssertNotEqual(parentReview, childReview, "identical category names must not collide")
        XCTAssertTrue(center.pending.contains { $0.identifier == parentReview })
        XCTAssertTrue(center.pending.contains { $0.identifier == childReview })
    }

    func testCancellingChildCategoryReviewKeepsParentReview() async {
        let fixture = makeFixture()
        let center = FakeNotificationCenter()
        await ReminderService.updateReminders(for: fixture.parentCategory, activities: [fixture.parentActivity], center: center)
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)
        let parentReview = ReminderService.categoryReviewIdentifier(categoryID: fixture.parentCategory.id)
        let childReview = ReminderService.categoryReviewIdentifier(categoryID: fixture.childCategory.id)

        fixture.childCategory.reminderEnabled = false
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)

        XCTAssertFalse(center.pending.contains { $0.identifier == childReview })
        XCTAssertTrue(center.pending.contains { $0.identifier == parentReview })
    }

    func testEditingChildCategoryReviewKeepsParentReview() async {
        let fixture = makeFixture()
        let center = FakeNotificationCenter()
        await ReminderService.updateReminders(for: fixture.parentCategory, activities: [fixture.parentActivity], center: center)
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)
        let parentReview = ReminderService.categoryReviewIdentifier(categoryID: fixture.parentCategory.id)

        fixture.childCategory.reminderHour = 20
        await ReminderService.updateReminders(for: fixture.childCategory, activities: [fixture.childActivity], center: center)

        // Same identifier (keyed by category id), but Parent's own pending
        // request for that identifier must be untouched — Child's reminderHour
        // change never reaches Parent's category at all.
        XCTAssertTrue(center.pending.contains { $0.identifier == parentReview })
        let parentRequest = center.pending.first { $0.identifier == parentReview }
        XCTAssertEqual(parentRequest?.triggerDateComponents.hour, fixture.parentCategory.reminderHour)
    }

    // MARK: - Goal check-in notification ownership

    private func makeGoalWithMeasure(profile: Profile, name: String, nextCheckIn: Date) -> (Goal, ResultMeasure) {
        let goal = Goal(profile: profile, name: name)
        let measure = ResultMeasure(
            goal: goal, name: "Body weight", direction: .decrease, baselineValue: 80, targetValue: 75,
            cadence: .weekly, nextCheckInDate: nextCheckIn, reminderEnabled: true
        )
        return (goal, measure)
    }

    func testParentAndChildGoalCheckInsHaveIndependentIdentifiers() async {
        let fixture = makeFixture()
        let nextCheckIn = TestFixtures.date(2026, 12, 1)
        let (_, parentMeasure) = makeGoalWithMeasure(profile: fixture.parentProfile, name: "Reach goal weight", nextCheckIn: nextCheckIn)
        let (_, childMeasure) = makeGoalWithMeasure(profile: fixture.childProfile, name: "Reach goal weight", nextCheckIn: nextCheckIn)
        let center = FakeNotificationCenter()

        await GoalReminderService.updateReminder(for: parentMeasure, center: center)
        await GoalReminderService.updateReminder(for: childMeasure, center: center)

        let parentIdentifier = GoalReminderService.identifier(measureID: parentMeasure.id)
        let childIdentifier = GoalReminderService.identifier(measureID: childMeasure.id)
        XCTAssertNotEqual(parentIdentifier, childIdentifier)
        XCTAssertTrue(center.pending.contains { $0.identifier == parentIdentifier })
        XCTAssertTrue(center.pending.contains { $0.identifier == childIdentifier })
    }

    func testCancellingChildGoalCheckInKeepsParentGoalCheckIn() async {
        let fixture = makeFixture()
        let nextCheckIn = TestFixtures.date(2026, 12, 1)
        let (_, parentMeasure) = makeGoalWithMeasure(profile: fixture.parentProfile, name: "Reach goal weight", nextCheckIn: nextCheckIn)
        let (_, childMeasure) = makeGoalWithMeasure(profile: fixture.childProfile, name: "Reach goal weight", nextCheckIn: nextCheckIn)
        let center = FakeNotificationCenter()
        await GoalReminderService.updateReminder(for: parentMeasure, center: center)
        await GoalReminderService.updateReminder(for: childMeasure, center: center)
        let parentIdentifier = GoalReminderService.identifier(measureID: parentMeasure.id)
        let childIdentifier = GoalReminderService.identifier(measureID: childMeasure.id)

        childMeasure.reminderEnabled = false
        await GoalReminderService.updateReminder(for: childMeasure, center: center)

        XCTAssertFalse(center.pending.contains { $0.identifier == childIdentifier })
        XCTAssertTrue(center.pending.contains { $0.identifier == parentIdentifier })
    }

    func testEditingChildGoalCheckInKeepsParentGoalCheckIn() async {
        let fixture = makeFixture()
        let nextCheckIn = TestFixtures.date(2026, 12, 1)
        let (_, parentMeasure) = makeGoalWithMeasure(profile: fixture.parentProfile, name: "Reach goal weight", nextCheckIn: nextCheckIn)
        let (_, childMeasure) = makeGoalWithMeasure(profile: fixture.childProfile, name: "Reach goal weight", nextCheckIn: nextCheckIn)
        let center = FakeNotificationCenter()
        await GoalReminderService.updateReminder(for: parentMeasure, center: center)
        await GoalReminderService.updateReminder(for: childMeasure, center: center)
        let parentIdentifier = GoalReminderService.identifier(measureID: parentMeasure.id)
        let parentRequestBefore = center.pending.first { $0.identifier == parentIdentifier }

        childMeasure.nextCheckInDate = TestFixtures.date(2026, 12, 15)
        await GoalReminderService.updateReminder(for: childMeasure, center: center)

        let parentRequestAfter = center.pending.first { $0.identifier == parentIdentifier }
        XCTAssertEqual(parentRequestBefore?.triggerDateComponents, parentRequestAfter?.triggerDateComponents, "Parent's check-in date must be untouched by editing Child's")
    }
}
