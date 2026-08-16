import Foundation

/// Pure validation/defaulting rules for Quick Add Task (AddActivityView.swift),
/// extracted out of the View so the past-time-default and create-time
/// validation behavior is unit-testable without SwiftUI state.
enum QuickAddValidation {
    /// Always at least an hour from `now`, regardless of what time it is --
    /// a fixed "6 pm today" default silently became a past time (and thus
    /// an invalid one-time Task) for the rest of every day after 6 pm.
    static func defaultOneTimeWhen(now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600)
    }

    /// A one-time Task's date/time must still be in the future at the moment
    /// Create is tapped, not just when the sheet first appeared -- a value
    /// can age past "now" while the sheet sits open.
    static func oneTimeWhenIsValid(when: Date, isRecurring: Bool, now: Date = .now) -> Bool {
        isRecurring || when >= now
    }

    static func canSave(
        name: String,
        hasValidCategory: Bool,
        isRecurring: Bool,
        selectedWeekdays: Set<Int>,
        when: Date,
        now: Date = .now
    ) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        hasValidCategory &&
        (!isRecurring || !selectedWeekdays.isEmpty) &&
        oneTimeWhenIsValid(when: when, isRecurring: isRecurring, now: now)
    }
}
