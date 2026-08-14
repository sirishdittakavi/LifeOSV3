//
//  NutritionTargetsView.swift
//  LifeOS
//
//  "Fix User-Defined Nutrition Targets": LifeOS never assumes or prescribes
//  a nutrition target. Every field here is optional and starts blank for a
//  new profile — no age/sex/height/weight/activity-level intake, no BMR
//  calculation, no recommended defaults. The user types the daily target
//  they personally want to track, or leaves a field blank to not track
//  that metric at all. Reached from the Nutrition Dashboard's existing
//  "More Nutrition options" menu — no new permanent toolbar icon.
//

import SwiftUI
import SwiftData

struct NutritionTargetsView: View {
    @Bindable var selection: SelectedProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allGoals: [NutritionGoal]

    @State private var protein: Double?
    @State private var calories: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    /// Displayed/edited in liters (the unit the rest of Nutrition shows
    /// water in); stored as NutritionGoal.waterTargetML, matching
    /// WaterEntry's canonical unit.
    @State private var waterLiters: Double?
    @State private var didLoad = false

    private var profileID: UUID? { selection.profile?.id }

    private var existingGoal: NutritionGoal? {
        guard let profileID else { return nil }
        return allGoals.first { $0.profileID == profileID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    targetField("Protein", value: $protein, unit: "g/day")
                    targetField("Calories", value: $calories, unit: "kcal/day")
                    targetField("Carbs", value: $carbs, unit: "g/day")
                    targetField("Fat", value: $fat, unit: "g/day")
                    targetField("Water", value: $waterLiters, unit: "L/day")
                } footer: {
                    Text("Every target is optional. Leave a field blank to not track a target for that metric — LifeOS never assumes a value for you.")
                }
            }
            .navigationTitle("Nutrition Targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    private func targetField(_ label: String, value: Binding<Double?>, unit: String) -> some View {
        HStack {
            Text(label)
                .font(.lifeOSBody)
            Spacer()
            TextField("Optional", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 70)
                .accessibilityIdentifier("nutrition.target.\(label.lowercased())")
            Text(unit)
                .font(.lifeOSSecondary)
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let goal = existingGoal else { return }
        protein = goal.proteinTargetG
        calories = goal.calorieTarget
        carbs = goal.carbsTargetG
        fat = goal.fatTargetG
        waterLiters = goal.waterTargetML.map { $0 / 1000 }
    }

    private func save() {
        guard let profileID else { dismiss(); return }
        let repository = SwiftDataNutritionRepository(context: modelContext)
        let goal = existingGoal ?? {
            let created = NutritionGoal(profileID: profileID)
            repository.insertGoal(created)
            return created
        }()

        goal.proteinTargetG = protein
        goal.calorieTarget = calories
        goal.carbsTargetG = carbs
        goal.fatTargetG = fat
        goal.waterTargetML = waterLiters.map { $0 * 1000 }
        goal.updatedAt = .now

        if repository.save() { dismiss() }
    }
}
