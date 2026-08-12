import XCTest
@testable import LifeOS

/// Records calls instead of touching a real ModelContext, so TodayViewModel
/// (Refactor.md Step 4) is testable without SwiftData or SwiftUI.
private final class FakeCalendarRepository: CalendarRepository {
    var hasChanges = false
    var saveResult = true
    var saveCallCount = 0
    var insertedActivities: [Activity] = []
    var insertedSessions: [ActivitySession] = []
    var deletedSessions: [ActivitySession] = []

    func insertMissingItems(profile: Profile, date: Date, activities: [Activity]) throws -> [CalendarItem] {
        insertedActivities = activities
        return []
    }

    func insertSession(_ session: ActivitySession) { insertedSessions.append(session) }
    func deleteSession(_ session: ActivitySession) { deletedSessions.append(session) }

    @discardableResult
    func save() -> Bool {
        saveCallCount += 1
        return saveResult
    }
}

@MainActor
final class TodayViewModelTests: XCTestCase {
    func testDerivedStateMatchesOriginalTodayTimelineViewLogic() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let today = TestFixtures.date(2026, 1, 6)
        let activity = Activity(
            profile: profile, category: area, name: "Practice",
            plannedStartMinutes: 600, estimatedDurationMinutes: 20, startDate: today
        )
        let plannedToday = CalendarItem(
            profile: profile, activity: activity, date: today,
            plannedStart: TestFixtures.date(2026, 1, 6, hour: 10)
        )
        let doneToday = CalendarItem(
            profile: profile, activity: activity, date: today,
            plannedStart: TestFixtures.date(2026, 1, 6, hour: 7), status: .done
        )
        let yesterday = CalendarItem(
            profile: profile, activity: activity, date: TestFixtures.date(2026, 1, 5),
            plannedStart: TestFixtures.date(2026, 1, 5, hour: 10)
        )

        let viewModel = TodayViewModel(
            profile: profile, items: [plannedToday, doneToday, yesterday], activities: [activity],
            resultMeasures: [], currentTime: TestFixtures.date(2026, 1, 6, hour: 12),
            repository: FakeCalendarRepository()
        )

        XCTAssertEqual(Set(viewModel.todayItems.map(\.id)), Set([plannedToday.id, doneToday.id]))
        XCTAssertEqual(viewModel.activeItems.map(\.id), [plannedToday.id])
        XCTAssertEqual(viewModel.decidedItems.map(\.id), [doneToday.id])
        XCTAssertEqual(viewModel.summary.done, 1)
        XCTAssertEqual(viewModel.summary.remaining, 1)
    }

    func testActionsMutateItemsAndRollBackOnSaveFailure() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let today = TestFixtures.date(2026, 1, 6)
        let activity = Activity(
            profile: profile, category: area, name: "Practice",
            plannedStartMinutes: 600, estimatedDurationMinutes: 20, startDate: today
        )
        let item = CalendarItem(
            profile: profile, activity: activity, date: today,
            plannedStart: TestFixtures.date(2026, 1, 6, hour: 10)
        )
        let repository = FakeCalendarRepository()
        let viewModel = TodayViewModel(
            profile: profile, items: [item], activities: [activity], resultMeasures: [],
            currentTime: TestFixtures.date(2026, 1, 6, hour: 12), repository: repository
        )

        viewModel.start(item)
        XCTAssertEqual(item.status, .inProgress)
        XCTAssertNotNil(item.actualStart)

        viewModel.skip(item)
        XCTAssertEqual(item.status, .skipped)

        viewModel.undoSkip(item)
        XCTAssertEqual(item.status, .planned)

        repository.saveResult = false
        viewModel.skip(item)
        XCTAssertEqual(item.status, .planned, "a failed save must roll the status back")
    }

    func testQuickFinishIsIdempotentAndRollsBackOnSaveFailure() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let today = TestFixtures.date(2026, 1, 6)
        let activity = Activity(
            profile: profile, category: area, name: "Practice",
            plannedStartMinutes: 600, estimatedDurationMinutes: 20, startDate: today
        )
        let item = CalendarItem(
            profile: profile, activity: activity, date: today,
            plannedStart: TestFixtures.date(2026, 1, 6, hour: 10)
        )
        let repository = FakeCalendarRepository()
        let completionTime = TestFixtures.date(2026, 1, 6, hour: 12)
        let viewModel = TodayViewModel(
            profile: profile, items: [item], activities: [activity], resultMeasures: [],
            currentTime: completionTime, repository: repository
        )

        repository.saveResult = false
        let previousStatus = item.status
        XCTAssertFalse(viewModel.quickFinish(item, at: completionTime), "a failed save must report failure")
        XCTAssertEqual(item.status, previousStatus, "a failed save must roll the status back")
        XCTAssertNil(item.actualStart, "a failed save must roll actualStart back")
        XCTAssertEqual(repository.insertedSessions.count, 1)
        XCTAssertEqual(repository.deletedSessions.count, 1, "the inserted Session must be removed on rollback")

        repository.saveResult = true
        XCTAssertTrue(viewModel.quickFinish(item, at: completionTime))
        XCTAssertEqual(item.status, .done)
        XCTAssertEqual(repository.insertedSessions.count, 2)

        // A second tap on an already-completed occurrence must be a no-op —
        // no new Session, no repository interaction at all.
        let saveCallCountBefore = repository.saveCallCount
        XCTAssertFalse(viewModel.quickFinish(item, at: completionTime), "quickFinish must be a no-op once the item is already done")
        XCTAssertEqual(repository.insertedSessions.count, 2, "a repeated tap must not insert a duplicate Session")
        XCTAssertEqual(repository.saveCallCount, saveCallCountBefore)
    }

    func testQuickFinishOnInProgressItemPreservesRealStartTime() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let today = TestFixtures.date(2026, 1, 6)
        let activity = Activity(
            profile: profile, category: area, name: "Practice",
            plannedStartMinutes: 360, estimatedDurationMinutes: 20, startDate: today
        )
        let item = CalendarItem(
            profile: profile, activity: activity, date: today,
            plannedStart: TestFixtures.date(2026, 1, 6, hour: 6)
        )
        let repository = FakeCalendarRepository()
        let startedAt = TestFixtures.date(2026, 1, 6, hour: 6)
        let finishedAt = TestFixtures.date(2026, 1, 6, hour: 6, minute: 45)
        // currentTime is deliberately stale/unrelated to the completion
        // time being asserted, to prove quickFinish uses the passed
        // `completionTime`, not the Today screen's refresh clock.
        let viewModel = TodayViewModel(
            profile: profile, items: [item], activities: [activity], resultMeasures: [],
            currentTime: TestFixtures.date(2026, 1, 6, hour: 5), repository: repository
        )

        item.status = .inProgress
        item.actualStart = startedAt

        // Started 6:00 → Finished 6:45 must record the real 45-minute
        // duration, not the Activity's unrelated 20-minute estimate.
        XCTAssertTrue(viewModel.quickFinish(item, at: finishedAt))
        XCTAssertEqual(item.status, .done)
        XCTAssertEqual(item.actualStart, startedAt, "the real start time must be preserved, not replaced by the estimate")
        XCTAssertEqual(item.actualEnd, finishedAt)
        XCTAssertEqual(repository.insertedSessions.last?.actualActiveSeconds, 45 * 60)
    }

    /// Regression: the ViewModel's `currentTime` (the Today screen's
    /// once-a-minute refresh clock) can be stale — here it's even earlier
    /// than the occurrence's real `actualStart`. quickFinish must still use
    /// the explicitly passed `completionTime`, never fall back to
    /// `currentTime`, or this would silently produce a negative/zero
    /// duration.
    func testQuickFinishUsesPassedCompletionTimeNotStaleCurrentTime() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let today = TestFixtures.date(2026, 1, 6)
        let activity = Activity(
            profile: profile, category: area, name: "Practice",
            plannedStartMinutes: 360, estimatedDurationMinutes: 20, startDate: today
        )
        let item = CalendarItem(
            profile: profile, activity: activity, date: today,
            plannedStart: TestFixtures.date(2026, 1, 6, hour: 6)
        )
        let repository = FakeCalendarRepository()
        let startedAt = TestFixtures.date(2026, 1, 6, hour: 6)
        let staleCurrentTime = TestFixtures.date(2026, 1, 6, hour: 5, minute: 30) // earlier than actualStart
        let completionTime = TestFixtures.date(2026, 1, 6, hour: 6, minute: 20)
        let viewModel = TodayViewModel(
            profile: profile, items: [item], activities: [activity], resultMeasures: [],
            currentTime: staleCurrentTime, repository: repository
        )

        item.status = .inProgress
        item.actualStart = startedAt

        XCTAssertTrue(viewModel.quickFinish(item, at: completionTime))
        XCTAssertEqual(item.actualEnd, completionTime, "actualEnd must equal the passed completion time, not the stale currentTime")
        XCTAssertLessThan(item.actualStart!, item.actualEnd!, "startedAt must be before endedAt")
        XCTAssertEqual(repository.insertedSessions.last?.actualActiveSeconds, 20 * 60)
    }

    func testQuickFinishOnInProgressItemRollsBackActualEndOnSaveFailure() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let today = TestFixtures.date(2026, 1, 6)
        let activity = Activity(
            profile: profile, category: area, name: "Practice",
            plannedStartMinutes: 360, estimatedDurationMinutes: 20, startDate: today
        )
        let item = CalendarItem(
            profile: profile, activity: activity, date: today,
            plannedStart: TestFixtures.date(2026, 1, 6, hour: 6)
        )
        let repository = FakeCalendarRepository()
        let startedAt = TestFixtures.date(2026, 1, 6, hour: 6)
        let completionTime = TestFixtures.date(2026, 1, 6, hour: 6, minute: 45)
        let viewModel = TodayViewModel(
            profile: profile, items: [item], activities: [activity], resultMeasures: [],
            currentTime: TestFixtures.date(2026, 1, 6, hour: 5), repository: repository
        )

        item.status = .inProgress
        item.actualStart = startedAt
        repository.saveResult = false

        XCTAssertFalse(viewModel.quickFinish(item, at: completionTime))
        XCTAssertEqual(item.status, .inProgress, "a failed save must roll the status back")
        XCTAssertEqual(item.actualStart, startedAt, "a failed save must leave the real start time untouched")
        XCTAssertNil(item.actualEnd, "a failed save must roll actualEnd back to its prior value")
    }

    func testGenerateTodayItemsIfNeededDelegatesToRepository() {
        let profile = TestFixtures.profile()
        let area = TestFixtures.area(profile: profile)
        let activity = Activity(
            profile: profile, category: area, name: "Practice",
            plannedStartMinutes: 600, estimatedDurationMinutes: 20, startDate: TestFixtures.date(2026, 1, 6)
        )
        let repository = FakeCalendarRepository()
        let viewModel = TodayViewModel(
            profile: profile, items: [], activities: [activity], resultMeasures: [],
            currentTime: TestFixtures.date(2026, 1, 6), repository: repository
        )

        viewModel.generateTodayItemsIfNeeded()
        XCTAssertEqual(repository.insertedActivities.map(\.id), [activity.id])
    }
}
