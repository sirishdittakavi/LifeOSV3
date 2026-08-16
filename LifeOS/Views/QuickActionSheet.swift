//
//  QuickActionSheet.swift
//  LifeOS
//
//  NUTRITION_MODULE_DESIGN_V1.md Screen 02 — a single entry point for the
//  three fastest Nutrition actions (Log Meal / Water / Weight) instead of
//  navigating to three separate screens first. Kept intentionally simple
//  per the brief: no complicated workflows.
//

import SwiftUI
import SwiftData

struct QuickActionSheet: View {
    @Bindable var selection: SelectedProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Called when "Log Meal" is chosen — the caller presents
    /// MealLoggingView for the returned meal type, matching the Meal
    /// checklist's own tap behavior.
    var onLogMeal: (MealType) -> Void

    @State private var showingMealTypePicker = false
    @State private var showingWater = false
    @State private var showingWeight = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LOCard {
                    VStack(spacing: 0) {
                        quickRow(title: "Log Meal", symbol: "fork.knife", tint: .lifeOSFocus, identifier: "nutrition.quickAction.logMeal") {
                            showingMealTypePicker = true
                        }
                        Divider()
                        quickRow(title: "Water", symbol: "drop.fill", tint: .lifeOSOnTrack, identifier: "nutrition.quickAction.water") {
                            showingWater = true
                        }
                        Divider()
                        quickRow(title: "Weight", symbol: "scalemass.fill", tint: .lifeOSRecovery, identifier: "nutrition.quickAction.weight") {
                            showingWeight = true
                        }
                    }
                }
                .padding(LifeOSSpacing.lg)
            }
            .navigationTitle("Log something")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .confirmationDialog("Which meal?", isPresented: $showingMealTypePicker, titleVisibility: .visible) {
                ForEach(MealType.allCases) { mealType in
                    Button(mealType.rawValue) { onLogMeal(mealType) }
                }
            }
            .sheet(isPresented: $showingWater) {
                WaterQuickAddSheet(selection: selection)
            }
            .sheet(isPresented: $showingWeight) {
                WeightQuickAddSheet(selection: selection)
            }
        }
    }

    private func quickRow(title: String, symbol: String, tint: Color, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: LifeOSSpacing.md) {
                LOIconBadge(symbol: symbol, tint: tint, diameter: 40)
                Text(title)
                    .font(.lifeOSCardTitle)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, LifeOSSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// "+250 ml / +500 ml / custom" — fast by design, no other fields.
private struct WaterQuickAddSheet: View {
    @Bindable var selection: SelectedProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allWaterEntries: [WaterEntry]
    @State private var customAmount: Double?

    private var todaysEntries: [WaterEntry] {
        guard let profileID = selection.profile?.id else { return [] }
        return allWaterEntries
            .filter { $0.profileID == profileID && Calendar.current.isDateInToday($0.recordedAt) }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: LifeOSSpacing.lg) {
                HStack(spacing: LifeOSSpacing.md) {
                    quickAmountButton(250)
                    quickAmountButton(500)
                }
                HStack {
                    TextField("Custom amount (mL)", value: $customAmount, format: .number)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    LOPrimaryButton(title: "Add", isDisabled: (customAmount ?? 0) <= 0) {
                        if let customAmount, customAmount > 0 { add(customAmount) }
                    }
                }
                if !todaysEntries.isEmpty {
                    loggedTodaySection
                }
                Spacer()
            }
            .padding(LifeOSSpacing.lg)
            .navigationTitle("Water")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private var loggedTodaySection: some View {
        VStack(alignment: .leading, spacing: LifeOSSpacing.sm) {
            LOSectionHeader(title: "Logged today")
            List {
                ForEach(todaysEntries) { entry in
                    HStack {
                        Text("\(Int(entry.amountML)) mL")
                            .font(.lifeOSBody)
                        Spacer()
                        Text(entry.recordedAt, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deleteEntries)
            }
            .listStyle(.plain)
            .frame(height: min(CGFloat(todaysEntries.count) * 44 + 8, 176))
        }
    }

    private func quickAmountButton(_ amount: Double) -> some View {
        Button { add(amount) } label: {
            Text("+\(Int(amount)) mL")
                .font(.lifeOSValueEmphasis)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LifeOSSpacing.lg)
        }
        .buttonStyle(LifeOSSecondaryButtonStyle())
        .accessibilityIdentifier("nutrition.water.add\(Int(amount))")
    }

    private func add(_ amount: Double) {
        guard let profileID = selection.profile?.id else { return }
        let entry = WaterEntry(profileID: profileID, amountML: amount)
        let repository = SwiftDataNutritionRepository(context: modelContext)
        repository.insertWaterEntry(entry)
        repository.save()
        customAmount = nil
    }

    private func deleteEntries(at offsets: IndexSet) {
        let repository = SwiftDataNutritionRepository(context: modelContext)
        for index in offsets { repository.deleteWaterEntry(todaysEntries[index]) }
        repository.save()
    }
}

/// "Weight / 78.5 kg / Save" — the single required field, matching
/// NUTRITION_MODULE_DESIGN_V1.md's "extremely simple" requirement.
private struct WeightQuickAddSheet: View {
    @Bindable var selection: SelectedProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var definitions: [BodyMetricDefinition]
    @State private var value: Double?

    private var weightDefinition: BodyMetricDefinition? {
        guard let profileID = selection.profile?.id else { return nil }
        return definitions.first { $0.profileID == profileID && $0.name == "Weight" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Weight (\(weightDefinition?.unit ?? "kg"))", value: $value, format: .number)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled((value ?? 0) <= 0)
                }
            }
        }
    }

    private func save() {
        guard let profileID = selection.profile?.id, let value, value > 0 else { return }
        let repository = SwiftDataBodyTrackingRepository(context: modelContext)
        repository.seedDefaultDefinitionsIfNeeded(profileID: profileID, existingDefinitions: definitions)
        let definition = weightDefinition ?? BodyMetricDefinition(profileID: profileID, name: "Weight", unit: "kg", isSystemDefault: true)
        if weightDefinition == nil { repository.insertDefinition(definition) }
        let entry = BodyMetricEntry(
            profileID: profileID, bodyMetricDefinition: definition,
            nameSnapshot: definition.name, unitSnapshot: definition.unit, value: value
        )
        repository.insertEntry(entry)
        if repository.save() { dismiss() }
    }
}
