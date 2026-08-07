import XCTest
import SwiftData
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif
@testable import LifeOS

@MainActor
final class GoalSystemComponentTests: XCTestCase {
    func testGoalGraphPersistsWithRelationshipsAndProfileIsolation() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let vihaan = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let parent = Profile(name: "Parent", kind: .parent, colorToken: "green")
        let baseball = AppCategory(
            profile: vihaan, name: "Baseball", symbol: "figure.baseball",
            colorToken: "orange", pillar: .sport
        )
        let goal = Goal(profile: vihaan, name: "Throw 70 mph")
        let contribution = GoalAreaContribution(goal: goal, category: baseball)
        let measure = ResultMeasure(
            goal: goal, name: "Throwing velocity", unit: "mph",
            baselineValue: 62, targetValue: 70
        )
        let entry = ResultEntry(profile: vihaan, measure: measure, numericValue: 65)
        [vihaan, parent].forEach(context.insert)
        context.insert(baseball)
        context.insert(goal)
        context.insert(contribution)
        context.insert(measure)
        context.insert(entry)
        try context.save()

        let storedGoals = try context.fetch(FetchDescriptor<Goal>())
        let storedEntries = try context.fetch(FetchDescriptor<ResultEntry>())

        XCTAssertEqual(storedGoals.count, 1)
        XCTAssertEqual(storedGoals.first?.profile?.id, vihaan.id)
        XCTAssertNotEqual(storedGoals.first?.profile?.id, parent.id)
        XCTAssertEqual(storedEntries.first?.measure?.goal?.name, "Throw 70 mph")
        XCTAssertEqual(storedEntries.first?.profile?.name, "Vihaan")
    }

    func testSchemaTwoBackupRoundTripRestoresCompleteGoalGraphWithoutDuplicates() throws {
        let source = try makeContainer()
        let sourceContext = source.mainContext
        let profile = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let area = AppCategory(
            profile: profile, name: "Nutrition", symbol: "fork.knife",
            colorToken: "green", pillar: .nutrition
        )
        let goal = Goal(profile: profile, name: "Reach a healthy weight range", purpose: "Support growth")
        let contribution = GoalAreaContribution(
            goal: goal, category: area, statement: "Consistent meals support growth",
            weeklyTargetSessions: 7, weeklyTargetMinutes: 0
        )
        let measure = ResultMeasure(
            goal: goal, name: "Body weight", unit: "kg", direction: .targetRange,
            baselineValue: 44, targetMinimum: 47, targetMaximum: 49,
            cadence: .monthly, nextCheckInDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let entry = ResultEntry(
            profile: profile, measure: measure, date: Date(timeIntervalSince1970: 1_700_000_000),
            numericValue: 45.5, sourceLabel: "Home scale", note: "Morning"
        )
        sourceContext.insert(profile)
        sourceContext.insert(area)
        sourceContext.insert(goal)
        sourceContext.insert(contribution)
        sourceContext.insert(measure)
        sourceContext.insert(entry)
        try sourceContext.save()

        let payload = LifeOSBackupService.make(
            profiles: [profile], categories: [area], activities: [], goals: [goal],
            goalContributions: [contribution], resultMeasures: [measure], resultEntries: [entry],
            calendarItems: [], sessions: [], foodEntries: [], weightEntries: [],
            sportEntries: [], savedTemplates: []
        )
        let encoded = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(LifeOSBackupPayload.self, from: encoded)
        let destination = try makeContainer()

        try LifeOSBackupService.restore(decoded, into: destination.mainContext)
        try LifeOSBackupService.restore(decoded, into: destination.mainContext)

        let goals = try destination.mainContext.fetch(FetchDescriptor<Goal>())
        let contributions = try destination.mainContext.fetch(FetchDescriptor<GoalAreaContribution>())
        let measures = try destination.mainContext.fetch(FetchDescriptor<ResultMeasure>())
        let entries = try destination.mainContext.fetch(FetchDescriptor<ResultEntry>())

        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(goals.count, 1)
        XCTAssertEqual(contributions.count, 1)
        XCTAssertEqual(measures.count, 1)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(contributions.first?.goal?.id, goals.first?.id)
        XCTAssertEqual(contributions.first?.category?.name, "Nutrition")
        XCTAssertEqual(measures.first?.targetMinimum, 47)
        XCTAssertEqual(entries.first?.measure?.id, measures.first?.id)
        XCTAssertEqual(entries.first?.sourceLabel, "Home scale")
    }

    func testPersistedManualWorkDoesNotChangePlannedGoalAdherence() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let area = AppCategory(
            profile: profile, name: "Baseball", symbol: "figure.baseball",
            colorToken: "orange", pillar: .sport
        )
        let goal = Goal(profile: profile, name: "Improve throwing")
        goal.createdAt = TestDate.make(2026, 1, 1)
        let contribution = GoalAreaContribution(goal: goal, category: area)
        let action = Activity(
            profile: profile, category: area, name: "Throwing practice",
            repeatType: .daily, plannedStartMinutes: 600,
            estimatedDurationMinutes: 30, startDate: TestDate.make(2026, 1, 1)
        )
        let scheduled = CalendarItem(
            profile: profile, activity: action, date: TestDate.make(2026, 1, 6),
            plannedStart: TestDate.make(2026, 1, 6, hour: 10), status: .done, source: .schedule
        )
        let manual = CalendarItem(
            profile: profile, activity: action, date: TestDate.make(2026, 1, 6),
            plannedStart: TestDate.make(2026, 1, 6, hour: 15), status: .done, source: .manual
        )
        context.insert(profile)
        context.insert(area)
        context.insert(goal)
        context.insert(contribution)
        context.insert(action)
        context.insert(scheduled)
        context.insert(manual)
        try context.save()

        let storedItems = try context.fetch(FetchDescriptor<CalendarItem>())
        let result = GoalProgressEngine.progress(
            goal: goal, period: .day, now: TestDate.make(2026, 1, 6, hour: 20),
            categories: [area], contributions: [contribution], measures: [], entries: [],
            activities: [action], calendarItems: storedItems, calendar: TestDate.calendar
        )

        XCTAssertEqual(storedItems.count, 2)
        XCTAssertEqual(result.contributions.first?.plannedActions, 1)
        XCTAssertEqual(result.contributions.first?.completedActions, 1)
    }

    #if canImport(UIKit)
    func testGoalsAndTodayComponentsConstructAgainstRealSwiftDataSchema() throws {
        let container = try makeContainer()
        let profile = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        container.mainContext.insert(profile)
        try container.mainContext.save()
        let selection = SelectedProfile()
        selection.profile = profile

        let goalsHost = UIHostingController(
            rootView: ImprovementDashboardView(selection: selection).modelContainer(container)
        )
        let todayHost = UIHostingController(
            rootView: TodayTimelineView(selection: selection).modelContainer(container)
        )
        goalsHost.loadViewIfNeeded()
        todayHost.loadViewIfNeeded()
        goalsHost.view.layoutIfNeeded()
        todayHost.view.layoutIfNeeded()

        XCTAssertNotNil(goalsHost.view)
        XCTAssertNotNil(todayHost.view)
        XCTAssertFalse(goalsHost.view.subviews.isEmpty)
        XCTAssertFalse(todayHost.view.subviews.isEmpty)
    }
    #endif

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Profile.self, SavedCategoryTemplate.self, AppCategory.self,
            Goal.self, GoalAreaContribution.self, ResultMeasure.self, ResultEntry.self,
            Activity.self, CalendarItem.self, ActivitySession.self,
            FoodEntry.self, WeightEntry.self, SportEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

private enum TestDate {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func make(
        _ year: Int, _ month: Int, _ day: Int,
        hour: Int = 0, minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone, year: year, month: month, day: day,
            hour: hour, minute: minute
        ))!
    }
}
