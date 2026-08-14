//
//  LifeOSApp.swift
//  LifeOS
//
//  Local-first app entry point with an explicit Version 1 SwiftData schema.
//  A persistent-store failure opens a recovery gate before the user can log
//  anything. Temporary use requires confirmation and remains visibly marked.
//

import SwiftUI
import SwiftData
import Observation

@main
struct LifeOSApp: App {
    @State private var store = LifeOSStore()

    var body: some Scene {
        WindowGroup {
            StoreRecoveryGate(store: store)
                .modelContainer(store.container)
                .onAppear { NotificationRouter.shared.configure(container: store.container) }
                .onChange(of: store.persistentStoreFailed) { _, failed in
                    if !failed { NotificationRouter.shared.configure(container: store.container) }
                }
        }
    }
}

@MainActor
@Observable
final class LifeOSStore {
    private(set) var container: ModelContainer
    private(set) var persistentStoreFailed = false

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            do {
                let container = try LifeOSDataStore.makeContainer(inMemory: true)
                try Self.prepareUITestFixture(container)
                self.container = container
                return
            } catch {
                fatalError("LifeOS UI-test fixture failed: \(error.localizedDescription)")
            }
        }
        #endif
        do {
            let container = try LifeOSDataStore.makeContainer(inMemory: false)
            try Self.prepare(container)
            self.container = container
        } catch {
            self.container = Self.makeFallbackContainer()
            self.persistentStoreFailed = true
            Self.logStoreFailure(error)
        }
    }

    func retryPersistentStore() {
        do {
            let container = try LifeOSDataStore.makeContainer(inMemory: false)
            try Self.prepare(container)
            self.container = container
            self.persistentStoreFailed = false
        } catch {
            Self.logStoreFailure(error)
        }
    }

    private static func prepare(_ container: ModelContainer) throws {
        try SeedData.seedIfNeeded(context: container.mainContext)
    }

    #if DEBUG
    /// A small, deterministic workspace used only by XCUITest. Release and
    /// TestFlight builds do not contain this test-data path.
    private static func prepareUITestFixture(_ container: ModelContainer) throws {
        UserDefaults.standard.set(true, forKey: "LifeOS.onboarding.v1.completed")
        UserDefaults.standard.removeObject(forKey: SelectedProfile.lastProfileKey)

        let context = container.mainContext
        let profile = Profile(name: "Parent", kind: .individual, colorToken: "blue")
        let baseball = AppCategory(
            profile: profile, name: "Baseball", symbol: "baseball.fill",
            colorToken: "orange", pillar: .sport, trackingKind: .sport,
            purpose: "Build dependable baseball skills.",
            weeklyTargetSessions: 21, weeklyTargetMinutes: 210
        )
        let nutrition = AppCategory(
            profile: profile, name: "Nutrition", symbol: "fork.knife",
            colorToken: "green", pillar: .nutrition, trackingKind: .nutrition,
            purpose: "Fuel training and recovery.",
            weeklyTargetSessions: 7, weeklyTargetMinutes: 0
        )
        let bodyWeight = AppCategory(
            profile: profile, name: "Body Weight", symbol: "scalemass.fill",
            colorToken: "purple", pillar: .physical, trackingKind: .bodyWeight,
            purpose: "Track weight and body composition trend.",
            weeklyTargetSessions: 1, weeklyTargetMinutes: 0
        )
        context.insert(profile)
        context.insert(baseball)
        context.insert(nutrition)
        context.insert(bodyWeight)

        let goal = Goal(
            profile: profile, name: "Become a Complete Baseball Player",
            purpose: "Improve batting, pitching, and fielding through a balanced plan."
        )
        let contribution = GoalAreaContribution(
            goal: goal, category: baseball,
            statement: "Baseball practice supports this Goal.",
            weeklyTargetSessions: 11, weeklyTargetMinutes: 110
        )
        context.insert(goal)
        context.insert(contribution)

        let todayWeekday = Calendar.current.component(.weekday, from: .now)
        let otherWeekdays = (1...7).filter { $0 != todayWeekday }.prefix(2)
        let tasks = [
            Activity(
                profile: profile, category: baseball, name: "Hitting",
                source: .manual, targetValue: 10, targetUnit: "min",
                repeatType: .daily, weekdays: Array(1...7),
                plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 10,
                startDate: Calendar.current.startOfDay(for: .now)
            ),
            Activity(
                profile: profile, category: baseball, name: "Pitching",
                source: .manual, targetValue: 10, targetUnit: "min",
                repeatType: .timesPerWeek,
                weekdays: ([todayWeekday] + Array(otherWeekdays)).sorted(),
                occurrencesPerWeek: 3,
                plannedStartMinutes: 18 * 60 + 15, estimatedDurationMinutes: 10,
                startDate: Calendar.current.startOfDay(for: .now)
            ),
            Activity(
                profile: profile, category: baseball, name: "Fielding",
                source: .manual, targetValue: 10, targetUnit: "min",
                repeatType: .timesPerWeek, weekdays: [todayWeekday],
                occurrencesPerWeek: 1,
                plannedStartMinutes: 18 * 60 + 30, estimatedDurationMinutes: 10,
                startDate: Calendar.current.startOfDay(for: .now)
            )
        ]
        tasks.forEach(context.insert)

        context.insert(Activity(
            profile: profile, category: baseball, name: "Future Conditioning",
            source: .manual, targetValue: 10, targetUnit: "min",
            repeatType: .daily, weekdays: Array(1...7),
            plannedStartMinutes: 19 * 60, estimatedDurationMinutes: 10,
            startDate: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        ))

        try seedNutritionFixture(profile: profile, context: context)
        try seedChildAndUnrelatedProfiles(context: context)
        try context.save()

        // ProfilePicker defaults to the last-selected profile (falling back
        // to alphabetically-first only when none is saved) — "Child" sorts
        // before "Parent", so without this, adding the Child fixture would
        // silently change which profile every pre-existing test lands on.
        UserDefaults.standard.set(profile.id.uuidString, forKey: SelectedProfile.lastProfileKey)
    }

    /// LifeOS XCUITest and Notification Ownership Release Pass: a second
    /// profile ("Child") with DELIBERATELY IDENTICAL Area/Activity/Goal/
    /// Template/Weight-definition names and an identical schedule to
    /// "Parent" above — the exact trap that would expose an ownership bug
    /// resolving by name instead of by ID. Plus a third, unrelated profile
    /// ("Unrelated") that no isolation test should ever see touched.
    private static func seedChildAndUnrelatedProfiles(context: ModelContext) throws {
        let child = Profile(name: "Child", kind: .child, colorToken: "orange")
        let unrelated = Profile(name: "Unrelated", kind: .individual, colorToken: "gray")
        context.insert(child)
        context.insert(unrelated)

        let childBaseball = AppCategory(
            profile: child, name: "Baseball", symbol: "baseball.fill",
            colorToken: "orange", pillar: .sport, trackingKind: .sport,
            purpose: "Build dependable baseball skills.",
            weeklyTargetSessions: 21, weeklyTargetMinutes: 210
        )
        let childNutritionCategory = AppCategory(
            profile: child, name: "Nutrition", symbol: "fork.knife",
            colorToken: "green", pillar: .nutrition, trackingKind: .nutrition,
            purpose: "Fuel training and recovery.",
            weeklyTargetSessions: 7, weeklyTargetMinutes: 0
        )
        let childBodyWeightCategory = AppCategory(
            profile: child, name: "Body Weight", symbol: "scalemass.fill",
            colorToken: "purple", pillar: .physical, trackingKind: .bodyWeight,
            purpose: "Track weight and body composition trend.",
            weeklyTargetSessions: 1, weeklyTargetMinutes: 0
        )
        context.insert(childBaseball)
        context.insert(childNutritionCategory)
        context.insert(childBodyWeightCategory)

        let childGoal = Goal(
            profile: child, name: "Become a Complete Baseball Player",
            purpose: "Improve batting, pitching, and fielding through a balanced plan."
        )
        let childContribution = GoalAreaContribution(
            goal: childGoal, category: childBaseball,
            statement: "Baseball practice supports this Goal.",
            weeklyTargetSessions: 11, weeklyTargetMinutes: 110
        )
        context.insert(childGoal)
        context.insert(childContribution)

        // Identical name AND identical schedule to Parent's own "Hitting".
        let childHitting = Activity(
            profile: child, category: childBaseball, name: "Hitting",
            source: .manual, targetValue: 10, targetUnit: "min",
            repeatType: .daily, weekdays: Array(1...7),
            plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 10,
            startDate: Calendar.current.startOfDay(for: .now)
        )
        context.insert(childHitting)

        let childNutritionGoal = NutritionGoal(
            profileID: child.id, calorieTarget: 2200, proteinTargetG: 120,
            carbsTargetG: 250, fatTargetG: 70, waterTargetML: 2500
        )
        context.insert(childNutritionGoal)

        let childNutritionRepository = SwiftDataNutritionRepository(context: context)
        let childBreakfastTemplate = MealTemplate(
            profileID: child.id, name: "My Protein Breakfast", mealTypeDefault: .breakfast,
            details: "3 eggs, oats 60g, protein shake",
            totals: NutritionValue(calories: 622, proteinG: 51, carbsG: 48, fatG: 22)
        )
        childNutritionRepository.insertTemplate(childBreakfastTemplate, foodEntries: [])

        let childBodyRepository = SwiftDataBodyTrackingRepository(context: context)
        childBodyRepository.seedDefaultDefinitionsIfNeeded(profileID: child.id, existingDefinitions: [])
        try context.save()
        let childBodyDefinitions = try context.fetch(FetchDescriptor<BodyMetricDefinition>())
        if let childWeightDefinition = childBodyDefinitions.first(where: { $0.profileID == child.id && $0.name == "Weight" }) {
            let childWeightHistory: [(daysAgo: Int, value: Double)] = [(7, 55.0), (0, 54.5)]
            for point in childWeightHistory {
                let date = Calendar.current.date(byAdding: .day, value: -point.daysAgo, to: .now) ?? .now
                context.insert(BodyMetricEntry(
                    profileID: child.id, bodyMetricDefinition: childWeightDefinition,
                    nameSnapshot: "Weight", unitSnapshot: "kg", value: point.value, recordedAt: date
                ))
            }
            let childWeightMeasure = ResultMeasure(
                goal: childGoal, name: "Weight", valueType: .number, unit: "kg",
                direction: .decrease, baselineValue: 56, targetValue: 52,
                linkedBodyMetricDefinitionID: childWeightDefinition.id
            )
            context.insert(childWeightMeasure)
        }
    }

    /// Realistic Nutrition v1 fixture data for the manual simulator review —
    /// separate from the rest of prepareUITestFixture so it's obviously
    /// additive and easy to remove later. DEBUG + -ui-testing only, same as
    /// the rest of this fixture.
    ///
    /// TEST DATA ONLY: the target values below (2200 kcal / 120g protein /
    /// etc.) are arbitrary sample numbers chosen to make the UI test
    /// fixture look realistic on screen — they are NOT defaults LifeOS
    /// prescribes to real users. A real profile's NutritionGoal starts with
    /// every field `nil` until the person explicitly sets it in Nutrition
    /// Targets (see NutritionGoal's own doc comment and NutritionTargetsView).
    private static func seedNutritionFixture(profile: Profile, context: ModelContext) throws {
        let nutritionGoal = NutritionGoal(
            profileID: profile.id, calorieTarget: 2200, proteinTargetG: 120,
            carbsTargetG: 250, fatTargetG: 70, waterTargetML: 2500
        )
        context.insert(nutritionGoal)

        let bodyRepository = SwiftDataBodyTrackingRepository(context: context)
        bodyRepository.seedDefaultDefinitionsIfNeeded(profileID: profile.id, existingDefinitions: [])
        try context.save()
        let bodyDefinitions = try context.fetch(FetchDescriptor<BodyMetricDefinition>())
        let weightDefinition = bodyDefinitions.first { $0.profileID == profile.id && $0.name == "Weight" }
        let heightDefinition = bodyDefinitions.first { $0.profileID == profile.id && $0.name == "Height" }
        let bodyFatDefinition = bodyDefinitions.first { $0.profileID == profile.id && $0.name == "Body Fat %" }

        if let weightDefinition {
            let weightHistory: [(daysAgo: Int, value: Double)] = [
                (42, 82.0), (35, 81.2), (28, 80.5), (21, 79.8), (14, 79.0), (7, 78.5), (0, 78.5)
            ]
            for point in weightHistory {
                let date = Calendar.current.date(byAdding: .day, value: -point.daysAgo, to: .now) ?? .now
                context.insert(BodyMetricEntry(
                    profileID: profile.id, bodyMetricDefinition: weightDefinition,
                    nameSnapshot: "Weight", unitSnapshot: "kg", value: point.value, recordedAt: date
                ))
            }
        }
        if let heightDefinition {
            context.insert(BodyMetricEntry(
                profileID: profile.id, bodyMetricDefinition: heightDefinition,
                nameSnapshot: "Height", unitSnapshot: "cm", value: 178,
                recordedAt: Calendar.current.date(byAdding: .month, value: -6, to: .now) ?? .now
            ))
        }
        if let bodyFatDefinition {
            context.insert(BodyMetricEntry(
                profileID: profile.id, bodyMetricDefinition: bodyFatDefinition,
                nameSnapshot: "Body Fat %", unitSnapshot: "%", value: 18.2,
                recordedAt: Calendar.current.date(byAdding: .day, value: -9, to: .now) ?? .now
            ))
        }

        // V1 locked decision: each template is ONE fixed, user-entered set
        // of totals + a free-text description — never a per-food
        // breakdown, never calculated, never scaled by serving size. A
        // different portion (e.g. 1 cup rice instead of 0.5) is simply a
        // different, separate template — see the two Lamb Shank templates
        // below, which intentionally do NOT derive one from the other.
        let nutritionRepository = SwiftDataNutritionRepository(context: context)

        let lambShankHalfCup = MealTemplate(
            profileID: profile.id, name: "Coles Lamb Shank + 0.5 cup rice", mealTypeDefault: .dinner,
            details: "Coles Lamb Shank\nRice: 0.5 cup",
            totals: NutritionValue(calories: 873, proteinG: 70, carbsG: 88, fatG: 25),
            isFavorite: true, useCount: 12,
            lastUsedAt: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        )
        nutritionRepository.insertTemplate(lambShankHalfCup, foodEntries: [])

        // Same core meal, different portion — a separate template, not a
        // scaled/derived version of the one above.
        let lambShankFullCup = MealTemplate(
            profileID: profile.id, name: "Coles Lamb Shank + 1 cup rice", mealTypeDefault: .dinner,
            details: "Coles Lamb Shank\nRice: 1 cup",
            totals: NutritionValue(calories: 1046, proteinG: 70, carbsG: 126, fatG: 25),
            useCount: 3, lastUsedAt: Calendar.current.date(byAdding: .day, value: -8, to: .now) ?? .now
        )
        nutritionRepository.insertTemplate(lambShankFullCup, foodEntries: [])

        let breakfastTemplate = MealTemplate(
            profileID: profile.id, name: "My Protein Breakfast", mealTypeDefault: .breakfast,
            details: "3 eggs, oats 60g, protein shake",
            totals: NutritionValue(calories: 622, proteinG: 51, carbsG: 48, fatG: 22),
            useCount: 4, lastUsedAt: Calendar.current.date(byAdding: .day, value: -6, to: .now) ?? .now
        )
        nutritionRepository.insertTemplate(breakfastTemplate, foodEntries: [])

        let breakfastMeal = MealEntry(
            profileID: profile.id, mealType: .breakfast,
            recordedAt: Calendar.current.date(bySettingHour: 7, minute: 40, second: 0, of: .now) ?? .now,
            sourceTemplateID: breakfastTemplate.id, sourceTemplateNameSnapshot: breakfastTemplate.name,
            details: breakfastTemplate.details
        )
        nutritionRepository.insertMeal(breakfastMeal, foodEntries: [])
        breakfastMeal.setTotals(breakfastTemplate.totals)

        let lunchMeal = MealEntry(
            profileID: profile.id, mealType: .lunch,
            recordedAt: Calendar.current.date(bySettingHour: 12, minute: 30, second: 0, of: .now) ?? .now,
            details: "Chicken breast 150g, rice 150g"
        )
        nutritionRepository.insertMeal(lunchMeal, foodEntries: [])
        lunchMeal.setTotals(NutritionValue(calories: 445, proteinG: 51, carbsG: 42, fatG: 6))

        // A past, non-template lunch so Recent Meals has content too.
        let pastLunch = MealEntry(
            profileID: profile.id, mealType: .lunch,
            recordedAt: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now,
            details: "Turkey wrap"
        )
        nutritionRepository.insertMeal(pastLunch, foodEntries: [])
        pastLunch.setTotals(NutritionValue(calories: 480, proteinG: 30, carbsG: 45, fatG: 18))

        nutritionRepository.insertWaterEntry(WaterEntry(profileID: profile.id, recordedAt: Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now, amountML: 500))
        nutritionRepository.insertWaterEntry(WaterEntry(profileID: profile.id, recordedAt: Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: .now) ?? .now, amountML: 500))
        nutritionRepository.insertWaterEntry(WaterEntry(profileID: profile.id, recordedAt: Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: .now) ?? .now, amountML: 800))

        // A Goal linked to a Nutrition metric, to review the Goal ↔
        // Nutrition/Body result-linking UI end to end (review item 8).
        let nutritionLinkedGoal = Goal(profile: profile, name: "Hit my protein target consistently")
        context.insert(nutritionLinkedGoal)
        let proteinMeasure = ResultMeasure(
            goal: nutritionLinkedGoal, name: "Protein", valueType: .number, unit: "g",
            direction: .increase, baselineValue: 0, targetValue: 3000,
            linkedNutritionMetric: .protein
        )
        context.insert(proteinMeasure)

        if let weightDefinition {
            let weightLinkedGoal = Goal(profile: profile, name: "Reach race weight")
            context.insert(weightLinkedGoal)
            let weightMeasure = ResultMeasure(
                goal: weightLinkedGoal, name: "Weight", valueType: .number, unit: "kg",
                direction: .decrease, baselineValue: 82, targetValue: 76,
                linkedBodyMetricDefinitionID: weightDefinition.id
            )
            context.insert(weightMeasure)
        }
    }
    #endif

    private static func makeFallbackContainer() -> ModelContainer {
        do {
            let container = try LifeOSDataStore.makeContainer(inMemory: true)
            try prepare(container)
            return container
        } catch {
            fatalError("LifeOS model schema is invalid: \(error.localizedDescription)")
        }
    }

    private static func logStoreFailure(_ error: Error) {
        #if DEBUG
        print("LifeOS persistent store failed to load: \(error.localizedDescription)")
        #endif
    }
}

private struct StoreRecoveryGate: View {
    @Bindable var store: LifeOSStore
    @State private var temporarySessionAccepted = false
    @State private var confirmingTemporarySession = false

    var body: some View {
        Group {
            if store.persistentStoreFailed && !temporarySessionAccepted {
                recoveryView
            } else {
                RootTabView()
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if store.persistentStoreFailed {
                            temporarySessionWarning
                        }
                    }
            }
        }
        .confirmationDialog(
            "Use a Temporary Session?",
            isPresented: $confirmingTemporarySession,
            titleVisibility: .visible
        ) {
            Button("Use Temporary Session", role: .destructive) {
                temporarySessionAccepted = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anything entered in the temporary session will disappear when LifeOS closes.")
        }
        .onChange(of: store.persistentStoreFailed) { _, failed in
            if !failed { temporarySessionAccepted = false }
        }
    }

    private var recoveryView: some View {
        ContentUnavailableView {
            Label("Saved Data Couldn’t Open", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("LifeOS has not changed or deleted the saved database. Retry first. Temporary mode is available for viewing the app, but it cannot save this session permanently.")
        } actions: {
            VStack(spacing: LifeOSSpacing.md) {
                Button("Retry", action: store.retryPersistentStore)
                    .buttonStyle(.borderedProminent)
                Button("Use Temporary Session") {
                    confirmingTemporarySession = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(LifeOSSpacing.xl)
    }

    private var temporarySessionWarning: some View {
        Label("Temporary session — changes will be lost", systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, LifeOSSpacing.lg)
            .padding(.vertical, LifeOSSpacing.sm)
            .foregroundStyle(.black)
            .background(Color.yellow)
            .accessibilityHint("Close LifeOS and reopen it after resolving the saved-data problem")
    }
}
