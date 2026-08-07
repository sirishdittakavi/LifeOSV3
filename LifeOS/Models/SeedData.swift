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

    /// Moves older shared-label categories into the v1.6 profile-owned
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

    private static func ensureEssentialCategories(
        for profile: Profile, categories: inout [AppCategory], context: ModelContext
    ) {
        func ensure(_ name: String, symbol: String, color: String, pillar: ImprovementPillar,
                    purpose: String, sessions: Int, minutes: Int) {
            if categories.contains(where: { $0.profile?.id == profile.id && $0.name == name }) { return }
            let item = AppCategory(
                profile: profile, name: name, symbol: symbol, colorToken: color,
                pillar: pillar, purpose: purpose,
                weeklyTargetSessions: sessions, weeklyTargetMinutes: minutes
            )
            context.insert(item)
            categories.append(item)
        }

        ensure("Nutrition", symbol: "fork.knife", color: "green", pillar: .nutrition,
               purpose: "Fuel health, growth and performance against personal targets.", sessions: 7, minutes: 0)
        ensure(profile.kind == .child ? "Body Development" : "Weight Improvement",
               symbol: "scalemass.fill", color: "blue", pillar: .physical,
               purpose: "Track body trend without reacting to daily noise.", sessions: 3, minutes: 0)

        if profile.kind == .child {
            ensure("Baseball", symbol: "figure.baseball", color: "orange", pillar: .sport,
                   purpose: "Improve baseball through planned practice and feedback.", sessions: 5, minutes: 240)
            ensure("Mobility", symbol: "figure.flexibility", color: "teal", pillar: .physical,
                   purpose: "Build movement quality that supports sport.", sessions: 5, minutes: 75)
            ensure("Speed", symbol: "figure.run", color: "blue", pillar: .physical,
                   purpose: "Improve acceleration and running mechanics.", sessions: 3, minutes: 90)
        }
    }

    private static func applyDefaults(to category: AppCategory) {
        let name = category.name.lowercased()
        if name.contains("baseball") {
            category.pillar = .sport; category.weeklyTargetSessions = 5; category.weeklyTargetMinutes = 240
            category.purpose = "Improve baseball through planned practice and feedback."
        } else if name.contains("health") || name.contains("gym") {
            category.pillar = .physical; category.weeklyTargetSessions = 4; category.weeklyTargetMinutes = 240
        } else if name.contains("nutrition") {
            category.pillar = .nutrition; category.weeklyTargetSessions = 7; category.weeklyTargetMinutes = 0
        } else if name.contains("family") {
            category.pillar = .life
        } else {
            category.pillar = .learning
        }
        if category.purpose.isEmpty { category.purpose = "Improve through consistent, measurable action." }
    }

    private static func connectRelatedCategories(_ categories: [AppCategory]) {
        let byProfile = Dictionary(grouping: categories.compactMap { category in
            category.profile.map { ($0.id, category) }
        }, by: { $0.0 })

        for (_, pairs) in byProfile {
            let items = pairs.map(\.1)
            func item(containing text: String) -> AppCategory? {
                items.first { $0.name.localizedCaseInsensitiveContains(text) }
            }
            if let baseball = item(containing: "Baseball") {
                baseball.relatedCategoryIDs = [item(containing: "Mobility"), item(containing: "Speed"), item(containing: "Nutrition")]
                    .compactMap { $0?.id }
            }
            if let weight = item(containing: "Weight") ?? item(containing: "Body") {
                weight.relatedCategoryIDs = [item(containing: "Nutrition"), item(containing: "Health")]
                    .compactMap { $0?.id }
            }
        }
    }
}
