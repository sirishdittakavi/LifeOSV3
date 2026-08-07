import XCTest
@testable import LifeOS

final class GoalProgressEngineTests: XCTestCase {
    func testCompletedActionsDoNotPretendMissingOutcomeImproved() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let goal = TestFixtures.goal(profile: profile)
        let measure = TestFixtures.measure(goal: goal)
        let contribution = GoalAreaContribution(goal: goal, category: area)
        let action = Activity(
            profile: profile, category: area, name: "Throwing practice",
            repeatType: .daily, plannedStartMinutes: 600,
            estimatedDurationMinutes: 30, startDate: TestFixtures.date()
        )
        let item = CalendarItem(
            profile: profile, activity: action, date: TestFixtures.date(2026, 1, 6),
            plannedStart: TestFixtures.date(2026, 1, 6, hour: 10), status: .done
        )

        let result = TestFixtures.progress(
            goal: goal, categories: [area], contributions: [contribution],
            measures: [measure], activities: [action], items: [item],
            period: .day
        )

        XCTAssertEqual(result.status, .awaitingResult)
        XCTAssertEqual(result.effortFraction ?? -1, 1, accuracy: 0.0001)
        XCTAssertNil(result.latestEntry)
        XCTAssertTrue(result.nextAction.contains("Action completion alone"))
    }

    func testIncreasingResultAheadOfExpectedPaceIsOnTrack() {
        let profile = TestFixtures.profile()
        let goal = TestFixtures.goal(profile: profile)
        let measure = TestFixtures.measure(goal: goal, baseline: 0, target: 100)
        let entry = ResultEntry(
            profile: profile, measure: measure, date: TestFixtures.date(2026, 1, 6),
            numericValue: 60
        )

        let result = TestFixtures.progress(goal: goal, measures: [measure], entries: [entry])

        XCTAssertEqual(result.status, .onTrack)
        XCTAssertEqual(result.resultFraction ?? -1, 0.60, accuracy: 0.0001)
        XCTAssertEqual(result.confidence, .medium)
    }

    func testIncreasingResultBehindExpectedPaceNeedsReview() {
        let profile = TestFixtures.profile()
        let goal = TestFixtures.goal(profile: profile)
        let measure = TestFixtures.measure(goal: goal, baseline: 0, target: 100)
        let entry = ResultEntry(
            profile: profile, measure: measure, date: TestFixtures.date(2026, 1, 6),
            numericValue: 20
        )

        let result = TestFixtures.progress(goal: goal, measures: [measure], entries: [entry])

        XCTAssertEqual(result.status, .needsAttention)
        XCTAssertEqual(result.resultFraction ?? -1, 0.20, accuracy: 0.0001)
    }

    func testDecreaseTargetIsReachedWhenLatestValueIsBelowTarget() {
        let profile = TestFixtures.profile()
        let goal = TestFixtures.goal(profile: profile)
        let measure = TestFixtures.measure(
            goal: goal, direction: .decrease, baseline: 100, target: 90
        )
        let entry = ResultEntry(profile: profile, measure: measure, numericValue: 89)

        let result = TestFixtures.progress(goal: goal, measures: [measure], entries: [entry])

        XCTAssertEqual(result.status, .achieved)
        XCTAssertEqual(result.resultFraction ?? -1, 1, accuracy: 0.0001)
    }

    func testValueInsideTargetRangeReachesGoal() {
        let profile = TestFixtures.profile()
        let goal = TestFixtures.goal(profile: profile)
        let measure = TestFixtures.measure(
            goal: goal, direction: .targetRange, baseline: 40, target: nil,
            minimum: 70, maximum: 80
        )
        let entry = ResultEntry(profile: profile, measure: measure, numericValue: 75)

        let result = TestFixtures.progress(goal: goal, measures: [measure], entries: [entry])

        XCTAssertEqual(result.status, .achieved)
        XCTAssertEqual(result.resultFraction ?? -1, 1, accuracy: 0.0001)
    }

    func testWrittenAssessmentNeverCreatesFakeNumericProgress() {
        let profile = TestFixtures.profile()
        let goal = TestFixtures.goal(profile: profile)
        let measure = TestFixtures.measure(
            goal: goal, type: .text, baseline: nil, target: nil
        )
        let entry = ResultEntry(
            profile: profile, measure: measure, textValue: "Coach reports better balance"
        )

        let result = TestFixtures.progress(goal: goal, measures: [measure], entries: [entry])

        XCTAssertEqual(result.status, .notEnoughEvidence)
        XCTAssertNil(result.resultFraction)
        XCTAssertTrue(result.nextAction.contains("written evidence"))
    }

    func testThreeObservationsProduceHighEvidenceConfidence() {
        let profile = TestFixtures.profile()
        let goal = TestFixtures.goal(profile: profile)
        let measure = TestFixtures.measure(goal: goal)
        let entries = [61.0, 63.0, 65.0].enumerated().map { index, value in
            ResultEntry(
                profile: profile, measure: measure,
                date: TestFixtures.date(2026, 1, index + 2), numericValue: value
            )
        }

        let result = TestFixtures.progress(goal: goal, measures: [measure], entries: entries)

        XCTAssertEqual(result.confidence, .high)
        XCTAssertEqual(result.latestEntry?.numericValue, 65)
        XCTAssertEqual(result.previousEntry?.numericValue, 63)
    }

    func testCompletedMinutesPreferActualDurationOverEstimate() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let goal = TestFixtures.goal(profile: profile)
        let contribution = GoalAreaContribution(goal: goal, category: area)
        let action = Activity(
            profile: profile, category: area, name: "Practice",
            repeatType: .daily, plannedStartMinutes: 600,
            estimatedDurationMinutes: 30, startDate: TestFixtures.date()
        )
        let item = CalendarItem(
            profile: profile, activity: action, date: TestFixtures.date(2026, 1, 6),
            plannedStart: TestFixtures.date(2026, 1, 6, hour: 10), status: .done
        )
        item.actualStart = TestFixtures.date(2026, 1, 6, hour: 10)
        item.actualEnd = TestFixtures.date(2026, 1, 6, hour: 10, minute: 45)

        let result = TestFixtures.progress(
            goal: goal, categories: [area], contributions: [contribution],
            activities: [action], items: [item], period: .day
        )

        XCTAssertEqual(result.contributions.first?.completedMinutes, 45)
    }
}
