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
        let parent = Profile(name: "Sirish", kind: .parent, colorToken: "blue")
        let child = Profile(name: "Junior", kind: .child, colorToken: "orange")
        child.calorieGoal = 2000
        child.proteinGoalGrams = 90
        child.weeklyBaseballMinutesGoal = 240
        context.insert(parent)
        context.insert(child)

        let parentHealth = category(
            parent, "Health & Fitness", "heart.fill", "red", .physical,
            "Build strength, fitness and sustainable energy.", 4, 240, context
        )
        let career = category(
            parent, "Career", "briefcase.fill", "blue", .learning,
            "Perform meaningful professional work.", 5, 300, context
        )
        let family = category(
            parent, "Family", "person.2.fill", "pink", .life,
            "Protect consistent, present family time.", 7, 210, context
        )
        let software = category(
            parent, "Software Development", "chevron.left.forwardslash.chevron.right", "purple", .learning,
            "Improve engineering skill through deliberate practice and projects.", 5, 225, context
        )
        let parentNutrition = category(
            parent, "Nutrition", "fork.knife", "green", .nutrition,
            "Fuel health and training against personal targets.", 7, 0, context
        )
        let parentWeight = category(
            parent, "Weight Improvement", "scalemass.fill", "blue", .physical,
            "Track body trend without reacting to daily noise.", 3, 0, context
        )

        let education = category(
            child, "Education", "book.fill", "indigo", .learning,
            "Stay prepared for school and complete important learning work.", 5, 300, context
        )
        let learning = category(
            child, "Reading & Learning", "lightbulb.fill", "yellow", .learning,
            "Build curiosity and consistent reading practice.", 7, 140, context
        )
        let baseball = category(
            child, "Baseball", "figure.baseball", "orange", .sport,
            "Improve baseball skill through planned practice, feedback and recovery.", 5, 240, context
        )
        let mobility = category(
            child, "Mobility", "figure.flexibility", "teal", .physical,
            "Build usable range of motion that supports baseball and daily movement.", 5, 75, context
        )
        let speed = category(
            child, "Speed", "figure.run", "blue", .physical,
            "Improve acceleration and running mechanics progressively.", 3, 90, context
        )
        let childNutrition = category(
            child, "Nutrition", "fork.knife", "green", .nutrition,
            "Support growth, training and recovery with parent-approved targets.", 7, 0, context
        )
        let childWeight = category(
            child, "Body Development", "scalemass.fill", "blue", .physical,
            "Observe healthy body development without restrictive or punitive targets.", 3, 0, context
        )

        baseball.relatedCategoryIDs = [mobility.id, speed.id, childNutrition.id]
        mobility.relatedCategoryIDs = [baseball.id, speed.id]
        speed.relatedCategoryIDs = [baseball.id, mobility.id, childWeight.id]
        parentWeight.relatedCategoryIDs = [parentNutrition.id, parentHealth.id]
        parentNutrition.relatedCategoryIDs = [parentWeight.id, parentHealth.id]

        let weekdays = [2, 3, 4, 5, 6]
        let monWedFri = [2, 4, 6]

        [
            Activity(profile: parent, category: parentHealth, name: "Gym", source: .template,
                     targetValue: 45, targetUnit: "min", repeatType: .selectedWeekdays, weekdays: [2, 3, 5, 6],
                     plannedStartMinutes: 7 * 60, estimatedDurationMinutes: 60),
            Activity(profile: parent, category: career, name: "Focused Work", source: .template,
                     repeatType: .selectedWeekdays, weekdays: weekdays,
                     plannedStartMinutes: 9 * 60, estimatedDurationMinutes: 60),
            Activity(profile: parent, category: family, name: "Family Dinner", source: .template,
                     repeatType: .daily, plannedStartMinutes: 18 * 60 + 30, estimatedDurationMinutes: 45),
            Activity(profile: parent, category: software, name: "Software Practice", source: .template,
                     tags: ["coding", "learning"], targetValue: 45, targetUnit: "min",
                     repeatType: .selectedWeekdays, weekdays: weekdays,
                     plannedStartMinutes: 20 * 60, estimatedDurationMinutes: 45),
            Activity(profile: child, category: education, name: "Homework", source: .template,
                     repeatType: .selectedWeekdays, weekdays: weekdays,
                     plannedStartMinutes: 17 * 60, estimatedDurationMinutes: 45),
            Activity(profile: child, category: baseball, name: "Hitting Practice", source: .template,
                     tags: ["baseball", "batting"], targetValue: 100, targetUnit: "swings",
                     repeatType: .selectedWeekdays, weekdays: [2, 3, 5, 7],
                     plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 60),
            Activity(profile: child, category: mobility, name: "Mobility Routine", source: .template,
                     targetValue: 15, targetUnit: "min", repeatType: .selectedWeekdays, weekdays: weekdays,
                     plannedStartMinutes: 7 * 60 + 30, estimatedDurationMinutes: 15),
            Activity(profile: child, category: speed, name: "Sprint Technique", source: .template,
                     targetValue: 30, targetUnit: "min", repeatType: .selectedWeekdays, weekdays: monWedFri,
                     plannedStartMinutes: 16 * 60 + 15, estimatedDurationMinutes: 30),
            Activity(profile: child, category: learning, name: "Reading", source: .template,
                     targetValue: 20, targetUnit: "min", repeatType: .daily,
                     plannedStartMinutes: 20 * 60, estimatedDurationMinutes: 20)
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
