import XCTest
@testable import LifeOS

/// NutritionEngine / BodyTrackingEngine — the Nutrition-native counterpart
/// to ProgressEngine.nutritionTotals. Pure calculation tests, no
/// ModelContext.
final class NutritionEngineTests: XCTestCase {
    private func meal(
        profileID: UUID, mealType: MealType = .breakfast, on date: Date,
        calories: Double, proteinG: Double = 0, carbsG: Double = 0, fatG: Double = 0
    ) -> MealEntry {
        let entry = MealEntry(profileID: profileID, mealType: mealType, recordedAt: date)
        entry.totals = NutritionValue(calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
        return entry
    }

    // MARK: - dailyTotals

    func testDailyTotalsSumsOnlyThatProfilesMealsOnThatDay() {
        let profileID = UUID()
        let otherProfileID = UUID()
        let day = TestFixtures.date(2026, 1, 5)
        let meals = [
            meal(profileID: profileID, on: day, calories: 500, proteinG: 30),
            meal(profileID: profileID, on: day, calories: 400, proteinG: 20),
            meal(profileID: profileID, on: TestFixtures.date(2026, 1, 6), calories: 999, proteinG: 99),
            meal(profileID: otherProfileID, on: day, calories: 777, proteinG: 77)
        ]

        let totals = NutritionEngine.dailyTotals(profileID: profileID, date: day, meals: meals, waterEntries: [])

        XCTAssertEqual(totals.calories, 900)
        XCTAssertEqual(totals.proteinG, 50)
    }

    func testDailyTotalsIncludesWaterForThatProfileAndDayOnly() {
        let profileID = UUID()
        let day = TestFixtures.date(2026, 1, 5)
        let water = [
            WaterEntry(profileID: profileID, recordedAt: day, amountML: 250),
            WaterEntry(profileID: profileID, recordedAt: day, amountML: 500),
            WaterEntry(profileID: profileID, recordedAt: TestFixtures.date(2026, 1, 6), amountML: 1000),
            WaterEntry(profileID: UUID(), recordedAt: day, amountML: 2000)
        ]

        let totals = NutritionEngine.dailyTotals(profileID: profileID, date: day, meals: [], waterEntries: water)

        XCTAssertEqual(totals.waterML, 750)
    }

    // MARK: - targetProgress

    func testTargetProgressUsesGoalWhenPresent() {
        let profileID = UUID()
        let day = TestFixtures.date(2026, 1, 5)
        let goal = NutritionGoal(profileID: profileID, calorieTarget: 2000, proteinTargetG: 100, carbsTargetG: 200, fatTargetG: 60, waterTargetML: 3000)
        let meals = [meal(profileID: profileID, on: day, calories: 1000, proteinG: 50)]

        let progress = NutritionEngine.targetProgress(profileID: profileID, date: day, meals: meals, waterEntries: [], goal: goal)

        XCTAssertEqual(progress.calorieFraction, 0.5)
        XCTAssertEqual(progress.proteinFraction, 0.5)
    }

    /// Locked product decision: no NutritionGoal (or a NutritionGoal with a
    /// nil field) means no target — never a fallback/assumed value.
    func testTargetProgressHasNoTargetsWhenNoGoalExists() {
        let profileID = UUID()
        let progress = NutritionEngine.targetProgress(
            profileID: profileID, date: TestFixtures.date(2026, 1, 5), meals: [], waterEntries: [], goal: nil
        )
        XCTAssertNil(progress.calorieTarget)
        XCTAssertNil(progress.proteinTarget)
        XCTAssertNil(progress.calorieFraction)
        XCTAssertNil(progress.proteinFraction)
    }

    /// Protein-only target (User A from the product brief): the other four
    /// metrics must not silently receive a target or fraction.
    func testTargetProgressWithOnlyProteinConfigured() {
        let profileID = UUID()
        let day = TestFixtures.date(2026, 1, 5)
        let goal = NutritionGoal(profileID: profileID, proteinTargetG: 220)
        let meals = [meal(profileID: profileID, on: day, calories: 500, proteinG: 102)]

        let progress = NutritionEngine.targetProgress(profileID: profileID, date: day, meals: meals, waterEntries: [], goal: goal)

        XCTAssertEqual(progress.proteinTarget, 220)
        XCTAssertEqual(progress.proteinFraction ?? -1, 102.0 / 220.0, accuracy: 0.0001)
        XCTAssertNil(progress.calorieTarget)
        XCTAssertNil(progress.carbsTarget)
        XCTAssertNil(progress.fatTarget)
        XCTAssertNil(progress.waterTarget)
    }

    /// Updating the daily target (e.g. 120 -> 220) must be reflected the
    /// next time progress is computed — no cached/stale target value.
    func testUpdatingProteinTargetChangesProgressImmediately() {
        let profileID = UUID()
        let day = TestFixtures.date(2026, 1, 5)
        let goal = NutritionGoal(profileID: profileID, proteinTargetG: 120)
        let meals = [meal(profileID: profileID, on: day, calories: 0, proteinG: 102)]

        let before = NutritionEngine.targetProgress(profileID: profileID, date: day, meals: meals, waterEntries: [], goal: goal)
        XCTAssertEqual(before.proteinTarget, 120)

        goal.proteinTargetG = 220
        let after = NutritionEngine.targetProgress(profileID: profileID, date: day, meals: meals, waterEntries: [], goal: goal)
        XCTAssertEqual(after.proteinTarget, 220)
        XCTAssertEqual(after.proteinFraction ?? -1, 102.0 / 220.0, accuracy: 0.0001)
    }

    /// Clearing a target must remove the comparison entirely — actual meal
    /// history is untouched (still readable via `totals`).
    func testClearingATargetRemovesTargetComparisonButKeepsActualTotals() {
        let profileID = UUID()
        let day = TestFixtures.date(2026, 1, 5)
        let goal = NutritionGoal(profileID: profileID, proteinTargetG: 220)
        let meals = [meal(profileID: profileID, on: day, calories: 0, proteinG: 102)]

        goal.proteinTargetG = nil
        let progress = NutritionEngine.targetProgress(profileID: profileID, date: day, meals: meals, waterEntries: [], goal: goal)

        XCTAssertNil(progress.proteinTarget)
        XCTAssertNil(progress.proteinFraction)
        XCTAssertEqual(progress.totals.proteinG, 102, "actual intake is unaffected by clearing the target")
    }

    /// Multiple optional targets configured together (Protein + Water, per
    /// the product brief's User B) each work independently.
    func testMultipleOptionalTargetsWorkIndependently() {
        let profileID = UUID()
        let day = TestFixtures.date(2026, 1, 5)
        let goal = NutritionGoal(profileID: profileID, proteinTargetG: 100, waterTargetML: 2000)
        let meals = [meal(profileID: profileID, on: day, calories: 0, proteinG: 100)]
        let water = [WaterEntry(profileID: profileID, recordedAt: day, amountML: 1500)]

        let progress = NutritionEngine.targetProgress(profileID: profileID, date: day, meals: meals, waterEntries: water, goal: goal)

        XCTAssertEqual(progress.proteinFraction, 1.0)
        XCTAssertEqual(progress.waterFraction ?? -1, 0.75, accuracy: 0.0001)
        XCTAssertNil(progress.calorieTarget)
        XCTAssertNil(progress.carbsTarget)
        XCTAssertNil(progress.fatTarget)
    }

    func testFractionClampsAndHandlesZeroTargetSafely() {
        XCTAssertEqual(NutritionEngine.fraction(150, of: 100), 1.0)
        XCTAssertEqual(NutritionEngine.fraction(-10, of: 100), 0.0)
        XCTAssertEqual(NutritionEngine.fraction(50, of: 0), 0.0)
    }

    // MARK: - derivedTarget (daily -> weekly/monthly)

    func testDerivedTargetMultipliesDailyTargetByDayCount() {
        XCTAssertEqual(NutritionEngine.derivedTarget(dailyTarget: 220, days: 7), 1540)
        XCTAssertEqual(NutritionEngine.derivedTarget(dailyTarget: 220, days: 30), 6600)
        XCTAssertEqual(NutritionEngine.derivedTarget(dailyTarget: 220, days: 1), 220)
    }

    // MARK: - consistencyDays

    func testConsistencyDaysCountsOnlyDaysMeetingTheTarget() {
        let profileID = UUID()
        let goal = NutritionGoal(profileID: profileID, proteinTargetG: 100)
        let meals = [
            meal(profileID: profileID, on: TestFixtures.date(2026, 1, 1), calories: 0, proteinG: 120), // hit
            meal(profileID: profileID, on: TestFixtures.date(2026, 1, 2), calories: 0, proteinG: 50),  // miss
            meal(profileID: profileID, on: TestFixtures.date(2026, 1, 3), calories: 0, proteinG: 100)  // hit (exactly at target)
            // Jan 4: no entry at all — must count as a missed day, not be excluded.
        ]
        let interval = DateInterval(start: TestFixtures.date(2026, 1, 1), end: TestFixtures.date(2026, 1, 5))

        let result = NutritionEngine.consistencyDays(
            profileID: profileID, interval: interval, metric: .protein,
            meals: meals, waterEntries: [], goal: goal, calendar: TestFixtures.calendar
        )

        XCTAssertEqual(result?.achieved, 2)
        XCTAssertEqual(result?.totalDays, 4)
    }

    /// 30-day consistency window, matching Nutrition Progress's default
    /// reporting period.
    func testConsistencyDaysOverAThirtyDayWindow() {
        let profileID = UUID()
        let goal = NutritionGoal(profileID: profileID, proteinTargetG: 100)
        var meals: [MealEntry] = []
        for offset in 0..<30 {
            let day = TestFixtures.calendar.date(byAdding: .day, value: offset, to: TestFixtures.date(2026, 1, 1))!
            // Hit the target on even offsets only (15 of 30 days).
            let protein = offset.isMultiple(of: 2) ? 120.0 : 50.0
            meals.append(meal(profileID: profileID, on: day, calories: 0, proteinG: protein))
        }
        let interval = DateInterval(start: TestFixtures.date(2026, 1, 1), end: TestFixtures.date(2026, 1, 31))

        let result = NutritionEngine.consistencyDays(
            profileID: profileID, interval: interval, metric: .protein,
            meals: meals, waterEntries: [], goal: goal, calendar: TestFixtures.calendar
        )

        XCTAssertEqual(result?.achieved, 15)
        XCTAssertEqual(result?.totalDays, 30)
    }

    func testConsistencyDaysForWaterUsesWaterEntries() {
        let profileID = UUID()
        let goal = NutritionGoal(profileID: profileID, waterTargetML: 2000)
        let water = [
            WaterEntry(profileID: profileID, recordedAt: TestFixtures.date(2026, 1, 1), amountML: 2500),
            WaterEntry(profileID: profileID, recordedAt: TestFixtures.date(2026, 1, 2), amountML: 500)
        ]
        let interval = DateInterval(start: TestFixtures.date(2026, 1, 1), end: TestFixtures.date(2026, 1, 3))

        let result = NutritionEngine.consistencyDays(
            profileID: profileID, interval: interval, metric: .water,
            meals: [], waterEntries: water, goal: goal, calendar: TestFixtures.calendar
        )

        XCTAssertEqual(result?.achieved, 1)
        XCTAssertEqual(result?.totalDays, 2)
    }

    /// No configured target at all (no NutritionGoal, or a goal with that
    /// field nil) must report "not applicable", never a bogus 0/N.
    func testConsistencyDaysIsNilWhenNoTargetIsConfigured() {
        let profileID = UUID()
        let interval = DateInterval(start: TestFixtures.date(2026, 1, 1), end: TestFixtures.date(2026, 1, 8))

        XCTAssertNil(NutritionEngine.consistencyDays(
            profileID: profileID, interval: interval, metric: .protein,
            meals: [], waterEntries: [], goal: nil, calendar: TestFixtures.calendar
        ))

        let goalWithOtherTargetOnly = NutritionGoal(profileID: profileID, waterTargetML: 2000)
        XCTAssertNil(NutritionEngine.consistencyDays(
            profileID: profileID, interval: interval, metric: .protein,
            meals: [], waterEntries: [], goal: goalWithOtherTargetOnly, calendar: TestFixtures.calendar
        ), "a goal exists but has no Protein target configured")
    }

    // MARK: - metricTotal (Goal linkage)

    func testMetricTotalSumsAcrossTheInterval() {
        let profileID = UUID()
        let meals = [
            meal(profileID: profileID, on: TestFixtures.date(2026, 1, 1), calories: 0, proteinG: 100),
            meal(profileID: profileID, on: TestFixtures.date(2026, 1, 2), calories: 0, proteinG: 80),
            meal(profileID: profileID, on: TestFixtures.date(2026, 1, 10), calories: 0, proteinG: 999)
        ]
        let interval = DateInterval(start: TestFixtures.date(2026, 1, 1), end: TestFixtures.date(2026, 1, 3))

        let total = NutritionEngine.metricTotal(
            profileID: profileID, metric: .protein, interval: interval, meals: meals, waterEntries: []
        )

        XCTAssertEqual(total, 180)
    }

    // MARK: - sortedByRelevance

    func testSortedByRelevancePutsFavoritesFirstThenMostRecentThenMostUsed() {
        let favoriteOld = MealTemplate(profileID: UUID(), name: "Favorite Old", isFavorite: true, useCount: 1, lastUsedAt: TestFixtures.date(2026, 1, 1))
        let favoriteNew = MealTemplate(profileID: UUID(), name: "Favorite New", isFavorite: true, useCount: 1, lastUsedAt: TestFixtures.date(2026, 1, 10))
        let popularNonFavorite = MealTemplate(profileID: UUID(), name: "Popular", isFavorite: false, useCount: 20, lastUsedAt: TestFixtures.date(2026, 1, 5))
        let neverUsed = MealTemplate(profileID: UUID(), name: "Never Used", isFavorite: false, useCount: 0, lastUsedAt: nil)

        let sorted = NutritionEngine.sortedByRelevance([popularNonFavorite, neverUsed, favoriteOld, favoriteNew])

        XCTAssertEqual(sorted.map(\.name), ["Favorite New", "Favorite Old", "Popular", "Never Used"])
    }
}

final class BodyTrackingEngineTests: XCTestCase {
    func testLatestEntryReturnsTheMostRecentAtOrBeforeTheGivenDate() {
        let definition = BodyMetricDefinition(profileID: UUID(), name: "Weight", unit: "kg")
        let e1 = BodyMetricEntry(profileID: definition.profileID, bodyMetricDefinition: definition, nameSnapshot: "Weight", unitSnapshot: "kg", value: 80, recordedAt: TestFixtures.date(2026, 1, 1))
        let e2 = BodyMetricEntry(profileID: definition.profileID, bodyMetricDefinition: definition, nameSnapshot: "Weight", unitSnapshot: "kg", value: 78.5, recordedAt: TestFixtures.date(2026, 1, 12))

        let latest = BodyTrackingEngine.latestEntry(definitionID: definition.id, entries: [e1, e2], on: TestFixtures.date(2026, 1, 15))

        XCTAssertEqual(latest?.value, 78.5)
    }

    func testTrendComputesChangeFromOldestToLatestWithinInterval() {
        let definition = BodyMetricDefinition(profileID: UUID(), name: "Weight", unit: "kg")
        let entries = [
            BodyMetricEntry(profileID: definition.profileID, bodyMetricDefinition: definition, nameSnapshot: "Weight", unitSnapshot: "kg", value: 82, recordedAt: TestFixtures.date(2026, 1, 1)),
            BodyMetricEntry(profileID: definition.profileID, bodyMetricDefinition: definition, nameSnapshot: "Weight", unitSnapshot: "kg", value: 78.5, recordedAt: TestFixtures.date(2026, 1, 30))
        ]
        let interval = DateInterval(start: TestFixtures.date(2026, 1, 1), end: TestFixtures.date(2026, 2, 1))

        let trend = BodyTrackingEngine.trend(definitionID: definition.id, entries: entries, interval: interval)

        XCTAssertEqual(trend ?? 0, -3.5, accuracy: 0.0001)
    }

    func testTrendIsNilWithFewerThanTwoEntriesInInterval() {
        let definition = BodyMetricDefinition(profileID: UUID(), name: "Weight", unit: "kg")
        let entries = [
            BodyMetricEntry(profileID: definition.profileID, bodyMetricDefinition: definition, nameSnapshot: "Weight", unitSnapshot: "kg", value: 82, recordedAt: TestFixtures.date(2026, 1, 1))
        ]
        let interval = DateInterval(start: TestFixtures.date(2026, 1, 1), end: TestFixtures.date(2026, 2, 1))

        XCTAssertNil(BodyTrackingEngine.trend(definitionID: definition.id, entries: entries, interval: interval))
    }
}
