//
//  NutritionProgressView.swift
//  LifeOS
//
//  NUTRITION_MODULE_DESIGN_V1.md Screen 07. Habit/trend framing throughout
//  — single meaningful numbers, never a blended arbitrary score. "Your
//  Goal" rows use plain language (metric display names), never surfacing
//  linkedNutritionMetricID/linkedBodyMetricDefinitionID.
//

import SwiftUI
import SwiftData

struct NutritionProgressView: View {
    @Bindable var selection: SelectedProfile
    @Environment(\.dismiss) private var dismiss

    @Query private var meals: [MealEntry]
    @Query private var waterEntries: [WaterEntry]
    @Query private var nutritionGoals: [NutritionGoal]
    @Query private var templates: [MealTemplate]
    @Query private var bodyMetricDefinitions: [BodyMetricDefinition]
    @Query private var bodyMetricEntries: [BodyMetricEntry]
    @Query private var goals: [Goal]
    @Query private var resultMeasures: [ResultMeasure]

    private var profileID: UUID? { selection.profile?.id }
    private var goal: NutritionGoal? {
        guard let profileID else { return nil }
        return nutritionGoals.first { $0.profileID == profileID }
    }
    private var interval: DateInterval {
        DateInterval(start: Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now, end: .now)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LifeOSSpacing.lg) {
                    if let profileID {
                        statGrid(profileID)
                        if goal?.proteinTargetG != nil {
                            proteinTrendCard(profileID)
                        }
                        linkedGoalsSection(profileID)
                    } else {
                        ContentUnavailableView("Choose a Profile", systemImage: "person.crop.circle")
                    }
                }
                .padding(LifeOSSpacing.lg)
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func statGrid(_ profileID: UUID) -> some View {
        let protein = NutritionEngine.consistencyDays(profileID: profileID, interval: interval, metric: .protein, meals: meals, waterEntries: waterEntries, goal: goal)
        let water = NutritionEngine.consistencyDays(profileID: profileID, interval: interval, metric: .water, meals: meals, waterEntries: waterEntries, goal: goal)
        let weightDefinition = bodyMetricDefinitions.first { $0.profileID == profileID && $0.name == "Weight" }
        let weightTrend = weightDefinition.flatMap { BodyTrackingEngine.trend(definitionID: $0.id, entries: bodyMetricEntries, interval: interval) }
        let templateUseRate = templateConsistency(profileID)

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: LifeOSSpacing.md) {
            if let protein {
                LOMetricTile(title: "Protein target days", value: "\(protein.achieved)/\(protein.totalDays)", status: .focus, symbol: "bolt.fill")
                    .accessibilityIdentifier("progress.nutrition.protein")
            } else {
                LOMetricTile(title: "Protein target days", value: "—", caption: "No target set", status: .neutral, symbol: "bolt.fill")
                    .accessibilityIdentifier("progress.nutrition.protein")
            }
            if let weightTrend {
                let formattedTrend = weightTrend.formatted(.number.precision(.fractionLength(1)))
                let sign = weightTrend > 0 ? "+" : ""
                LOMetricTile(
                    title: "Weight trend",
                    value: "\(sign)\(formattedTrend)\(weightDefinition?.unit ?? "")",
                    status: weightTrend <= 0 ? .complete : .neutral, symbol: "scalemass.fill"
                )
                .accessibilityIdentifier("progress.body.weight")
            } else {
                LOMetricTile(title: "Weight trend", value: "—", caption: "Not enough entries yet", status: .neutral, symbol: "scalemass.fill")
                    .accessibilityIdentifier("progress.body.weight")
            }
            if let water {
                LOMetricTile(title: "Water target days", value: "\(water.achieved)/\(water.totalDays)", status: .complete, symbol: "drop.fill")
            } else {
                LOMetricTile(title: "Water target days", value: "—", caption: "No target set", status: .neutral, symbol: "drop.fill")
            }
            LOMetricTile(title: "Template consistency", value: templateUseRate, status: .inProgress, symbol: "star.fill")
        }
    }

    private func templateConsistency(_ profileID: UUID) -> String {
        let recentMeals = meals.filter { $0.profileID == profileID && interval.contains($0.recordedAt) }
        guard !recentMeals.isEmpty else { return "No meals yet" }
        let fromTemplate = recentMeals.filter { $0.sourceTemplateID != nil }.count
        let percent = Int((Double(fromTemplate) / Double(recentMeals.count) * 100).rounded())
        return "\(percent)%"
    }

    private func proteinTrendCard(_ profileID: UUID) -> some View {
        var day = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .now
        var bars: [(day: Date, fraction: Double)] = []
        for _ in 0..<7 {
            let progress = NutritionEngine.targetProgress(profileID: profileID, date: day, meals: meals, waterEntries: waterEntries, goal: goal)
            bars.append((day, progress.proteinFraction ?? 0))
            day = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        }

        return VStack(alignment: .leading, spacing: LifeOSSpacing.sm) {
            LOSectionHeader(title: "Protein — daily target hit")
            LOCard {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(bars, id: \.day) { bar in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(bar.fraction >= 1 ? Color.lifeOSFocus : Color.lifeOSFocus.opacity(0.25))
                            .frame(height: max(6, 56 * bar.fraction))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 56, alignment: .bottom)
            }
        }
    }

    private func linkedGoalsSection(_ profileID: UUID) -> some View {
        let linkedMeasures = resultMeasures.filter {
            $0.isActive && $0.goal?.profile?.id == profileID
                && ($0.linkedNutritionMetric != nil || $0.linkedBodyMetricDefinitionID != nil)
        }

        return Group {
            if !linkedMeasures.isEmpty {
                VStack(alignment: .leading, spacing: LifeOSSpacing.sm) {
                    LOSectionHeader(title: "Your Goals")
                    LOCard {
                        VStack(spacing: 0) {
                            ForEach(linkedMeasures) { measure in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(measure.goal?.name ?? measure.name).font(.lifeOSCardTitle)
                                        Text(plainLanguageLabel(for: measure)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                                if measure.id != linkedMeasures.last?.id { Divider() }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Plain language only — never the raw linkedNutritionMetricID/
    /// linkedBodyMetricDefinitionID field names.
    private func plainLanguageLabel(for measure: ResultMeasure) -> String {
        if let metric = measure.linkedNutritionMetric {
            return "Tracks \(metric.displayName)"
        }
        if let definitionID = measure.linkedBodyMetricDefinitionID,
           let definition = bodyMetricDefinitions.first(where: { $0.id == definitionID }) {
            return "Tracks \(definition.name)"
        }
        return ""
    }
}
