import XCTest
@testable import LifeOS

/// Phase 9: the Progress screen (ImprovementDashboardView.swift) must show
/// effort (task adherence) beside observed outcome without implying one
/// caused the other, must evaluate "not enough evidence" correctly rather
/// than defaulting to a pace judgment, and must never leak another
/// profile's data into a query -- even when, like the View's own @Query
/// properties, the arrays handed to the progress engines aren't
/// pre-filtered by profile.
final class ProgressViewAlignmentTests: XCTestCase {
    // MARK: - Effort and outcome stay independent, never a causal blend

    /// 100% supporting-task completion with an outcome that barely moved:
    /// effortFraction and resultFraction must each reflect only their own
    /// evidence, never merge into one derived "this effort caused X" score.
    func testEffortAndResultFractionsAreReportedIndependentlyNeverBlended() {
        let calendar = TestFixtures.calendar
        let profile = TestFixtures.profile("Vihaan")
        let area = TestFixtures.area(profile: profile)
        let goal = Goal(profile: profile, name: "Throw 70 mph")
        let contribution = GoalAreaContribution(goal: goal, category: area)
        let measure = ResultMeasure(
            goal: goal, name: "Throwing velocity", role: .primary, unit: "mph",
            direction: .increase, baselineValue: 60, targetValue: 70
        )
        let day = TestFixtures.date(2026, 1, 1)
        let activity = Activity(
            profile: profile, category: area, name: "Throwing practice",
            plannedStartMinutes: 600, estimatedDurationMinutes: 20, startDate: day
        )
        // The only scheduled session today was completed (100% effort)...
        let completedItem = CalendarItem(
            profile: profile, activity: activity, date: day,
            plannedStart: TestFixtures.date(2026, 1, 1, hour: 10), status: .done
        )
        // ...but the observed outcome barely moved off baseline (10% of the way to target).
        let entries = [ResultEntry(profile: profile, measure: measure, date: day, numericValue: 61)]

        let progress = GoalProgressEngine.progress(
            goal: goal, period: .day, now: day, categories: [area],
            contributions: [contribution], measures: [measure], entries: entries,
            activities: [activity], calendarItems: [completedItem], calendar: calendar
        )

        XCTAssertEqual(progress.effortFraction ?? -1, 1.0, accuracy: 0.0001, "the only scheduled session was completed")
        XCTAssertEqual(progress.resultFraction ?? -1, 0.1, accuracy: 0.0001, "the outcome only moved 1 of the 10 mph needed")
        XCTAssertNotEqual(progress.effortFraction, progress.resultFraction, "full effort must never be reported as if it were the (much smaller) actual result")
    }

    /// Action completion alone -- with zero Result entries -- must never be
    /// read as proof of outcome progress (Models.swift's explicit design:
    /// "Action completion alone cannot prove improvement").
    func testActionCompletionAloneNeverProvesGoalProgressWithoutAResultEntry() {
        let calendar = TestFixtures.calendar
        let profile = TestFixtures.profile("Vihaan")
        let area = TestFixtures.area(profile: profile)
        let goal = Goal(profile: profile, name: "Throw 70 mph")
        let contribution = GoalAreaContribution(goal: goal, category: area)
        let measure = ResultMeasure(
            goal: goal, name: "Throwing velocity", role: .primary, unit: "mph",
            direction: .increase, baselineValue: 60, targetValue: 70
        )
        let day = TestFixtures.date(2026, 1, 1)
        let activity = Activity(
            profile: profile, category: area, name: "Throwing practice",
            plannedStartMinutes: 600, estimatedDurationMinutes: 20, startDate: day
        )
        let completedItem = CalendarItem(
            profile: profile, activity: activity, date: day,
            plannedStart: TestFixtures.date(2026, 1, 1, hour: 10), status: .done
        )

        let progress = GoalProgressEngine.progress(
            goal: goal, period: .day, now: day, categories: [area],
            contributions: [contribution], measures: [measure], entries: [],
            activities: [activity], calendarItems: [completedItem], calendar: calendar
        )

        XCTAssertEqual(progress.effortFraction ?? -1, 1.0, accuracy: 0.0001)
        XCTAssertEqual(progress.status, .awaitingResult, "a fully completed Task with zero Result entries must still await a real result, not read as on-track")
    }

    // MARK: - Insufficient/not-enough-evidence states for Goals

    /// A milestone Result (no baseline, since milestones don't use one) with
    /// exactly one not-yet-achieved check-in has only one piece of evidence
    /// -- the engine requires at least two before it will render any pace
    /// judgment ("on track"/"needs attention"), so this must read as not
    /// enough evidence instead.
    func testGoalWithFewerThanTwoEvidencePointsIsNotEnoughEvidenceNotAPaceJudgment() {
        let profile = TestFixtures.profile("Vihaan")
        let goal = Goal(profile: profile, name: "Ran a 5k")
        let measure = ResultMeasure(goal: goal, name: "Ran a 5k", role: .primary, valueType: .milestone)
        let entries = [ResultEntry(profile: profile, measure: measure, date: TestFixtures.date(2026, 1, 2), numericValue: 0)]

        let progress = GoalProgressEngine.progress(
            goal: goal, period: .day, now: TestFixtures.date(2026, 1, 2),
            categories: [], contributions: [], measures: [measure], entries: entries,
            activities: [], calendarItems: [], calendar: TestFixtures.calendar
        )

        XCTAssertEqual(progress.status, .notEnoughEvidence)
    }

    func testGoalWithNoPrimaryMeasureAtAllIsAwaitingResultNotInsufficientOrOnTrack() {
        let profile = TestFixtures.profile("Vihaan")
        let goal = Goal(profile: profile, name: "Throw 70 mph")

        let progress = GoalProgressEngine.progress(
            goal: goal, period: .day, now: TestFixtures.date(2026, 1, 2),
            categories: [], contributions: [], measures: [], entries: [],
            activities: [], calendarItems: [], calendar: TestFixtures.calendar
        )

        XCTAssertEqual(progress.status, .awaitingResult)
        XCTAssertNil(progress.resultFraction)
        XCTAssertNil(progress.effortFraction)
    }

    // MARK: - Profile isolation on progress queries

    /// Mirrors ImprovementDashboardView's own @Query properties (no
    /// per-profile predicate) -- the engines themselves, not the caller,
    /// must be what keeps two profiles' progress apart.
    func testGoalProgressNeverLeaksAnotherProfilesCompletedSessionsIntoEffortFraction() {
        let vihaan = TestFixtures.profile("Vihaan")
        let sibling = TestFixtures.profile("Sibling")
        let vihaanArea = TestFixtures.area(profile: vihaan)
        let siblingArea = TestFixtures.area(profile: sibling, name: "Baseball")
        let goal = Goal(profile: vihaan, name: "Throw 70 mph")
        let contribution = GoalAreaContribution(goal: goal, category: vihaanArea)
        let vihaanActivity = Activity(
            profile: vihaan, category: vihaanArea, name: "Throwing practice",
            plannedStartMinutes: 600, estimatedDurationMinutes: 20, startDate: TestFixtures.date(2026, 1, 1)
        )
        // Identically-named Activity/Task, fully completed, but belongs to Sibling.
        let siblingActivity = Activity(
            profile: sibling, category: siblingArea, name: "Throwing practice",
            plannedStartMinutes: 600, estimatedDurationMinutes: 20, startDate: TestFixtures.date(2026, 1, 1)
        )
        let day = TestFixtures.date(2026, 1, 1)
        let vihaanItem = CalendarItem(profile: vihaan, activity: vihaanActivity, date: day, plannedStart: TestFixtures.date(2026, 1, 1, hour: 10), status: .planned)
        let siblingItem = CalendarItem(profile: sibling, activity: siblingActivity, date: day, plannedStart: TestFixtures.date(2026, 1, 1, hour: 10), status: .done)

        // Unfiltered, all-profiles arrays -- exactly what the View's @Query hands the engine.
        let progress = GoalProgressEngine.progress(
            goal: goal, period: .day, now: day, categories: [vihaanArea, siblingArea],
            contributions: [contribution], measures: [], entries: [],
            activities: [vihaanActivity, siblingActivity], calendarItems: [vihaanItem, siblingItem],
            calendar: TestFixtures.calendar
        )

        XCTAssertEqual(progress.contributions.first?.completedActions, 0, "Sibling's completed session must never count toward Vihaan's Goal effort")
        XCTAssertEqual(progress.contributions.first?.plannedActions, 1)
    }

    func testCategoryProgressNeverLeaksAnotherProfilesSessionsEvenWithIdenticalCategoryAndTaskNames() {
        let vihaan = TestFixtures.profile("Vihaan")
        let sibling = TestFixtures.profile("Sibling")
        let vihaanArea = TestFixtures.area(profile: vihaan, name: "Baseball")
        let siblingArea = TestFixtures.area(profile: sibling, name: "Baseball")
        let vihaanActivity = Activity(
            profile: vihaan, category: vihaanArea, name: "Hitting",
            plannedStartMinutes: 600, estimatedDurationMinutes: 20, startDate: TestFixtures.date(2026, 1, 1)
        )
        let siblingActivity = Activity(
            profile: sibling, category: siblingArea, name: "Hitting",
            plannedStartMinutes: 600, estimatedDurationMinutes: 20, startDate: TestFixtures.date(2026, 1, 1)
        )
        let day = TestFixtures.date(2026, 1, 1)
        let vihaanItem = CalendarItem(profile: vihaan, activity: vihaanActivity, date: day, plannedStart: TestFixtures.date(2026, 1, 1, hour: 10), status: .planned)
        let siblingItem = CalendarItem(profile: sibling, activity: siblingActivity, date: day, plannedStart: TestFixtures.date(2026, 1, 1, hour: 10), status: .done)

        let progress = CategoryProgressEngine.progress(
            profile: vihaan, category: vihaanArea, period: .day, now: day,
            activities: [vihaanActivity, siblingActivity], calendarItems: [vihaanItem, siblingItem],
            foodEntries: [], weightEntries: [], sportEntries: [], calendar: TestFixtures.calendar
        )

        XCTAssertEqual(progress.completedSessions, 0, "Sibling's completed identically-named Task must never count toward Vihaan's Plan progress")
    }
}
