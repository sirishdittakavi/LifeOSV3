import XCTest
@testable import LifeOS

/// Phase 1 (Refactor.md / IMPLEMENTATION_PHASE_PLAN_V2.md): construction
/// tests only, for the three new, still-inert V2 foundation models. Nothing
/// here exercises a Repository, Engine, or View — those are later phases.
final class MeasurementAndRelationshipModelTests: XCTestCase {
    func testMeasurementDefinitionConstructsWithEachType() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let activity = Activity(
            profile: profile, category: area, name: "Fielding Practice",
            plannedStartMinutes: 600, estimatedDurationMinutes: 30
        )

        for type in MeasurementType.allCases {
            let definition = MeasurementDefinition(
                activity: activity, name: "Ground Balls", type: type, unit: "reps",
                targetValue: 100, isOptional: false, sortOrder: 0
            )
            XCTAssertEqual(definition.type, type)
            XCTAssertEqual(definition.activity?.id, activity.id)
            XCTAssertEqual(definition.targetValue, 100)
            XCTAssertTrue(definition.isActive, "defaults to active")
        }
    }

    func testMeasurementDefinitionSupportsOptionalTargetAndOptionalFlag() {
        let definition = MeasurementDefinition(
            activity: nil, name: "Notes", type: .text, isOptional: true
        )
        XCTAssertNil(definition.targetValue)
        XCTAssertNil(definition.unit)
        XCTAssertTrue(definition.isOptional)
    }

    func testMeasurementEntrySnapshotsSurviveWithoutALiveDefinitionLink() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let activity = Activity(
            profile: profile, category: area, name: "Fielding Practice",
            plannedStartMinutes: 600, estimatedDurationMinutes: 30
        )
        let session = ActivitySession(activity: activity, calendarItem: nil)

        // No measurementDefinition link at all — the entry must still be
        // fully interpretable from its own snapshot fields alone, per
        // DOMAIN_MODEL_V2_PROPOSAL.md §2.8.
        let entry = MeasurementEntry(
            activitySession: session, measurementDefinition: nil,
            nameSnapshot: "Ground Balls", typeSnapshot: .count, unitSnapshot: "reps",
            numericValue: 100
        )

        XCTAssertNil(entry.measurementDefinition)
        XCTAssertEqual(entry.nameSnapshot, "Ground Balls")
        XCTAssertEqual(entry.typeSnapshot, MeasurementType.count.rawValue)
        XCTAssertEqual(entry.unitSnapshot, "reps")
        XCTAssertEqual(entry.numericValue, 100)
        XCTAssertNil(entry.textValue)
        XCTAssertEqual(entry.activitySession?.id, session.id)
    }

    func testMeasurementEntrySupportsTextValueForTextType() {
        let entry = MeasurementEntry(
            activitySession: nil, measurementDefinition: nil,
            nameSnapshot: "Technique notes", typeSnapshot: .text,
            textValue: "Footwork improving"
        )
        XCTAssertNil(entry.numericValue)
        XCTAssertEqual(entry.textValue, "Footwork improving")
    }

    func testRelationshipDefaultsToPendingAndStoresPermissionsAsData() {
        let subject = TestFixtures.profile("Child")
        let actor = TestFixtures.profile("Parent")

        let relationship = Relationship(
            subjectProfileID: subject.id, actorProfileID: actor.id,
            relationshipType: "Parent", permissionsRaw: ["view", "edit", "manageActivities"]
        )

        XCTAssertEqual(relationship.status, .pending, "defaults to pending, no consent flow implemented yet")
        XCTAssertEqual(relationship.subjectProfileID, subject.id)
        XCTAssertEqual(relationship.actorProfileID, actor.id)
        XCTAssertEqual(relationship.permissionsRaw, ["view", "edit", "manageActivities"])
        XCTAssertNil(relationship.respondedAt)
    }

    func testRelationshipStatusTransitions() {
        let relationship = Relationship(
            subjectProfileID: UUID(), actorProfileID: UUID(), relationshipType: "Coach"
        )
        relationship.status = .active
        XCTAssertEqual(relationship.status, .active)
        relationship.status = .revoked
        XCTAssertEqual(relationship.status, .revoked)
    }
}
