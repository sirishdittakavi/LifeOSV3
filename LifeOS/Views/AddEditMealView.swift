//
//  AddEditMealView.swift
//  LifeOS
//
//  V1 locked decision (meal template scope correction): a meal is ONE
//  fixed, user-entered set of totals — Calories/Protein/Carbs/Fat — plus an
//  optional free-text description ("Coles Lamb Shank / Rice: 0.5 cup").
//  LifeOS never computes these from ingredients, never scales a serving,
//  and never converts units. Editable in place for normal user corrections
//  (NUTRITION_MODULE_DESIGN_V1.md §4a — not immutable-once-created).
//

import SwiftUI
import SwiftData

struct AddEditMealView: View {
    @Bindable var selection: SelectedProfile
    let mealType: MealType
    var existingMeal: MealEntry?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var details: String
    @State private var calories: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?

    @State private var showingTemplateNamePrompt = false
    @State private var templateName = ""
    @State private var showingDeleteConfirmation = false

    init(selection: SelectedProfile, mealType: MealType, existingMeal: MealEntry? = nil) {
        self.selection = selection
        self.mealType = mealType
        self.existingMeal = existingMeal
        _details = State(initialValue: existingMeal?.details ?? "")
        _calories = State(initialValue: existingMeal.flatMap { $0.totals.calories > 0 ? $0.totals.calories : nil })
        _protein = State(initialValue: existingMeal.flatMap { $0.totals.proteinG > 0 ? $0.totals.proteinG : nil })
        _carbs = State(initialValue: existingMeal.flatMap { $0.totals.carbsG > 0 ? $0.totals.carbsG : nil })
        _fat = State(initialValue: existingMeal.flatMap { $0.totals.fatG > 0 ? $0.totals.fatG : nil })
    }

    private var hasAnyValue: Bool {
        (calories ?? 0) > 0 || (protein ?? 0) > 0 || (carbs ?? 0) > 0 || (fat ?? 0) > 0
    }

    private var currentTotals: NutritionValue {
        NutritionValue(calories: calories ?? 0, proteinG: protein ?? 0, carbsG: carbs ?? 0, fatG: fat ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Optional — e.g. \"Coles Lamb Shank, Rice: 0.5 cup\"", text: $details, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    macroField("Calories", $calories, suffix: "kcal")
                    macroField("Protein", $protein, suffix: "g")
                    macroField("Carbs", $carbs, suffix: "g")
                    macroField("Fat", $fat, suffix: "g")
                } footer: {
                    Text("Enter this meal's totals directly — LifeOS doesn't calculate nutrition from ingredients.")
                }

                Section {
                    Button("Save as Template") { showingTemplateNamePrompt = true }
                        .disabled(!hasAnyValue)
                }

                if existingMeal != nil {
                    Section {
                        Button("Delete Meal", role: .destructive) { showingDeleteConfirmation = true }
                            .accessibilityIdentifier("nutrition.meal.delete.\(mealType.rawValue.lowercased())")
                    }
                }
            }
            .navigationTitle(existingMeal == nil ? "Add \(mealType.rawValue)" : "Edit \(mealType.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Meal", action: saveMeal).disabled(!hasAnyValue)
                }
            }
            .alert("Save as Template", isPresented: $showingTemplateNamePrompt) {
                TextField("Template name", text: $templateName)
                Button("Cancel", role: .cancel) { }
                Button("Save") { saveAsTemplate() }
            } message: {
                Text("This meal's details and totals will be saved for one-tap reuse.")
            }
            .confirmationDialog("Delete this meal?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Meal", role: .destructive, action: deleteMeal)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes it from today's totals and history. This can't be undone.")
            }
        }
    }

    private func macroField(_ title: String, _ value: Binding<Double?>, suffix: String) -> some View {
        HStack {
            Text(title).font(.lifeOSBody)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(suffix).font(.lifeOSSecondary).foregroundStyle(.secondary)
        }
    }

    private func saveMeal() {
        guard let profileID = selection.profile?.id else { return }
        let repository = SwiftDataNutritionRepository(context: modelContext)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)

        if let meal = existingMeal {
            meal.details = trimmedDetails
            meal.setTotals(currentTotals)
        } else {
            let meal = MealEntry(profileID: profileID, mealType: mealType, details: trimmedDetails)
            repository.insertMeal(meal, foodEntries: [])
            meal.setTotals(currentTotals)
        }

        if repository.save() { dismiss() }
    }

    private func deleteMeal() {
        guard let meal = existingMeal else { return }
        let repository = SwiftDataNutritionRepository(context: modelContext)
        do {
            try repository.deleteMeal(meal)
            if repository.save() { dismiss() }
        } catch {
            // Deletion failures here mean the persistent store itself is broken;
            // nothing meaningful to recover from at the form level.
        }
    }

    private func saveAsTemplate() {
        guard let profileID = selection.profile?.id else { return }
        let trimmedName = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let repository = SwiftDataNutritionRepository(context: modelContext)
        let template = MealTemplate(
            profileID: profileID, name: trimmedName, mealTypeDefault: mealType,
            details: details.trimmingCharacters(in: .whitespacesAndNewlines), totals: currentTotals
        )
        repository.insertTemplate(template, foodEntries: [])
        repository.save()
        templateName = ""
    }
}
