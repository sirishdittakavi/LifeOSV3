import XCTest
import SwiftData
@testable import LifeOS

/// Chunk 4: Task Detail's Skip/Reschedule must act on exactly one
/// CalendarItem occurrence, resolved by identity, never by Task name, time,
/// or profile.
@MainActor
final class TaskOccurrenceActionsTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try LifeOSDataStore.makeContainer(inMemory: true)
    }

    func testSkipOnlyAffectsTheChosenOccurrence() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = TestFixtures.profile("Vihaan")
        let area = TestFixtures.area(profile: profile)
        let activity = Activity(
            profile: profile, category: area, name: "Hitting",
            plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 30,
            startDate: TestFixtures.date(2026, 6, 1)
        )
        let target = CalendarItem(
            profile: profile, activity: activity, date: TestFixtures.date(2026, 6, 1),
            plannedStart: TestFixtures.date(2026, 6, 1, hour: 18)
        )
        let otherOccurrence = CalendarItem(
            profile: profile, activity: activity, date: TestFixtures.date(2026, 6, 2),
            plannedStart: TestFixtures.date(2026, 6, 2, hour: 18)
        )
        context.insert(profile); context.insert(area); context.insert(activity)
        context.insert(target); context.insert(otherOccurrence)
        try context.save()

        let succeeded = TaskOccurrenceActions.skip(target, context: context)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(target.status, .skipped)
        XCTAssertEqual(otherOccurrence.status, .planned, "skipping one occurrence must never affect another occurrence of the same Task")
    }

    func testSkipOnOneProfilesOccurrenceNeverTouchesAnotherProfile() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let alice = TestFixtures.profile("Alice")
        let bob = TestFixtures.profile("Bob")
        let aliceArea = TestFixtures.area(profile: alice)
        let bobArea = TestFixtures.area(profile: bob)
        // Identically named/timed Activities on two different profiles --
        // the exact trap that would expose a resolve-by-name-or-time bug.
        let aliceActivity = Activity(
            profile: alice, category: aliceArea, name: "Hitting",
            plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 30,
            startDate: TestFixtures.date(2026, 6, 1)
        )
        let bobActivity = Activity(
            profile: bob, category: bobArea, name: "Hitting",
            plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 30,
            startDate: TestFixtures.date(2026, 6, 1)
        )
        let occurrence = TestFixtures.date(2026, 6, 1, hour: 18)
        let aliceItem = CalendarItem(profile: alice, activity: aliceActivity, date: TestFixtures.date(2026, 6, 1), plannedStart: occurrence)
        let bobItem = CalendarItem(profile: bob, activity: bobActivity, date: TestFixtures.date(2026, 6, 1), plannedStart: occurrence)
        context.insert(alice); context.insert(bob)
        context.insert(aliceArea); context.insert(bobArea)
        context.insert(aliceActivity); context.insert(bobActivity)
        context.insert(aliceItem); context.insert(bobItem)
        try context.save()

        TaskOccurrenceActions.skip(aliceItem, context: context)

        XCTAssertEqual(aliceItem.status, .skipped)
        XCTAssertEqual(bobItem.status, .planned, "skipping Alice's identically named/timed Task must never touch Bob's")
    }

    func testRescheduleMarksOriginalAndInsertsNewOccurrenceForSameProfileAndActivity() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = TestFixtures.profile("Vihaan")
        let area = TestFixtures.area(profile: profile)
        let activity = Activity(
            profile: profile, category: area, name: "Hitting",
            plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 45,
            startDate: TestFixtures.date(2026, 6, 1)
        )
        let original = CalendarItem(
            profile: profile, activity: activity, date: TestFixtures.date(2026, 6, 1),
            plannedStart: TestFixtures.date(2026, 6, 1, hour: 18)
        )
        context.insert(profile); context.insert(area); context.insert(activity); context.insert(original)
        try context.save()

        let newDate = TestFixtures.date(2026, 6, 3, hour: 9)
        let replacement = TaskOccurrenceActions.reschedule(original, to: newDate, context: context)

        XCTAssertNotNil(replacement)
        XCTAssertEqual(original.status, .rescheduled, "the original occurrence must be marked rescheduled, not deleted or silently reused")
        XCTAssertEqual(replacement?.status, .planned)
        XCTAssertEqual(replacement?.plannedStart, newDate)
        XCTAssertEqual(replacement?.profile?.id, profile.id, "the new occurrence must belong to the same profile as the original")
        XCTAssertEqual(replacement?.activity?.id, activity.id)
        XCTAssertNotEqual(replacement?.id, original.id, "reschedule must create a distinct occurrence, not repurpose the original's identity")

        let allItems = try context.fetch(FetchDescriptor<CalendarItem>())
        XCTAssertEqual(allItems.count, 2, "reschedule must not affect any occurrence other than the one being moved")
    }

    func testRescheduleOnOneProfilesOccurrenceNeverTouchesAnotherProfile() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let alice = TestFixtures.profile("Alice")
        let bob = TestFixtures.profile("Bob")
        let aliceArea = TestFixtures.area(profile: alice)
        let bobArea = TestFixtures.area(profile: bob)
        let aliceActivity = Activity(
            profile: alice, category: aliceArea, name: "Hitting",
            plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 30,
            startDate: TestFixtures.date(2026, 6, 1)
        )
        let bobActivity = Activity(
            profile: bob, category: bobArea, name: "Hitting",
            plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 30,
            startDate: TestFixtures.date(2026, 6, 1)
        )
        let occurrence = TestFixtures.date(2026, 6, 1, hour: 18)
        let aliceItem = CalendarItem(profile: alice, activity: aliceActivity, date: TestFixtures.date(2026, 6, 1), plannedStart: occurrence)
        let bobItem = CalendarItem(profile: bob, activity: bobActivity, date: TestFixtures.date(2026, 6, 1), plannedStart: occurrence)
        context.insert(alice); context.insert(bob)
        context.insert(aliceArea); context.insert(bobArea)
        context.insert(aliceActivity); context.insert(bobActivity)
        context.insert(aliceItem); context.insert(bobItem)
        try context.save()

        _ = TaskOccurrenceActions.reschedule(aliceItem, to: TestFixtures.date(2026, 6, 5, hour: 9), context: context)

        XCTAssertEqual(aliceItem.status, .rescheduled)
        XCTAssertEqual(bobItem.status, .planned, "rescheduling Alice's identically named/timed Task must never touch Bob's")
        let bobOccurrences = try context.fetch(FetchDescriptor<CalendarItem>()).filter { $0.profile?.id == bob.id }
        XCTAssertEqual(bobOccurrences.count, 1, "no new occurrence should be created for a profile that wasn't rescheduled")
    }

    /// reschedule(_:to:context:) reads the Activity/profile to reschedule
    /// from `item` itself -- there is no separate `activity`/`profile`
    /// parameter a caller could accidentally pass a mismatched value
    /// through. This proves the one edge case that guard introduces: an
    /// item with no Activity at all is left alone rather than crashing or
    /// inserting an orphaned replacement.
    func testRescheduleOfItemWithNoActivityReturnsNilAndChangesNothing() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = TestFixtures.profile("Vihaan")
        let orphanItem = CalendarItem(profile: profile, activity: nil, date: TestFixtures.date(2026, 6, 1))
        context.insert(profile); context.insert(orphanItem)
        try context.save()

        let result = TaskOccurrenceActions.reschedule(orphanItem, to: TestFixtures.date(2026, 6, 3, hour: 9), context: context)

        XCTAssertNil(result)
        XCTAssertEqual(orphanItem.status, .planned, "an item with no Activity must be left untouched, not silently marked rescheduled")
        let allItems = try context.fetch(FetchDescriptor<CalendarItem>())
        XCTAssertEqual(allItems.count, 1, "no replacement occurrence should be created for an item with no Activity")
    }
}
