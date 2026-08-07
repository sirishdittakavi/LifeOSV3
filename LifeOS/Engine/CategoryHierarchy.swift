import Foundation

/// Editable containment for improvement areas. A broad area can contain
/// user-defined programs, subjects, teams, or projects. Containment remains
/// separate from cross-area relationships.
enum CategoryHierarchy {
    static func parent(of category: AppCategory, in categories: [AppCategory]) -> AppCategory? {
        guard let parentID = category.parentCategoryID else { return nil }
        return categories.first { $0.id == parentID }
    }

    static func directChildren(of category: AppCategory, in categories: [AppCategory]) -> [AppCategory] {
        categories
            .filter { $0.parentCategoryID == category.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func descendants(of category: AppCategory, in categories: [AppCategory]) -> [AppCategory] {
        var result: [AppCategory] = []
        var pending = directChildren(of: category, in: categories)
        var visited: Set<UUID> = [category.id]

        while let next = pending.first {
            pending.removeFirst()
            guard visited.insert(next.id).inserted else { continue }
            result.append(next)
            pending.append(contentsOf: directChildren(of: next, in: categories))
        }
        return result
    }

    static func ancestors(of category: AppCategory, in categories: [AppCategory]) -> [AppCategory] {
        var result: [AppCategory] = []
        var current = category
        var visited: Set<UUID> = [category.id]
        while let next = parent(of: current, in: categories), visited.insert(next.id).inserted {
            result.append(next)
            current = next
        }
        return result
    }

    static func idsIncludingDescendants(of category: AppCategory, in categories: [AppCategory]) -> Set<UUID> {
        Set([category.id] + descendants(of: category, in: categories).map(\.id))
    }

    static func isTopLevel(_ category: AppCategory, in categories: [AppCategory]) -> Bool {
        guard let parentID = category.parentCategoryID else { return true }
        return !categories.contains { $0.id == parentID && $0.isActive }
    }

    static func breadcrumbName(for category: AppCategory, in categories: [AppCategory]) -> String {
        let names = ancestors(of: category, in: categories).reversed().map(\.name) + [category.name]
        return names.joined(separator: " › ")
    }
}
