import SwiftUI
import SwiftData

struct ProfileGoalsView: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedWeightUnit: WeightUnit
    @State private var targetWeight: Double

    init(profile: Profile) {
        self.profile = profile
        let unit = profile.weightUnit
        _selectedWeightUnit = State(initialValue: unit)
        _targetWeight = State(initialValue: profile.weightGoalKilograms.map(unit.displayValue) ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Display units") {
                    Picker("Weight", selection: $selectedWeightUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Body goal") {
                    HStack {
                        Text("Goal weight")
                        Spacer()
                        TextField("Optional", value: $targetWeight, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text(selectedWeightUnit.rawValue).foregroundStyle(.secondary)
                    }
                }

                Section("Daily nutrition goals") {
                    goalField("Calories", value: $profile.calorieGoal, unit: "kcal")
                    goalField("Protein", value: $profile.proteinGoalGrams, unit: "g")
                    goalField("Carbohydrates", value: $profile.carbohydrateGoalGrams, unit: "g")
                    goalField("Fat", value: $profile.fatGoalGrams, unit: "g")
                    goalField("Water", value: $profile.waterGoalMilliliters, unit: "ml")
                }

                Section {
                    Text("Sport and other Area targets are edited inside that Area. Targets are set by you, a parent, or a qualified coach. LifeOS tracks progress but does not prescribe medical or youth-training targets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("\(profile.name)'s Goals")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { saveAndDismiss() }
                }
            }
            .onChange(of: selectedWeightUnit) { oldUnit, newUnit in
                guard targetWeight > 0 else { return }
                targetWeight = newUnit.displayValue(kilograms: oldUnit.kilograms(from: targetWeight))
            }
        }
    }

    private func goalField(_ title: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func saveAndDismiss() {
        profile.weightUnit = selectedWeightUnit
        profile.weightGoalKilograms = targetWeight > 0 ? selectedWeightUnit.kilograms(from: targetWeight) : nil
        try? modelContext.save()
        dismiss()
    }
}
