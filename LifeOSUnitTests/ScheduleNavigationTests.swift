import XCTest
import SwiftData
@testable import LifeOS

/// Phase 8: Weekly Schedule navigation (WeeklyScheduleView.swift) is a
/// plain (non-private) View whose own computed properties are `private`,
/// so this exercises the same underlying rules it relies on directly:
/// chronological ordering by plannedStart (falling back to `date`, exactly
/// WeeklyScheduleView.selectedDayItems's sort key), calendar-day bucketing
/// across the visible week, plan-profile alignment via ProfileScope (used
/// by both AddActivityView's Quick Add and EditTaskView's Plan picker,
/// which Schedule's "+" and item-detail sheets present), and
/// PlanningService's profile-safety when generating a week's occurrences
/// from an unfiltered, all-profiles Activity list -- exactly what
/// WeeklyScheduleView's own `@Query private var activities: [Activity]`
/// (no predicate) passes to PlanningService.insertMissingCalendarItems.
@MainActor
final class ScheduleNavigationTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try LifeOSDataStore.makeContainer(inMemory: true)
    }

    // MARK: - Chronological ordering

    func testItemsOrderChronologicallyByPlannedStartFallingBackToDate() {
        let profile = TestFixtures.profile("Vihaan")
        let area = TestFixtures.area(profile: profile)
        let activity = Activity(
            profile: profile, category: area, name: "Hitting",
            plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 30
        )
        let day = TestFixtures.date(2026, 6, 1)
        let evening = CalendarItem(profile: profile, activity: activity, date: day, plannedStart: TestFixtures.date(2026, 6, 1, hour: 18))
        let morning = CalendarItem(profile: profile, activity: activity, date: day, plannedStart: TestFixtures.date(2026, 6, 1, hour: 7))
        let noPlannedStart = CalendarItem(profile: profile, activity: activity, date: TestFixtures.date(2026, 6, 1, hour: 3))

        let ordered = [evening, morning, noPlannedStart]
            .sorted { ($0.plannedStart ?? $0.date) < ($1.plannedStart ?? $1.date) }

        XCTAssertEqual(ordered, [noPlannedStart, morning, evening], "no-plannedStart falls back to `date` (03:00), then 07:00, then 18:00")
    }

    // MARK: - Day bucketing across the visible week

    func testItemsAreGroupedByCalendarDayWithinTheVisibleWeek() {
        let calendar = TestFixtures.calendar
        let profile = TestFixtures.profile("Vihaan")
        let area = TestFixtures.area(profile: profile)
        let activity = Activity(
            profile: profile, category: area, name: "Hitting",
            plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 30
        )
        let monday = TestFixtures.date(2026, 6, 1)
        let tuesday = TestFixtures.date(2026, 6, 2)
        let mondayItem = CalendarItem(profile: profile, activity: activity, date: monday, plannedStart: TestFixtures.date(2026, 6, 1, hour: 18))
        let tuesdayItem1 = CalendarItem(profile: profile, activity: activity, date: tuesday, plannedStart: TestFixtures.date(2026, 6, 2, hour: 9))
        let tuesdayItem2 = CalendarItem(profile: profile, activity: activity, date: tuesday, plannedStart: TestFixtures.date(2026, 6, 2, hour: 18))
        let allItems = [mondayItem, tuesdayItem1, tuesdayItem2]

        let mondayBucket = allItems.filter { calendar.isSameDay($0.date, as: monday) }
        let tuesdayBucket = allItems.filter { calendar.isSameDay($0.date, as: tuesday) }

        XCTAssertEqual(mondayBucket.map(\.id), [mondayItem.id])
        XCTAssertEqual(Set(tuesdayBucket.map(\.id)), Set([tuesdayItem1.id, tuesdayItem2.id]))
    }

    // MARK: - Plan-profile alignment before task creation/assignment

    func testPlanPickerExcludesAnotherProfilesIdenticallyNamedPlan() {
        let vihaan = TestFixtures.profile("Vihaan")
        let sibling = TestFixtures.profile("Sibling")
        // Same name on purpose -- the classic trap this codebase repeatedly
        // guards against: a name/time match must never substitute for a
        // real profile-identity check.
        let vihaanPlan = AppCategory(profile: vihaan, name: "Baseball", symbol: "figure.baseball", colorToken: "orange")
        let siblingPlan = AppCategory(profile: sibling, name: "Baseball", symbol: "figure.baseball", colorToken: "blue")

        let picked = ProfileScope.categories(for: vihaan, from: [siblingPlan, vihaanPlan])

        XCTAssertEqual(picked.map(\.id), [vihaanPlan.id], "the Plan picker offered when creating/assigning a Task from Schedule must never include another profile's identically named Plan")
    }

    func testCannotAssignATaskToAnotherProfilesPlan() {
        let vihaan = TestFixtures.profile("Vihaan")
        let sibling = TestFixtures.profile("Sibling")
        let siblingPlan = AppCategory(profile: sibling, name: "Baseball", symbol: "figure.baseball", colorToken: "orange")

        XCTAssertFalse(ProfileScope.canAssign(siblingPlan, to: vihaan))
    }

    func testCannotAssignATaskToAnInactivePlan() {
        let profile = TestFixtures.profile("Vihaan")
        let plan = AppCategory(profile: profile, name: "Baseball", symbol: "figure.baseball", colorToken: "orange")
        plan.isActive = false

        XCTAssertFalse(ProfileScope.canAssign(plan, to: profile), "a hidden/removed Plan must never accept a new or reassigned Task")
    }

    // MARK: - Week generation stays profile-safe on an unfiltered Activity list

    /// Mirrors WeeklyScheduleView.generateVisibleWeek() exactly: it queries
    /// ALL profiles' Activities (no predicate) and passes that unfiltered
    /// list straight to PlanningService for a single profile's date.
    func testWeeklyGenerationOnlyInsertsItemsForTheRequestedProfileFromAnUnfilteredActivityList() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let vihaan = TestFixtures.profile("Vihaan")
        let sibling = TestFixtures.profile("Sibling")
        let vihaanArea = TestFixtures.area(profile: vihaan)
        let siblingArea = TestFixtures.area(profile: sibling)
        let monday = TestFixtures.date(2026, 6, 1)
        let vihaanActivity = Activity(
            profile: vihaan, category: vihaanArea, name: "Hitting",
            repeatType: .daily, weekdays: Array(1...7),
            plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 30, startDate: monday
        )
        let siblingActivity = Activity(
            profile: sibling, category: siblingArea, name: "Hitting",
            repeatType: .daily, weekdays: Array(1...7),
            plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 30, startDate: monday
        )
        context.insert(vihaan); context.insert(sibling)
        context.insert(vihaanArea); context.insert(siblingArea)
        context.insert(vihaanActivity); context.insert(siblingActivity)
        try context.save()

        // The all-profiles Activity list Schedule's own @Query would hand in.
        let allActivities = [vihaanActivity, siblingActivity]
        let generated = try PlanningService.insertMissingCalendarItems(
            profile: vihaan, date: monday, activities: allActivities, context: context
        )
        try context.save()

        XCTAssertEqual(generated.count, 1)
        XCTAssertEqual(generated.first?.profile?.id, vihaan.id)
        let allItems = try context.fetch(FetchDescriptor<CalendarItem>())
        XCTAssertTrue(allItems.allSatisfy { $0.profile?.id == vihaan.id }, "generating Vihaan's week must never create an occurrence for Sibling's identically named/timed Task")
    }
}
