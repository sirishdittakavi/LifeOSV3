import XCTest
@testable import LifeOS

/// Records calls instead of touching a real ModelContext, so TodayViewModel
/// (Refactor.md Step 4) is testable without SwiftData or SwiftUI.
private final class FakeCalendarRepository: CalendarRepository {
    var hasChanges = false
    var saveResult = true
    var saveCallCount = 0
    var insertedActivities: [Activity] = []

    func insertMissingItems(profile: Profile, date: Date, activities: [Activity]) throws -> [CalendarItem] {
        insertedActivities = activities
        return []
    }

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
