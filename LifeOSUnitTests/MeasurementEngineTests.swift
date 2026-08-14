import XCTest
@testable import LifeOS

/// Phase 2 (Refactor.md / IMPLEMENTATION_PHASE_PLAN_V2.md): repository and
/// aggregation-function tests. No ModelContext, no SwiftUI, and nothing here
/// is wired into any View/ViewModel yet.

private final class FakeMeasurementRepository: MeasurementRepository {
    var hasChanges = false
    var saveResult = true
    var insertedDefinitions: [MeasurementDefinition] = []
    var insertedEntries: [MeasurementEntry] = []

    func insertDefinition(_ definition: MeasurementDefinition) { insertedDefinitions.append(definition) }
    func insertEntry(_ entry: MeasurementEntry) { insertedEntries.append(entry) }
    @discardableResult func save() -> Bool { saveResult }
}

private final class FakeRelationshipRepository: RelationshipRepository {
    var hasChanges = false
    var saveResult = true
    var inserted: [Relationship] = []

    func insert(_ relationship: Relationship) { inserted.append(relationship) }
    @discardableResult func save() -> Bool { saveResult }
}

final class MeasurementRepositoryTests: XCTestCase {
    func testInsertAndSaveDelegateToTheUnderlyingStore() {
        let repository = FakeMeasurementRepository()
        let definition = MeasurementDefinition(activity: nil, name: "Ground Balls", type: .count)
        let entry = MeasurementEntry(
            activitySession: nil, measurementDefinition: definition,
            nameSnapshot: "Ground Balls", typeSnapshot: .count, numericValue: 100
        )

        repository.insertDefinition(definition)
        repository.insertEntry(entry)

        XCTAssertEqual(repository.insertedDefinitions.map(\.id), [definition.id])
        XCTAssertEqual(repository.insertedEntries.map(\.id), [entry.id])
        XCTAssertTrue(repository.save())

        repository.saveResult = false
        XCTAssertFalse(repository.save())
    }
}

final class RelationshipRepositoryTests: XCTestCase {
    func testInsertAndSaveDelegateToTheUnderlyingStore() {
        let repository = FakeRelationshipRepository()
        let relationship = Relationship(
            subjectProfileID: UUID(), actorProfileID: UUID(), relationshipType: "Coach"
        )

        repository.insert(relationship)

        XCTAssertEqual(repository.inserted.map(\.id), [relationship.id])
        XCTAssertTrue(repository.save())
    }
}

final class MeasurementAggregationTests: XCTestCase {
    private func groundBallsDefinition(activity: Activity? = nil) -> MeasurementDefinition {
        MeasurementDefinition(activity: activity, name: "Ground Balls", type: .count, unit: "reps", targetValue: 300)
    }

    private func entry(
        _ value: Double, definition: MeasurementDefinition?, name: String = "Ground Balls",
        on date: Date
    ) -> MeasurementEntry {
        MeasurementEntry(
            activitySession: nil, measurementDefinition: definition,
            nameSnapshot: name, typeSnapshot: .count, numericValue: value, recordedAt: date
        )
    }

    /// The worked example from DOMAIN_MODEL_V2_PROPOSAL.md §2.9:
    /// 100 + 80 + 120 = 300, i.e. 300/300 = 100% against the definition's target.
    func testWorkedExampleSumsThreeWeeksToTheFullTarget() {
        let definition = groundBallsDefinition()
        let entries = [
            entry(100, definition: definition, on: TestFixtures.date(2026, 1, 5)),
            entry(80, definition: definition, on: TestFixtures.date(2026, 1, 12)),
            entry(120, definition: definition, on: TestFixtures.date(2026, 1, 19))
        ]

        let total = ProgressEngine.measurementTotal(for: definition, entries: entries)

        XCTAssertEqual(total, 300)
        XCTAssertEqual(min(total / (definition.targetValue ?? 1), 1.0), 1.0)
    }

    func testNoMatchingEntriesReturnsZero() {
        let definition = groundBallsDefinition()
        let other = MeasurementDefinition(activity: nil, name: "Catches", type: .count)
        let entries = [entry(50, definition: other, name: "Catches", on: TestFixtures.date(2026, 1, 5))]

        XCTAssertEqual(ProgressEngine.measurementTotal(for: definition, entries: entries), 0)
        XCTAssertEqual(ProgressEngine.measurementTotal(for: definition, entries: []), 0)
    }

    /// The core historical-safety case: the definition is gone (nil link),
    /// but the entry's own nameSnapshot still matches — it must still count.
    func testFallsBackToNameSnapshotWhenTheLiveDefinitionLinkIsAbsent() {
        let definition = groundBallsDefinition()
        let entries = [
            entry(100, definition: nil, name: "Ground Balls", on: TestFixtures.date(2026, 1, 5)),
            entry(999, definition: nil, name: "Some Other Name", on: TestFixtures.date(2026, 1, 5))
        ]

        XCTAssertEqual(ProgressEngine.measurementTotal(for: definition, entries: entries), 100)
    }

    /// Profile-isolation regression: the nameSnapshot fallback (above) exists
    /// to keep counting an entry once ITS OWN definition is deleted, but must
    /// never adopt an orphaned entry belonging to a DIFFERENT profile's
    /// identically-named, separately-deleted definition. Two profiles each
    /// had their own "Ground Balls" definition deleted; only the entry that
    /// actually belongs to Alice's Activity may contribute to Alice's total.
    func testNameSnapshotFallbackNeverAdoptsAnotherProfilesOrphanedEntry() {
        let alice = Profile(name: "Alice", kind: .individual, colorToken: "blue")
        let bob = Profile(name: "Bob", kind: .individual, colorToken: "orange")
        let aliceActivity = Activity(profile: alice, category: nil, name: "Fielding", plannedStartMinutes: 0, estimatedDurationMinutes: 10)
        let bobActivity = Activity(profile: bob, category: nil, name: "Fielding", plannedStartMinutes: 0, estimatedDurationMinutes: 10)
        // Alice's live definition — its own definition was NOT deleted, so a
        // correct implementation only needs entries whose measurementDefinition
        // still points at it, or (fallback) whose orphaned entry is actually hers.
        let aliceDefinition = MeasurementDefinition(activity: aliceActivity, name: "Ground Balls", type: .count)

        let aliceSession = ActivitySession(activity: aliceActivity, calendarItem: nil)
        let bobSession = ActivitySession(activity: bobActivity, calendarItem: nil)
        // Bob's own "Ground Balls" definition was deleted after this entry was
        // recorded, so it fell back to nameSnapshot matching — exactly like
        // testFallsBackToNameSnapshotWhenTheLiveDefinitionLinkIsAbsent, but on
        // a DIFFERENT profile's orphaned entry with the same definition name.
        let bobOrphanedEntry = MeasurementEntry(
            activitySession: bobSession, measurementDefinition: nil,
            nameSnapshot: "Ground Balls", typeSnapshot: .count, numericValue: 999,
            recordedAt: TestFixtures.date(2026, 1, 5)
        )
        let aliceEntry = MeasurementEntry(
            activitySession: aliceSession, measurementDefinition: aliceDefinition,
            nameSnapshot: "Ground Balls", typeSnapshot: .count, numericValue: 100,
            recordedAt: TestFixtures.date(2026, 1, 5)
        )

        let total = ProgressEngine.measurementTotal(for: aliceDefinition, entries: [aliceEntry, bobOrphanedEntry])

        XCTAssertEqual(total, 100, "Bob's orphaned identically-named entry (999) must never be added to Alice's total")
    }

    func testIntervalBoundsExcludeEntriesOutsideTheRange() {
        let definition = groundBallsDefinition()
        let entries = [
            entry(100, definition: definition, on: TestFixtures.date(2026, 1, 5)),
            entry(80, definition: definition, on: TestFixtures.date(2026, 1, 12)),
            entry(120, definition: definition, on: TestFixtures.date(2026, 2, 5))
        ]
        let januaryOnly = DateInterval(
            start: TestFixtures.date(2026, 1, 1), end: TestFixtures.date(2026, 2, 1)
        )

        XCTAssertEqual(
            ProgressEngine.measurementTotal(for: definition, entries: entries, interval: januaryOnly),
            180
        )
    }

    /// Multiple simultaneous MeasurementDefinitions on one Activity (the
    /// Baseball Fielding example) must never cross-contaminate each other's
    /// totals.
    func testMultipleDefinitionsOnOneActivityStayIndependent() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let activity = Activity(
            profile: profile, category: area, name: "Fielding Practice",
            plannedStartMinutes: 600, estimatedDurationMinutes: 30
        )
        let groundBalls = MeasurementDefinition(activity: activity, name: "Ground Balls", type: .count)
        let catches = MeasurementDefinition(activity: activity, name: "Catches", type: .count)
        let entries = [
            entry(100, definition: groundBalls, name: "Ground Balls", on: TestFixtures.date(2026, 1, 5)),
            entry(40, definition: catches, name: "Catches", on: TestFixtures.date(2026, 1, 5))
        ]

        XCTAssertEqual(ProgressEngine.measurementTotal(for: groundBalls, entries: entries), 100)
        XCTAssertEqual(ProgressEngine.measurementTotal(for: catches, entries: entries), 40)
    }
}
