//
//  MealLoggingView.swift
//  LifeOS
//
//  NUTRITION_MODULE_DESIGN_V1.md Screen 03. Priority order per the brief:
//  Templates first (the one-tap happy path), then Recent Meals, then
//  Manual Entry, then Quick Macros. Reusing a template should take the
//  "Nutrition → Breakfast → My Protein Breakfast → Confirm" path with no
//  re-entry of details already saved.
//
//  V1 locked decision (meal template scope correction): templates and
//  meals carry one fixed, user-entered set of totals + a free-text
//  description — never a per-food breakdown, never calculated, never
//  scaled by serving size.
//

import SwiftUI
import SwiftData

struct MealLoggingView: View {
    @Bindable var selection: SelectedProfile
    let mealType: MealType

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allMeals: [MealEntry]
    @Query private var allTemplates: [MealTemplate]

    private enum SourceTab: String, CaseIterable, Identifiable {
        case templates = "My Templates"
        case recent = "Recent Meals"
        case manual = "Manual entry"
        case quickMacros = "Quick macros"
        var id: String { rawValue }
    }

    @State private var selectedTab: SourceTab = .templates
    @State private var showingManualEntry = false
    @State private var showingEditMeal: MealEntry?
    @State private var quickName = ""
    @State private var quickCalories: Double?
    @State private var quickProtein: Double?
    @State private var quickCarbs: Double?
    @State private var quickFat: Double?
    @State private var showingQuickTemplatePrompt = false
    @State private var quickTemplateName = ""

    private var profileID: UUID? { selection.profile?.id }

    /// Only templates for this meal type (or with no specific meal type) —
    /// a breakfast template must not be offered as "My Templates" while
    /// logging a Snack. Templates for other meal types are still reachable
    /// by switching meal type, not hidden from the app entirely.
    private var templates: [MealTemplate] {
        guard let profileID else { return [] }
        return NutritionEngine.sortedByRelevance(
            allTemplates.filter { $0.profileID == profileID && ($0.mealTypeDefault == nil || $0.mealTypeDefault == mealType) }
        )
    }

    /// Distinct past meals (by description text, or by totals when there's
    /// no description) for this meal type, excluding today — a
    /// lower-commitment alternative to a saved Template for one-off repeats.
    private var recentMeals: [MealEntry] {
        guard let profileID else { return [] }
        let past = allMeals.filter {
            $0.profileID == profileID && $0.mealType == mealType && !Calendar.current.isDateInToday($0.recordedAt)
        }
        .sorted { $0.recordedAt > $1.recordedAt }
        var seenSignatures = Set<String>()
        var result: [MealEntry] = []
        for meal in past {
            let trimmedDetails = meal.details.trimmingCharacters(in: .whitespacesAndNewlines)
            let signature = trimmedDetails.isEmpty
                ? "\(Int(meal.totals.calories))|\(Int(meal.totals.proteinG))|\(Int(meal.totals.carbsG))|\(Int(meal.totals.fatG))"
                : trimmedDetails
            guard !seenSignatures.contains(signature) else { continue }
            seenSignatures.insert(signature)
            result.append(meal)
            if result.count == 5 { break }
        }
        return result
    }

    private var todaysMeal: MealEntry? {
        guard let profileID else { return nil }
        return allMeals.first {
            $0.profileID == profileID && $0.mealType == mealType && Calendar.current.isDateInToday($0.recordedAt)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LifeOSSpacing.lg) {
                    tabRow

                    switch selectedTab {
                    case .templates: templatesSection
                    case .recent: recentSection
                    case .manual: manualSection
                    case .quickMacros: quickMacrosSection
                    }

                    if let todaysMeal {
                        loggedSoFarSection(todaysMeal)
                    }
                }
                .padding(LifeOSSpacing.lg)
            }
            .navigationTitle(mealType.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showingManualEntry) {
                AddEditMealView(selection: selection, mealType: mealType, existingMeal: todaysMeal)
            }
            .sheet(item: $showingEditMeal) { meal in
                AddEditMealView(selection: selection, mealType: mealType, existingMeal: meal)
            }
            .alert("Save as Template", isPresented: $showingQuickTemplatePrompt) {
                TextField("Template name", text: $quickTemplateName)
                Button("Cancel", role: .cancel) { }
                Button("Save", action: saveQuickMacroAsTemplate)
            } message: {
                Text("This meal's details and totals will be saved for one-tap reuse.")
            }
        }
    }

    private var tabRow: some View {
        // Horizontally scrollable so these four labels never wrap mid-word
        // inside a chip at standard/larger Dynamic Type sizes.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LifeOSSpacing.sm) {
                ForEach(SourceTab.allCases) { tab in
                    LOChip(title: tab.rawValue, isSelected: selectedTab == tab) { selectedTab = tab }
                        .fixedSize()
                }
            }
        }
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: LifeOSSpacing.sm) {
            if templates.isEmpty {
                Text("No templates yet. Save a meal as a Template after logging it.")
                    .font(.lifeOSSecondary)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(templates) { template in
                    templateRow(template)
                }
            }
        }
    }

    private func templateRow(_ template: MealTemplate) -> some View {
        Button { useTemplate(template) } label: {
            LOCard {
                HStack(spacing: LifeOSSpacing.md) {
                    LOIconBadge(symbol: template.isFavorite ? "star.fill" : "fork.knife", tint: .lifeOSFocus)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name)
                            .font(.lifeOSCardTitle)
                            .foregroundStyle(.primary)
                        if !template.details.isEmpty {
                            Text(template.details)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            macroPill("P \(Int(template.totals.proteinG))g", .lifeOSFocus)
                            macroPill("C \(Int(template.totals.carbsG))g", .lifeOSWatch)
                            macroPill("\(Int(template.totals.calories)) kcal", .lifeOSRecovery)
                        }
                    }
                    Spacer()
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func macroPill(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: LifeOSSpacing.sm) {
            if recentMeals.isEmpty {
                Text("No previous \(mealType.rawValue.lowercased())s logged yet.")
                    .font(.lifeOSSecondary)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentMeals) { meal in
                    Button { useRecentMeal(meal) } label: {
                        LOCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meal.details.isEmpty ? "\(mealType.rawValue)" : meal.details)
                                        .font(.lifeOSCardTitle)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("\(Int(meal.totals.calories)) kcal")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var manualSection: some View {
        LOPrimaryButton(title: todaysMeal == nil ? "Add \(mealType.rawValue)" : "Edit \(mealType.rawValue)", symbol: "plus") {
            showingManualEntry = true
        }
    }

    private var quickMacrosSection: some View {
        LOCard {
            VStack(alignment: .leading, spacing: LifeOSSpacing.md) {
                Text("Enter this meal's totals directly — no ingredient breakdown needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Name").font(.lifeOSBody)
                    Spacer()
                    TextField("Optional, e.g. \"Something I ate\"", text: $quickName)
                        .multilineTextAlignment(.trailing)
                }
                quickField("Calories", $quickCalories)
                quickField("Protein (g)", $quickProtein)
                quickField("Carbs (g)", $quickCarbs)
                quickField("Fat (g)", $quickFat)
                HStack {
                    LOPrimaryButton(
                        title: "Add",
                        isDisabled: (quickCalories ?? 0) <= 0 && (quickProtein ?? 0) <= 0
                            && (quickCarbs ?? 0) <= 0 && (quickFat ?? 0) <= 0
                    ) {
                        addQuickMacros()
                    }
                    Button("Save as Template") { showingQuickTemplatePrompt = true }
                        .disabled((quickCalories ?? 0) <= 0 && (quickProtein ?? 0) <= 0 && (quickCarbs ?? 0) <= 0 && (quickFat ?? 0) <= 0)
                }
            }
        }
    }

    private func quickField(_ title: String, _ value: Binding<Double?>) -> some View {
        HStack {
            Text(title).font(.lifeOSBody)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }

    private func loggedSoFarSection(_ meal: MealEntry) -> some View {
        VStack(alignment: .leading, spacing: LifeOSSpacing.sm) {
            LOSectionHeader(title: "Logged so far")
            Button { showingEditMeal = meal } label: {
                LOCard {
                    VStack(alignment: .leading, spacing: 4) {
                        if !meal.details.isEmpty {
                            Text(meal.details).font(.lifeOSBody)
                        }
                        HStack(spacing: 6) {
                            macroPill("P \(Int(meal.totals.proteinG))g", .lifeOSFocus)
                            macroPill("C \(Int(meal.totals.carbsG))g", .lifeOSWatch)
                            macroPill("\(Int(meal.totals.calories)) kcal", .lifeOSRecovery)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private var quickTotals: NutritionValue {
        NutritionValue(calories: quickCalories ?? 0, proteinG: quickProtein ?? 0, carbsG: quickCarbs ?? 0, fatG: quickFat ?? 0)
    }

    private func useTemplate(_ template: MealTemplate) {
        guard let profileID else { return }
        let repository = SwiftDataNutritionRepository(context: modelContext)
        let meal = MealEntry(
            profileID: profileID, mealType: mealType,
            sourceTemplateID: template.id, sourceTemplateNameSnapshot: template.name,
            details: template.details
        )
        repository.insertMeal(meal, foodEntries: [])
        meal.setTotals(template.totals)
        template.recordUse()
        if repository.save() { dismiss() }
    }

    private func useRecentMeal(_ source: MealEntry) {
        guard let profileID else { return }
        let repository = SwiftDataNutritionRepository(context: modelContext)
        let meal = MealEntry(profileID: profileID, mealType: mealType, details: source.details)
        repository.insertMeal(meal, foodEntries: [])
        meal.setTotals(source.totals)
        if repository.save() { dismiss() }
    }

    private func addQuickMacros() {
        guard let profileID else { return }
        let repository = SwiftDataNutritionRepository(context: modelContext)
        let trimmedName = quickName.trimmingCharacters(in: .whitespacesAndNewlines)

        if let meal = todaysMeal {
            if !trimmedName.isEmpty { meal.details = trimmedName }
            meal.setTotals(NutritionValue.sum([meal.totals, quickTotals]))
        } else {
            let meal = MealEntry(profileID: profileID, mealType: mealType, details: trimmedName)
            repository.insertMeal(meal, foodEntries: [])
            meal.setTotals(quickTotals)
        }

        if repository.save() {
            quickName = ""
            quickCalories = nil; quickProtein = nil; quickCarbs = nil; quickFat = nil
            dismiss()
        }
    }

    private func saveQuickMacroAsTemplate() {
        guard let profileID else { return }
        let trimmedTemplateName = quickTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTemplateName.isEmpty else { return }

        let repository = SwiftDataNutritionRepository(context: modelContext)
        let template = MealTemplate(
            profileID: profileID, name: trimmedTemplateName, mealTypeDefault: mealType,
            details: quickName.trimmingCharacters(in: .whitespacesAndNewlines), totals: quickTotals
        )
        repository.insertTemplate(template, foodEntries: [])
        repository.save()
        quickTemplateName = ""
    }
}
