//
//  NutritionDashboardView.swift
//  LifeOS
//
//  NUTRITION_MODULE_DESIGN_V1.md Screen 01 (refined per review: Protein is
//  the primary hero, Calories secondary). Built entirely from the existing
//  LifeOS DesignSystem (LOCard/LOMetricTile/LOProgressBar/LOChip/
//  LOProgressRing) — no new component vocabulary.
//

import SwiftUI
import SwiftData

struct NutritionDashboardView: View {
    @Bindable var selection: SelectedProfile
    @Environment(\.modelContext) private var modelContext

    @Query private var meals: [MealEntry]
    @Query private var waterEntries: [WaterEntry]
    @Query private var nutritionGoals: [NutritionGoal]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showingQuickActions = false
    @State private var loggingMealType: MealType?
    @State private var showingTemplates = false
    @State private var showingBodyTracking = false
    @State private var showingProgress = false
    @State private var showingTargets = false

    private let mealChecklist: [MealType] = [.breakfast, .lunch, .dinner, .snack]

    private var profileID: UUID? { selection.profile?.id }

    private var goal: NutritionGoal? {
        guard let profileID else { return nil }
        return nutritionGoals.first { $0.profileID == profileID }
    }

    private var todaysMeals: [MealEntry] {
        guard let profileID else { return [] }
        return meals.filter { $0.profileID == profileID && Calendar.current.isDateInToday($0.recordedAt) }
    }

    private var progress: NutritionEngine.TargetProgress? {
        guard let profileID else { return nil }
        return NutritionEngine.targetProgress(
            profileID: profileID, date: .now, meals: meals, waterEntries: waterEntries, goal: goal
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LifeOSSpacing.lg) {
                    subNavRow
                    if let progress {
                        proteinHeroCard(progress)
                        secondaryMetricsCard(progress)
                        mealsCard
                    } else {
                        ContentUnavailableView("Choose a Profile", systemImage: "person.crop.circle")
                    }
                }
                .padding(LifeOSSpacing.lg)
            }
            .navigationTitle("Nutrition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfilePicker(selection: selection) }
                ToolbarItem(placement: .topBarTrailing) {
                    // The single always-visible action — a second icon here
                    // pushes iOS to auto-collapse both into a hidden "..."
                    // overflow menu. Templates/Body Tracking/Progress/
                    // Targets moved to a visible tab row below the nav bar
                    // instead (one tap, not menu-then-tap).
                    Button { showingQuickActions = true } label: { Image(systemName: "plus.circle.fill") }
                        .accessibilityLabel("Log Meal, Water, or Weight")
                        .accessibilityIdentifier("nutrition.meal.add")
                }
            }
            .sheet(isPresented: $showingQuickActions) {
                QuickActionSheet(selection: selection, onLogMeal: { mealType in
                    showingQuickActions = false
                    loggingMealType = mealType
                })
            }
            .sheet(item: $loggingMealType) { mealType in
                MealLoggingView(selection: selection, mealType: mealType)
            }
            .sheet(isPresented: $showingTemplates) { MealTemplatesView(selection: selection) }
            .sheet(isPresented: $showingBodyTracking) { BodyTrackingView(selection: selection) }
            .sheet(isPresented: $showingProgress) { NutritionProgressView(selection: selection) }
            .sheet(isPresented: $showingTargets) { NutritionTargetsView(selection: selection) }
        }
    }

    /// One tap to each secondary Nutrition screen — replaces the earlier
    /// "•••" overflow menu, which needed a menu-open tap before the actual
    /// destination tap.
    private var subNavRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LifeOSSpacing.sm) {
                LOChip(title: "Templates", symbol: "star", isSelected: false) { showingTemplates = true }
                    .fixedSize()
                LOChip(title: "Body Tracking", symbol: "scalemass", isSelected: false) { showingBodyTracking = true }
                    .fixedSize()
                LOChip(title: "Progress", symbol: "chart.line.uptrend.xyaxis", isSelected: false) { showingProgress = true }
                    .fixedSize()
                LOChip(title: "Targets", symbol: "target", isSelected: false) { showingTargets = true }
                    .fixedSize()
            }
        }
    }

    /// Protein is the primary hero metric only when the user has actually
    /// configured a protein target — otherwise a ring implying "0% of an
    /// assumed target" would misrepresent a target LifeOS never assumed.
    /// Without a target this still shows today's protein prominently, just
    /// without any target-progress framing (NUTRITION_MODULE_DESIGN_V1
    /// "Fix User-Defined Nutrition Targets" §6).
    private func proteinHeroCard(_ progress: NutritionEngine.TargetProgress) -> some View {
        Group {
            if let proteinTarget = progress.proteinTarget, let proteinFraction = progress.proteinFraction {
                proteinTargetHero(progress, target: proteinTarget, fraction: proteinFraction)
            } else {
                proteinNoTargetHero(progress)
            }
        }
    }

    private func proteinTargetHero(_ progress: NutritionEngine.TargetProgress, target: Double, fraction: Double) -> some View {
        // At accessibility Dynamic Type sizes the ring's fixed diameter
        // can't grow with the text, so the ring + detail column stack
        // vertically instead of side by side once the text would no
        // longer fit legibly next to it.
        let ring = LOProgressRing(fraction: fraction, status: .focus, diameter: 108, lineWidth: 12) {
            VStack(spacing: 0) {
                Text(Int(progress.totals.proteinG), format: .number)
                    .font(.lifeOSValueEmphasis)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                // "g protein" is redundant with "Protein today" / "Xg of
                // Yg" right next to it once those grow to accessibility
                // sizes — the fixed-diameter ring has no room for a second
                // line at that point, so it's dropped rather than clipped.
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("g protein")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
        }
        let detail = VStack(alignment: .leading, spacing: LifeOSSpacing.xs) {
            Text("Protein today")
                .font(.lifeOSSectionTitle)
            Text("\(Int(progress.totals.proteinG))g of \(Int(target))g")
                .font(.lifeOSSecondary)
                .foregroundStyle(.secondary)
            calorieCaption(progress)
        }

        return LOCard(tint: .lifeOSFocus) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: LifeOSSpacing.lg) {
                        ring
                        detail
                    }
                } else {
                    HStack(spacing: LifeOSSpacing.lg) {
                        ring
                        detail
                        Spacer()
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Protein, \(Int(progress.totals.proteinG)) of \(Int(target)) grams today")
        .accessibilityIdentifier("nutrition.total.protein")
    }

    private func proteinNoTargetHero(_ progress: NutritionEngine.TargetProgress) -> some View {
        LOCard(tint: .lifeOSFocus) {
            VStack(alignment: .leading, spacing: LifeOSSpacing.xs) {
                Text("Protein today")
                    .font(.lifeOSSectionTitle)
                Text("\(Int(progress.totals.proteinG))g")
                    .font(.lifeOSHeroMetric)
                calorieCaption(progress)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Protein, \(Int(progress.totals.proteinG)) grams today, no target set")
        .accessibilityIdentifier("nutrition.total.protein")
    }

    private func calorieCaption(_ progress: NutritionEngine.TargetProgress) -> some View {
        Group {
            if let calorieTarget = progress.calorieTarget {
                Text("\(Int(progress.totals.calories)) / \(Int(calorieTarget)) kcal")
            } else {
                Text("\(Int(progress.totals.calories)) kcal today")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func secondaryMetricsCard(_ progress: NutritionEngine.TargetProgress) -> some View {
        LOCard {
            VStack(alignment: .leading, spacing: LifeOSSpacing.md) {
                NutritionMetricRow(
                    label: "Calories", currentText: "\(Int(progress.totals.calories))",
                    unitSuffix: "", targetText: progress.calorieTarget.map { "\(Int($0))" },
                    fraction: progress.calorieFraction, status: .neutral
                )
                .accessibilityIdentifier("nutrition.total.calories")
                NutritionMetricRow(
                    label: "Carbs", currentText: "\(Int(progress.totals.carbsG))",
                    unitSuffix: "g", targetText: progress.carbsTarget.map { "\(Int($0))g" },
                    fraction: progress.carbsFraction, status: .inProgress
                )
                NutritionMetricRow(
                    label: "Fat", currentText: "\(Int(progress.totals.fatG))",
                    unitSuffix: "g", targetText: progress.fatTarget.map { "\(Int($0))g" },
                    fraction: progress.fatFraction, status: .recovery
                )
                NutritionMetricRow(
                    label: "Water",
                    currentText: (progress.totals.waterML / 1000).formatted(.number.precision(.fractionLength(1))),
                    unitSuffix: "L",
                    targetText: progress.waterTarget.map { "\(($0 / 1000).formatted(.number.precision(.fractionLength(1))))L" },
                    fraction: progress.waterFraction, status: .complete
                )
                .accessibilityIdentifier("nutrition.water.total")
            }
        }
    }

    private var mealsCard: some View {
        VStack(alignment: .leading, spacing: LifeOSSpacing.sm) {
            LOSectionHeader(title: "Meals")
            LOCard {
                VStack(spacing: 0) {
                    ForEach(mealChecklist) { mealType in
                        let logged = todaysMeals.first { $0.mealType == mealType }
                        Button { loggingMealType = mealType } label: {
                            HStack(spacing: LifeOSSpacing.md) {
                                LOStatusControl(status: logged != nil ? .complete : .neutral, size: 26)
                                Text(mealType.rawValue)
                                    .font(.lifeOSCardTitle)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if let logged {
                                    Text("\(Int(logged.totals.calories)) kcal")
                                        .font(.lifeOSSecondary)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, LifeOSSpacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("nutrition.meal.\(mealType.rawValue.lowercased())")
                        if mealType != mealChecklist.last {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

/// A local, Nutrition-only equivalent of LOProgressBar. Kept separate from
/// the shared component (rather than modifying it) because LOProgressBar is
/// also used by Area Hub/DailyProgressView, which this change must not
/// touch. Two things LOProgressBar doesn't do: (1) render a plain "X today"
/// row with no bar at all when there's no target, instead of implying a
/// target of zero; (2) stack the label above the value at accessibility
/// Dynamic Type sizes instead of squeezing both into one row, which is what
/// produced the "Calo-ries" mid-word wrap.
private struct NutritionMetricRow: View {
    let label: String
    let currentText: String
    let unitSuffix: String
    /// `nil` means this metric has no configured target — render a plain
    /// "current today" row with no bar, never "current / 0".
    let targetText: String?
    let fraction: Double?
    var status: LOStatus = .inProgress

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var safeFraction: Double {
        guard let fraction, fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }

    private var valueText: String {
        if let targetText {
            return "\(currentText)\(unitSuffix) / \(targetText)"
        }
        return "\(currentText)\(unitSuffix) today"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpacing.xs) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    labelText
                    valueTextView
                }
            } else {
                HStack {
                    labelText
                    Spacer()
                    valueTextView
                }
            }
            if targetText != nil {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.07))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [status.color, status.color.opacity(0.65)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: proxy.size.width * safeFraction)
                            .shadow(color: status.color.opacity(0.35), radius: 3, x: 0, y: 1)
                    }
                }
                .frame(height: 9)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var labelText: some View {
        Text(label)
            .font(.lifeOSBody.weight(.medium))
            .foregroundStyle(.primary)
    }

    private var valueTextView: some View {
        Text(valueText)
            .font(.lifeOSSecondary.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}
