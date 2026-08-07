import Foundation
@testable import LifeOS

enum TestFixtures {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    static func date(
        _ year: Int = 2026, _ month: Int = 1, _ day: Int = 1,
        hour: Int = 0, minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone, year: year, month: month, day: day,
            hour: hour, minute: minute
        ))!
    }

    static func profile(_ name: String = "Vihaan") -> Profile {
        Profile(name: name, kind: .child, colorToken: "blue")
    }

    static func area(profile: Profile, name: String = "Baseball") -> AppCategory {
        AppCategory(
            profile: profile, name: name, symbol: "figure.baseball",
            colorToken: "orange", pillar: .sport,
            weeklyTargetSessions: 3, weeklyTargetMinutes: 120
        )
    }

    static func goal(
        profile: Profile, name: String = "Improve throwing velocity",
        createdAt: Date = date(), targetDate: Date? = date(2026, 1, 11)
    ) -> Goal {
        let goal = Goal(profile: profile, name: name, targetDate: targetDate)
        goal.createdAt = createdAt
        return goal
    }

    static func measure(
        goal: Goal, type: ResultValueType = .number,
        direction: ResultDirection = .increase,
        baseline: Double? = 60, target: Double? = 70,
        minimum: Double? = nil, maximum: Double? = nil
    ) -> ResultMeasure {
        ResultMeasure(
            goal: goal, name: "Throwing velocity", valueType: type, unit: "mph",
            direction: direction, baselineValue: baseline, targetValue: target,
            targetMinimum: minimum, targetMaximum: maximum,
            cadence: .monthly, nextCheckInDate: date(2026, 2, 1)
        )
    }

    static func progress(
        goal: Goal, categories: [AppCategory] = [],
        contributions: [GoalAreaContribution] = [], measures: [ResultMeasure] = [],
        entries: [ResultEntry] = [], activities: [Activity] = [],
        items: [CalendarItem] = [], now: Date = date(2026, 1, 6),
        period: DashboardPeriod = .week
    ) -> GoalProgress {
        GoalProgressEngine.progress(
            goal: goal, period: period, now: now, categories: categories,
            contributions: contributions, measures: measures, entries: entries,
            activities: activities, calendarItems: items, calendar: calendar
        )
    }
}
