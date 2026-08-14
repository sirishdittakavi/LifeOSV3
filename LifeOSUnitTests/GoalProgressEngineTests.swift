import XCTest
@testable import LifeOS

final class GoalProgressEngineTests: XCTestCase {
    func testPaceComparisonCoversAheadAndBehindResults() {
        assertIncreasingResultAheadOfExpectedPaceIsOnTrack()
        assertIncreasingResultBehindExpectedPaceNeedsReview()
    }

    func testInvalidDirectionalTargetsNeverReportGoalReached() {
        assertIncreaseTargetBelowBaselineNeverReportsGoalReached()
        assertDecreaseTargetAboveBaselineNeverReportsGoalReached()
    }

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

    private func assertIncreasingResultAheadOfExpectedPaceIsOnTrack() {
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

    private func assertIncreasingResultBehindExpectedPaceNeedsReview() {
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

    private func assertIncreaseTargetBelowBaselineNeverReportsGoalReached() {
        let profile = TestFixtures.profile()
        let goal = TestFixtures.goal(profile: profile)
        let measure = TestFixtures.measure(
            goal: goal, direction: .increase, baseline: 100, target: 90
        )
        let entry = ResultEntry(profile: profile, measure: measure, numericValue: 95)

        let result = TestFixtures.progress(goal: goal, measures: [measure], entries: [entry])

        XCTAssertEqual(result.status, .needsAttention)
        XCTAssertNil(result.resultFraction)
        XCTAssertTrue(result.nextAction.contains("Correct the Result"))
    }

    private func assertDecreaseTargetAboveBaselineNeverReportsGoalReached() {
        let profile = TestFixtures.profile()
        let goal = TestFixtures.goal(profile: profile)
        let measure = TestFixtures.measure(
            goal: goal, direction: .decrease, baseline: 90, target: 100
        )
        let entry = ResultEntry(profile: profile, measure: measure, numericValue: 95)

        let result = TestFixtures.progress(goal: goal, measures: [measure], entries: [entry])

        XCTAssertEqual(result.status, .needsAttention)
        XCTAssertNil(result.resultFraction)
        XCTAssertTrue(result.nextAction.contains("Correct the Result"))
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

    func testUnplannedManualWorkDoesNotInflatePlannedAdherence() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let goal = TestFixtures.goal(profile: profile)
        let contribution = GoalAreaContribution(goal: goal, category: area)
        let action = Activity(
            profile: profile, category: area, name: "Practice",
            repeatType: .daily, plannedStartMinutes: 600,
            estimatedDurationMinutes: 30, startDate: TestFixtures.date()
        )
        let scheduled = CalendarItem(
            profile: profile, activity: action, date: TestFixtures.date(2026, 1, 6),
            plannedStart: TestFixtures.date(2026, 1, 6, hour: 10),
            status: .done, source: .schedule
        )
        let unplanned = CalendarItem(
            profile: profile, activity: action, date: TestFixtures.date(2026, 1, 6),
            plannedStart: TestFixtures.date(2026, 1, 6, hour: 15),
            status: .done, source: .manual
        )

        let result = TestFixtures.progress(
            goal: goal, categories: [area], contributions: [contribution],
            activities: [action], items: [scheduled, unplanned], period: .day
        )

        XCTAssertEqual(result.contributions.first?.plannedActions, 1)
        XCTAssertEqual(result.contributions.first?.completedActions, 1)
        XCTAssertEqual(result.effortFraction ?? -1, 1, accuracy: 0.0001)
    }

    // MARK: - Nutrition/Body Metric Goal linkage

    func testGoalLinkedToNutritionMetricDerivesProgressFromMealHistorySinceGoalCreation() {
        let profile = TestFixtures.profile()
        let goal = TestFixtures.goal(profile: profile, createdAt: TestFixtures.date(2026, 1, 1))
        let measure = ResultMeasure(
            goal: goal, name: "Protein", valueType: .number, unit: "g",
            direction: .increase, baselineValue: 0, targetValue: 300,
            linkedNutritionMetric: .protein
        )
        let beforeGoal = MealEntry(profileID: profile.id, mealType: .breakfast, recordedAt: TestFixtures.date(2025, 12, 31))
        beforeGoal.totals = NutritionValue(proteinG: 999)
        let afterGoal1 = MealEntry(profileID: profile.id, mealType: .breakfast, recordedAt: TestFixtures.date(2026, 1, 5))
        afterGoal1.totals = NutritionValue(proteinG: 100)
        let afterGoal2 = MealEntry(profileID: profile.id, mealType: .lunch, recordedAt: TestFixtures.date(2026, 1, 12))
        afterGoal2.totals = NutritionValue(proteinG: 80)

        let result = GoalProgressEngine.progress(
            goal: goal, period: .month, now: TestFixtures.date(2026, 1, 19),
            categories: [], contributions: [], measures: [measure], entries: [],
            activities: [], calendarItems: [],
            nutritionMeals: [beforeGoal, afterGoal1, afterGoal2],
            calendar: TestFixtures.calendar
        )

        XCTAssertEqual(result.latestEntry, nil, "linked results derive from Nutrition data, not manual ResultEntry")
        XCTAssertEqual(result.resultFraction ?? -1, 180.0 / 300.0, accuracy: 0.0001, "only meals since goal.createdAt count (300 excluded)")
    }

    func testGoalLinkedToBodyMetricDerivesProgressFromLatestEntry() {
        let profile = TestFixtures.profile()
        let goal = TestFixtures.goal(profile: profile, createdAt: TestFixtures.date(2026, 1, 1))
        let definition = BodyMetricDefinition(profileID: profile.id, name: "Weight", unit: "kg")
        let measure = ResultMeasure(
            goal: goal, name: "Weight", valueType: .number, unit: "kg",
            direction: .decrease, baselineValue: 82, targetValue: 78,
            linkedBodyMetricDefinitionID: definition.id
        )
        let older = BodyMetricEntry(profileID: profile.id, bodyMetricDefinition: definition, nameSnapshot: "Weight", unitSnapshot: "kg", value: 80, recordedAt: TestFixtures.date(2026, 1, 5))
        let latest = BodyMetricEntry(profileID: profile.id, bodyMetricDefinition: definition, nameSnapshot: "Weight", unitSnapshot: "kg", value: 78.5, recordedAt: TestFixtures.date(2026, 1, 12))

        let result = GoalProgressEngine.progress(
            goal: goal, period: .month, now: TestFixtures.date(2026, 1, 19),
            categories: [], contributions: [], measures: [measure], entries: [],
            activities: [], calendarItems: [],
            bodyMetricEntries: [older, latest],
            calendar: TestFixtures.calendar
        )

        XCTAssertEqual(result.resultFraction ?? -1, (82.0 - 78.5) / (82.0 - 78.0), accuracy: 0.0001)
    }

    func testGoalWithNoLinkageStillFallsBackToManualResultEntries() {
        let profile = TestFixtures.profile()
        let goal = TestFixtures.goal(profile: profile)
        let measure = TestFixtures.measure(goal: goal, baseline: 0, target: 100)
        let entry = ResultEntry(profile: profile, measure: measure, date: TestFixtures.date(2026, 1, 6), numericValue: 40)

        let result = TestFixtures.progress(goal: goal, measures: [measure], entries: [entry], period: .month)

        XCTAssertEqual(result.latestEntry?.numericValue, 40, "no linkage set, so manual ResultEntry is still the source")
    }
}
