import Foundation
import SwiftData

enum SeedData {
    static func seedIfNeeded(context: ModelContext) {
        let profiles = (try? context.fetch(FetchDescriptor<Profile>())) ?? []
        if profiles.isEmpty {
            seedFreshWorkspace(context: context)
        }
        upgradeImprovementCategoriesIfNeeded(context: context)
        try? context.save()
    }

    private static func seedFreshWorkspace(context: ModelContext) {
        // A fresh install starts with one neutral owner profile. Children and
        // other household members are always optional, user-created profiles.
        let owner = Profile(name: "My Profile", kind: .individual, colorToken: "blue")
        context.insert(owner)

        let movement = category(
            owner, "Movement", "figure.run", "blue", .physical,
            "Build sustainable movement, fitness and energy.", 4, 160, context
        )
        let learning = category(
            owner, "Learning", "lightbulb.fill", "yellow", .learning,
            "Improve through consistent, focused learning.", 5, 150, context
        )
        let nutrition = category(
            owner, "Nutrition", "fork.knife", "green", .nutrition,
            "Support health and performance with useful nutrition evidence.", 7, 0, context
        )
        let recovery = category(
            owner, "Recovery", "bed.double.fill", "indigo", .life,
            "Protect sleep, recovery and sustainable effort.", 7, 0, context
        )

        movement.relatedCategoryIDs = [nutrition.id, recovery.id]
        nutrition.relatedCategoryIDs = [movement.id, recovery.id]
        recovery.relatedCategoryIDs = [movement.id, nutrition.id]

        [
            Activity(profile: owner, category: movement, name: "Move or Train", source: .template,
                     targetValue: 40, targetUnit: "min", repeatType: .selectedWeekdays,
                     weekdays: [2, 4, 6, 7], plannedStartMinutes: 7 * 60,
                     estimatedDurationMinutes: 40),
            Activity(profile: owner, category: learning, name: "Focused Learning", source: .template,
                     targetValue: 30, targetUnit: "min", repeatType: .selectedWeekdays,
                     weekdays: [2, 3, 4, 5, 6], plannedStartMinutes: 19 * 60,
                     estimatedDurationMinutes: 30)
        ].forEach { context.insert($0) }
    }

    private static func category(
        _ profile: Profile, _ name: String, _ symbol: String, _ color: String,
        _ pillar: ImprovementPillar, _ purpose: String, _ sessions: Int, _ minutes: Int,
        _ context: ModelContext
    ) -> AppCategory {
        let item = AppCategory(
            profile: profile, name: name, symbol: symbol, colorToken: color,
            pillar: pillar, purpose: purpose,
            weeklyTargetSessions: sessions, weeklyTargetMinutes: minutes
        )
        context.insert(item)
        return item
    }

    /// Moves shared-label categories into the profile-owned
    /// improvement-area model without deleting activities or history.
    private static func upgradeImprovementCategoriesIfNeeded(context: ModelContext) {
        let profiles = (try? context.fetch(FetchDescriptor<Profile>())) ?? []
        let activities = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        var categories = (try? context.fetch(FetchDescriptor<AppCategory>())) ?? []

        for category in categories where category.profile == nil {
            let categoryActivities = activities.filter { $0.category?.id == category.id }
            let owners = profiles.filter { profile in
                categoryActivities.contains { $0.profile?.id == profile.id }
            }

            if let firstOwner = owners.first {
                category.profile = firstOwner
                applyDefaults(to: category)
                for owner in owners.dropFirst() {
                    let duplicate = AppCategory(
                        profile: owner, name: category.name, symbol: category.symbol,
                        colorToken: category.colorToken, pillar: category.pillar,
                        purpose: category.purpose, weeklyTargetSessions: category.weeklyTargetSessions,
                        weeklyTargetMinutes: category.weeklyTargetMinutes
                    )
                    context.insert(duplicate)
                    categoryActivities.filter { $0.profile?.id == owner.id }.forEach { $0.category = duplicate }
                    categories.append(duplicate)
                }
            } else {
                category.profile = profiles.first
                applyDefaults(to: category)
            }
        }

        // Starter content is chosen explicitly when a profile is created.
        // Never add sport- or health-specific categories on every launch, and
        // never overwrite relationships the user has edited.
    }

    private static func applyDefaults(to category: AppCategory) {
        if category.purpose.isEmpty { category.purpose = "Improve through consistent, measurable action." }
    }
}
