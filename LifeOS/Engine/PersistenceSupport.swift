import Foundation
import Observation
import SwiftData

/// A single user-visible reporting path for unexpected save failures.
/// Callers remain in control of whether a sheet should dismiss after saving.
@MainActor
@Observable
final class PersistenceIssueCenter {
    static let shared = PersistenceIssueCenter()
    var message: String?

    private init() {}

    func report(_ error: Error) {
        message = "Your change could not be saved. Nothing was intentionally deleted. \(error.localizedDescription)"
    }
}

extension ModelContext {
    @MainActor
    @discardableResult
    func saveOrReport() -> Bool {
        do {
            try save()
            return true
        } catch {
            PersistenceIssueCenter.shared.report(error)
            return false
        }
    }
}

enum ProfileScope {
    static func categories(for profile: Profile, from categories: [AppCategory]) -> [AppCategory] {
        categories.filter { $0.profile?.id == profile.id && $0.isActive }
    }

    static func canAssign(_ category: AppCategory, to profile: Profile) -> Bool {
        category.isActive && category.profile?.id == profile.id
    }
}

enum CompletionTiming {
    static func interval(endingAt end: Date, durationMinutes: Int) -> (start: Date, end: Date) {
        let safeMinutes = max(durationMinutes, 1)
        return (end.addingTimeInterval(-Double(safeMinutes * 60)), end)
    }
}
