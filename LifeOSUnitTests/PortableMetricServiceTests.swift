import XCTest
@testable import LifeOS

final class PortableMetricServiceTests: XCTestCase {
    func testEveryVersionOneEvidenceTypeMapsToPortableMetrics() throws {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let goal = TestFixtures.goal(profile: profile)
        let measure = TestFixtures.measure(goal: goal)
        let action = Activity(
            profile: profile, category: area, name: "Throwing practice",
            targetValue: 30, targetUnit: "throws", repeatType: .daily,
            plannedStartMinutes: 600, estimatedDurationMinutes: 30,
            startDate: TestFixtures.date()
        )
        let session = ActivitySession(
            activity: action, calendarItem: nil, date: TestFixtures.date(2026, 1, 2),
            actualActiveSeconds: 1_500, recordedValue: 24, note: "Good mechanics"
        )
        let result = ResultEntry(
            profile: profile, measure: measure, date: TestFixtures.date(2026, 1, 3),
            numericValue: 65, sourceLabel: "Radar"
        )
        let food = FoodEntry(
            profile: profile, date: TestFixtures.date(2026, 1, 4), mealType: .lunch,
            name: "Rice bowl", calories: 620, proteinGrams: 32, servings: 1.5
        )
        let weight = WeightEntry(
            profile: profile, date: TestFixtures.date(2026, 1, 5), kilograms: 45.2
        )
        let sport = SportEntry(
            profile: profile, category: area, date: TestFixtures.date(2026, 1, 6),
            sessionName: "Fielding", repetitions: 40, durationMinutes: 35
        )

        let envelope = try PortableMetricService.makeEnvelope(
            sessions: [session], resultEntries: [result], foodEntries: [food],
            weightEntries: [weight], sportEntries: [sport],
            exportedAt: TestFixtures.date(2026, 1, 7)
        )

        XCTAssertEqual(envelope.metrics.map(\.kind), [
            .actionSession, .goalResult, .nutrition, .weight, .sport
        ])
        XCTAssertTrue(envelope.metrics.allSatisfy { $0.profileID == profile.id })
        XCTAssertEqual(envelope.metrics.first?.fields["recorded_value"], .number(24))
        XCTAssertEqual(envelope.metrics[1].goalID, goal.id)
        XCTAssertEqual(envelope.metrics[2].fields["protein_grams"], .number(32))
        XCTAssertEqual(envelope.metrics[3].fields["unit"], .string("kg"))
        XCTAssertEqual(envelope.metrics[4].categoryID, area.id)
    }

    func testPortableJSONRoundTripPreservesTypedFlexibleFields() throws {
        let metric = PortableMetric(
            id: UUID(), profileID: UUID(), occurredAt: TestFixtures.date(),
            kind: .sport, title: "Assessment",
            fields: [
                "number": .number(12.5),
                "integral_number": .number(12),
                "integer": .integer(4),
                "flag": .boolean(true),
                "labels": .array([.string("fast"), .null]),
                "details": .object(["surface": .string("grass")])
            ]
        )
        let envelope = PortableMetricEnvelope(
            exportedAt: TestFixtures.date(2026, 1, 2), metrics: [metric]
        )

        let data = try PortableMetricCodec.encode(envelope)
        let decoded = try PortableMetricCodec.decode(data)

        XCTAssertEqual(decoded, envelope)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"schemaVersion\" : 1"))
    }

    func testProgressIsNotStoredInPortableMetric() throws {
        let profile = TestFixtures.profile()
        let goal = TestFixtures.goal(profile: profile)
        let measure = TestFixtures.measure(goal: goal, baseline: 60, target: 70)
        let entry = ResultEntry(profile: profile, measure: measure, numericValue: 65)

        let metric = try PortableMetricService.metric(from: entry)
        let data = try PortableMetricCodec.encode(PortableMetricEnvelope(metrics: [metric]))
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(metric.fields["baseline_value"], .number(60))
        XCTAssertEqual(metric.fields["target_value"], .number(70))
        XCTAssertFalse(json.contains("progressValue"))
        XCTAssertFalse(json.contains("progress_value"))
    }

    func testRecordWithoutProfileIsRejectedInsteadOfLeakingAcrossPeople() {
        let entry = WeightEntry(profile: nil, kilograms: 45)

        XCTAssertThrowsError(try PortableMetricService.metric(from: entry)) { error in
            XCTAssertEqual(
                error as? PortableMetricError,
                .missingProfile(recordID: entry.id, kind: .weight)
            )
        }
    }

    func testFutureSchemaAndInvalidNumbersAreRejected() {
        let future = PortableMetric(
            schemaVersion: 99, id: UUID(), profileID: UUID(), occurredAt: .now,
            kind: .weight, title: "Weight"
        )
        XCTAssertThrowsError(try future.validate()) { error in
            XCTAssertEqual(error as? PortableMetricError, .unsupportedVersion(99))
        }

        let invalid = PortableMetric(
            id: UUID(), profileID: UUID(), occurredAt: .now, kind: .weight,
            title: "Weight", fields: ["kilograms": .number(.infinity)]
        )
        XCTAssertThrowsError(try invalid.validate()) { error in
            XCTAssertEqual(error as? PortableMetricError, .nonFiniteNumber(invalid.id))
        }
    }

    func testDuplicateMetricIDsAreRejected() {
        let id = UUID()
        let first = PortableMetric(
            id: id, profileID: UUID(), occurredAt: .now, kind: .nutrition, title: "Lunch"
        )
        let second = PortableMetric(
            id: id, profileID: UUID(), occurredAt: .now, kind: .weight, title: "Weight"
        )

        XCTAssertThrowsError(try PortableMetricEnvelope(metrics: [first, second]).validate()) { error in
            XCTAssertEqual(error as? PortableMetricError, .duplicateIdentifier(id))
        }
    }

    func testWeeklyMealPlansAreNotExportedAsActualNutritionEvidence() throws {
        let profile = TestFixtures.profile()
        let planned = FoodEntry(
            profile: profile, mealType: .dinner, name: "Planned salmon",
            calories: 500, nutritionSource: FoodEntry.mealPlanSource
        )
        let actual = FoodEntry(
            profile: profile, mealType: .dinner, name: "Chicken bowl",
            calories: 620, nutritionSource: "Manual"
        )

        let envelope = try PortableMetricService.makeEnvelope(
            sessions: [], resultEntries: [], foodEntries: [planned, actual],
            weightEntries: [], sportEntries: []
        )

        XCTAssertTrue(planned.isMealPlanItem)
        XCTAssertFalse(actual.isMealPlanItem)
        XCTAssertEqual(envelope.metrics.map(\.title), ["Chicken bowl"])
    }
}
