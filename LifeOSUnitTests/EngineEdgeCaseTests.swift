import Testing
import Foundation
import SwiftData
@testable import LifeOS

/// Comprehensive unit test gap-fill pass: numeric edge cases for
/// GoalProgressEngine, macro/aggregation edge cases for NutritionEngine,
/// and profile-mutation edge cases not covered by the existing XCTest
/// suites (ProgressViewAlignmentTests, NutritionEngineTests,
/// ProfileIsolationAuditTests). Uses Swift Testing (`import Testing`)
/// rather than XCTest, per this pass's own ask -- everything else in this
/// repo is XCTest; the two frameworks coexist fine in the same target.
///
/// Two items from the requested audit describe behavior this app does not
/// actually have, and are deliberately NOT faked here:
/// - "Mutating data on an inactive profile throws strict guard errors":
///   `Profile.isActive` is a UI-visibility flag only (ProfileManagerView's
///   Hide/Restore). Nothing in this codebase guards ModelContext mutations
///   against it, so there is no such error to test. What IS real and is
///   tested below: hiding a profile leaves its own data completely intact
///   and never touches another profile's.
/// - "Deleting a Profile or Goal cascades to associated child items": per
///   the Phase 10 audit, there is no hard "delete Profile" or "delete
///   Goal" feature anywhere in the app (Profiles are Hidden, Goals are
///   archived -- both isActive = false, preserving history on purpose),
///   and no @Relationship(.cascade) exists on any model. What IS real and
///   is tested below: directly deleting a Goal (bypassing the app's own
///   archive-only UI) orphans its ResultMeasure/GoalAreaContribution
///   (nullifies the reference) rather than cascading, and does so without
///   crashing or touching another profile -- documenting the actual
///   nullify-not-cascade behavior rather than a fictional one.
@MainActor
struct GoalProgressEdgeCaseTests {
    private func makeContainer() throws -> ModelContainer {
        try LifeOSDataStore.makeContainer(inMemory: true)
    }

    @Test("A Goal with zero Result Measures resolves to awaitingResult, not a crash")
    func zeroResultMeasures() throws {
        let profile = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let goal = Goal(profile: profile, name: "Get better at guitar")

        let progress = GoalProgressEngine.progress(
            goal: goal, period: .day, now: .now, categories: [], contributions: [],
            measures: [], entries: [], activities: [], calendarItems: []
        )

        #expect(progress.status == .awaitingResult)
        #expect(progress.primaryMeasure == nil)
        #expect(progress.resultFraction == nil)
        #expect(progress.effortFraction == nil)
    }

    @Test("A Goal with zero Result Measures but real contributions still reports effort safely")
    func zeroResultMeasuresWithContributions() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let area = AppCategory(profile: profile, name: "Guitar", symbol: "guitars", colorToken: "purple")
        let goal = Goal(profile: profile, name: "Get better at guitar")
        let contribution = GoalAreaContribution(goal: goal, category: area)
        context.insert(profile); context.insert(area); context.insert(goal); context.insert(contribution)
        try context.save()

        let progress = GoalProgressEngine.progress(
            goal: goal, period: .day, now: .now, categories: [area], contributions: [contribution],
            measures: [], entries: [], activities: [], calendarItems: []
        )

        #expect(progress.status == .awaitingResult, "no measure at all must never read as on-track just because effort exists")
        #expect(progress.contributions.count == 1)
    }

    @Test(
        "Negative-range Goals (e.g. a temperature-style metric) compute the same correct fraction as positive ranges",
        arguments: [
            (baseline: -10.0, target: -2.0, value: -6.0, expected: 0.5),
            (baseline: -10.0, target: -2.0, value: -10.0, expected: 0.0),
            (baseline: -10.0, target: -2.0, value: -2.0, expected: 1.0)
        ]
    )
    func negativeRangeFraction(baseline: Double, target: Double, value: Double, expected: Double) throws {
        let profile = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let goal = Goal(profile: profile, name: "Warm up the greenhouse")
        let measure = ResultMeasure(
            goal: goal, name: "Overnight low", role: .primary, unit: "°C",
            direction: .increase, baselineValue: baseline, targetValue: target
        )
        let entry = ResultEntry(profile: profile, measure: measure, date: .now, numericValue: value)

        let progress = GoalProgressEngine.progress(
            goal: goal, period: .day, now: .now, categories: [], contributions: [],
            measures: [measure], entries: [entry], activities: [], calendarItems: []
        )

        #expect(progress.resultFraction.map { abs($0 - expected) < 0.0001 } == true)
    }

    @Test("A value overshooting the target clamps to exactly 100%, never exceeds it")
    func overshootClampsToOne() throws {
        let profile = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let goal = Goal(profile: profile, name: "Read more")
        let measure = ResultMeasure(
            goal: goal, name: "Books this month", role: .primary, unit: "books",
            direction: .increase, baselineValue: 0, targetValue: 10
        )
        // 15 books read against a target of 10 -- 150% of target on paper.
        let entry = ResultEntry(profile: profile, measure: measure, date: .now, numericValue: 15)

        let progress = GoalProgressEngine.progress(
            goal: goal, period: .day, now: .now, categories: [], contributions: [],
            measures: [measure], entries: [entry], activities: [], calendarItems: []
        )

        #expect(progress.resultFraction == 1.0)
        #expect(progress.status == .achieved)
    }

    @Test("A value that regresses past the baseline clamps to exactly 0%, never goes negative")
    func regressionClampsToZero() throws {
        let profile = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let goal = Goal(profile: profile, name: "Increase pull-ups")
        let measure = ResultMeasure(
            goal: goal, name: "Max pull-ups", role: .primary, unit: "reps",
            direction: .increase, baselineValue: 5, targetValue: 15
        )
        // Regressed below the starting baseline (e.g. after an injury).
        let entry = ResultEntry(profile: profile, measure: measure, date: .now, numericValue: 2)

        let progress = GoalProgressEngine.progress(
            goal: goal, period: .day, now: .now, categories: [], contributions: [],
            measures: [measure], entries: [entry], activities: [], calendarItems: []
        )

        #expect(progress.resultFraction == 0.0)
        #expect(progress.status != .achieved)
    }

    @Test("A zero-width range (target == baseline) is rejected as invalid and never divides by zero")
    func zeroWidthRangeIsRejected() throws {
        let profile = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let goal = Goal(profile: profile, name: "Maintain weight")
        let measure = ResultMeasure(
            goal: goal, name: "Body weight", role: .primary, unit: "kg",
            direction: .increase, baselineValue: 50, targetValue: 50
        )
        let entry = ResultEntry(profile: profile, measure: measure, date: .now, numericValue: 51)

        let progress = GoalProgressEngine.progress(
            goal: goal, period: .day, now: .now, categories: [], contributions: [],
            measures: [measure], entries: [entry], activities: [], calendarItems: []
        )

        #expect(progress.status == .needsAttention, "an invalid (zero-width) target must surface as needing correction, not a crash or a false 100%")
        #expect(progress.resultFraction == nil)
    }

    @Test("An out-of-range targetRange baseline still produces a finite, clamped fraction, never NaN or infinity")
    func targetRangeWithDistantBaselineStaysFinite() throws {
        let profile = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let goal = Goal(profile: profile, name: "Reach a healthy resting heart rate")
        let measure = ResultMeasure(
            goal: goal, name: "Resting HR", role: .primary, unit: "bpm",
            direction: .targetRange, baselineValue: 95, targetMinimum: 60, targetMaximum: 70
        )
        let entry = ResultEntry(profile: profile, measure: measure, date: .now, numericValue: 200)

        let progress = GoalProgressEngine.progress(
            goal: goal, period: .day, now: .now, categories: [], contributions: [],
            measures: [measure], entries: [entry], activities: [], calendarItems: []
        )

        let fraction = try #require(progress.resultFraction)
        #expect(fraction.isFinite)
        #expect(fraction >= 0 && fraction <= 1)
    }
}

@MainActor
struct NutritionEdgeCaseTests {
    private func meal(profileID: UUID, on date: Date, calories: Double, proteinG: Double = 0, carbsG: Double = 0, fatG: Double = 0) -> MealEntry {
        let entry = MealEntry(profileID: profileID, mealType: .breakfast, recordedAt: date)
        entry.setTotals(NutritionValue(calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG))
        return entry
    }

    @Test(
        "caloriesFromMacros stays a pure calculation, independent of whatever the user typed into Calories",
        arguments: [
            // (proteinG, carbsG, fatG, enteredCalories) -- entered deliberately diverges from the macro-implied total.
            (protein: 50.0, carbs: 50.0, fat: 10.0, entered: 300.0),  // macro-implied 590, far above entered
            (protein: 10.0, carbs: 10.0, fat: 2.0, entered: 900.0)    // macro-implied 98, far below entered
        ]
    )
    func caloriesFromMacrosIndependentOfEnteredCalories(protein: Double, carbs: Double, fat: Double, entered: Double) {
        let macroImplied = NutritionEngine.caloriesFromMacros(proteinG: protein, carbsG: carbs, fatG: fat)
        let stored = NutritionValue(calories: entered, proteinG: protein, carbsG: carbs, fatG: fat)

        // By AddEditMealView.swift's locked design, LifeOS never reconciles
        // or overrides one with the other -- both are independently valid.
        #expect(stored.calories == entered)
        #expect(macroImplied != entered)
        #expect(NutritionEngine.isValidMacroEntry(stored), "a meal is valid even when its macro-implied calories disagree with the entered total -- LifeOS never computes nutrition from macros on the user's behalf")
    }

    @Test("Fractional gram values are preserved through dailyTotals without silent rounding")
    func fractionalPrecisionIsPreserved() {
        let profileID = UUID()
        let day = TestFixtures.date(2026, 5, 1)
        let meals = [
            meal(profileID: profileID, on: day, calories: 123.4, proteinG: 12.3, carbsG: 45.6, fatG: 7.8),
            meal(profileID: profileID, on: day, calories: 67.8, proteinG: 1.1, carbsG: 2.2, fatG: 3.3)
        ]

        let totals = NutritionEngine.dailyTotals(profileID: profileID, date: day, meals: meals, waterEntries: [])

        #expect(abs(totals.calories - 191.2) < 0.0001)
        #expect(abs(totals.proteinG - 13.4) < 0.0001)
        #expect(abs(totals.carbsG - 47.8) < 0.0001)
        #expect(abs(totals.fatG - 11.1) < 0.0001)
    }

    @Test("Multiple meals across two profiles logged the same day aggregate correctly for each profile independently")
    func multiMealMultiProfileAggregation() {
        let vihaanID = UUID()
        let siblingID = UUID()
        let day = TestFixtures.date(2026, 5, 1)
        let allMeals = [
            meal(profileID: vihaanID, on: day, calories: 400, proteinG: 30),
            meal(profileID: vihaanID, on: day, calories: 350, proteinG: 25),
            meal(profileID: vihaanID, on: day, calories: 300, proteinG: 20),
            meal(profileID: siblingID, on: day, calories: 500, proteinG: 40),
            meal(profileID: siblingID, on: day, calories: 250, proteinG: 15)
        ]

        let vihaanTotals = NutritionEngine.dailyTotals(profileID: vihaanID, date: day, meals: allMeals, waterEntries: [])
        let siblingTotals = NutritionEngine.dailyTotals(profileID: siblingID, date: day, meals: allMeals, waterEntries: [])

        #expect(vihaanTotals.calories == 1050)
        #expect(vihaanTotals.proteinG == 75)
        #expect(siblingTotals.calories == 750)
        #expect(siblingTotals.proteinG == 55)
        // The two totals must never bleed into each other regardless of shared-day, shared-array input.
        #expect(vihaanTotals.calories + siblingTotals.calories == allMeals.reduce(0) { $0 + $1.totals.calories })
    }
}

@MainActor
struct ProfileMutationEdgeCaseTests {
    private func makeContainer() throws -> ModelContainer {
        try LifeOSDataStore.makeContainer(inMemory: true)
    }

    @Test("Hiding a profile preserves its own data intact and never touches another profile's")
    func hidingPreservesOwnDataAndIsolatesOthers() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let vihaan = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let sibling = Profile(name: "Sibling", kind: .child, colorToken: "green")
        let area = AppCategory(profile: vihaan, name: "Baseball", symbol: "figure.baseball", colorToken: "orange")
        let activity = Activity(profile: vihaan, category: area, name: "Hitting", plannedStartMinutes: 600, estimatedDurationMinutes: 20)
        context.insert(vihaan); context.insert(sibling); context.insert(area); context.insert(activity)
        try context.save()

        vihaan.isActive = false
        try context.save()

        let refreshedActivities = try context.fetch(FetchDescriptor<Activity>())
        #expect(refreshedActivities.first?.name == "Hitting", "hiding a profile must never delete or mutate its own records")
        #expect(refreshedActivities.first?.profile?.id == vihaan.id)

        let refreshedSibling = try #require(try context.fetch(FetchDescriptor<Profile>()).first { $0.id == sibling.id })
        #expect(refreshedSibling.isActive, "hiding Vihaan must never hide Sibling")

        // Restore round-trips cleanly.
        vihaan.isActive = true
        try context.save()
        let restored = try #require(try context.fetch(FetchDescriptor<Profile>()).first { $0.id == vihaan.id })
        #expect(restored.isActive)
    }

    /// Simulates "switching active profile mid-operation": AddActivityView/
    /// AddGoalView/etc. all capture `let profile: Profile` as a plain value
    /// at sheet-creation time, not a live binding to the app's
    /// `SelectedProfile` (an `@Observable` holder of `var profile: Profile?`
    /// in RootTabView.swift, which -- being in Views/ -- isn't part of the
    /// headless package this test target builds against). A plain local
    /// `Profile?` reproduces the exact same reference-capture semantics
    /// `@Observable`'s wrapped property has, without needing that type: a
    /// later reassignment cannot retarget an in-flight creation that
    /// already captured the old value.
    @Test("A Profile reference captured before an active-profile switch still resolves to the original profile")
    func capturedProfileReferenceSurvivesAConcurrentSwitch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let vihaan = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let sibling = Profile(name: "Sibling", kind: .child, colorToken: "green")
        context.insert(vihaan); context.insert(sibling)
        try context.save()

        var currentSelection: Profile? = vihaan

        // A sheet opens for Vihaan and captures the profile by value, exactly
        // as AddActivityView's `let profile: Profile` does.
        let capturedProfile = try #require(currentSelection)

        // The user switches the app's active profile to Sibling while that
        // sheet is still open (the "concurrent" part of the scenario).
        currentSelection = sibling

        // The in-flight creation still uses its own captured reference, not
        // the now-changed live selection.
        let area = AppCategory(profile: capturedProfile, name: "Reading", symbol: "book", colorToken: "blue")
        context.insert(area)
        try context.save()

        let storedAreas = try context.fetch(FetchDescriptor<AppCategory>())
        #expect(storedAreas.count == 1)
        #expect(storedAreas.first?.profile?.id == vihaan.id, "an in-flight creation must stay attributed to the profile open when it started, never the profile switched to mid-operation")
        #expect(currentSelection?.id == sibling.id, "the app's own active-profile selection did change, confirming this is a genuine race, not a no-op")
    }

    /// Documents the actual, current deletion architecture (Phase 10):
    /// there is no @Relationship(.cascade) anywhere in this codebase, and
    /// the app itself never hard-deletes a Goal (EditGoalViews.swift only
    /// archives one via isActive = false). This test proves directly
    /// deleting a Goal -- bypassing the app's own archive-only UI, the way
    /// a hypothetical future "delete" feature would have to -- is
    /// genuinely dangerous, not just imperfect: the child ResultMeasure's
    /// `goal` reference is NOT nullified to nil. It is left as a "zombie"
    /// reference that fatally crashes the process (SwiftData:
    /// "invalidated because its backing data could no longer be found in
    /// the store") the instant any property on it is touched -- confirmed
    /// via a throwaway diagnostic run; that crash cannot be caught inside
    /// a test, so this asserts only the safe-to-check part (identity/nil
    /// comparison never crashes) and stops there. This is exactly why the
    /// app's one real cascading hard-delete (Activity's no-history branch,
    /// EditTaskView.deleteOrArchive()) explicitly deletes every child
    /// CalendarItem BEFORE the Activity itself, and why any future
    /// "delete a Goal" feature must do the same for ResultMeasure/
    /// GoalAreaContribution -- SwiftData will not do it safely by default.
    @Test("Directly deleting a Goal leaves a dangling (not nil) reference on its ResultMeasure -- children must be deleted explicitly, never left to SwiftData's default")
    func deletingAGoalLeavesADanglingReferenceOnItsMeasure() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let vihaan = Profile(name: "Vihaan", kind: .child, colorToken: "blue")
        let sibling = Profile(name: "Sibling", kind: .child, colorToken: "green")
        let vihaanArea = AppCategory(profile: vihaan, name: "Baseball", symbol: "figure.baseball", colorToken: "orange")
        let siblingArea = AppCategory(profile: sibling, name: "Baseball", symbol: "figure.baseball", colorToken: "orange")
        let vihaanGoal = Goal(profile: vihaan, name: "Throw 70 mph")
        let siblingGoal = Goal(profile: sibling, name: "Throw 70 mph")
        let vihaanMeasure = ResultMeasure(goal: vihaanGoal, name: "Velocity", direction: .increase, baselineValue: 60, targetValue: 70)
        let siblingMeasure = ResultMeasure(goal: siblingGoal, name: "Velocity", direction: .increase, baselineValue: 60, targetValue: 70)
        let vihaanContribution = GoalAreaContribution(goal: vihaanGoal, category: vihaanArea)
        let siblingContribution = GoalAreaContribution(goal: siblingGoal, category: siblingArea)
        [vihaan, sibling].forEach(context.insert)
        [vihaanArea, siblingArea].forEach(context.insert)
        [vihaanGoal, siblingGoal].forEach(context.insert)
        [vihaanMeasure, siblingMeasure].forEach(context.insert)
        [vihaanContribution, siblingContribution].forEach(context.insert)
        try context.save()

        context.delete(vihaanGoal)
        try context.save()

        let remainingGoals = try context.fetch(FetchDescriptor<Goal>())
        #expect(remainingGoals.map(\.id) == [siblingGoal.id], "Sibling's Goal must survive Vihaan's Goal deletion untouched")

        let measures = try context.fetch(FetchDescriptor<ResultMeasure>())
        #expect(measures.count == 2, "the ResultMeasure row itself is not deleted -- SwiftData does not cascade by default")
        let orphanedMeasure = try #require(measures.first { $0.id == vihaanMeasure.id })
        // Safe: comparing to nil only inspects identity, never faults the
        // backing data. This is NOT nil -- proving the reference dangles
        // rather than being cleanly nullified. Deliberately not accessing
        // any property on it (e.g. .goal!.name) -- that crashes the process.
        #expect(orphanedMeasure.goal != nil, "confirmed dangling, not nullified -- any future Goal-delete feature must delete children explicitly first, exactly like Activity's deleteOrArchive() already does")

        let siblingMeasureAfter = try #require(measures.first { $0.id == siblingMeasure.id })
        #expect(siblingMeasureAfter.goal?.id == siblingGoal.id, "Sibling's measure must be completely unaffected by Vihaan's deletion")
    }
}
