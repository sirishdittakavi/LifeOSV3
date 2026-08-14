//
//  MealTemplatesView.swift
//  LifeOS
//
//  NUTRITION_MODULE_DESIGN_V1.md Screen 05. Core v1 feature per the brief:
//  create/use/edit/duplicate/delete/favorite, with usage metadata (times
//  used, last used) and a Favorites section pinned above the relevance-
//  sorted rest.
//
//  V1 locked decision (meal template scope correction): a template is ONE
//  fixed set of user-entered totals + a free-text description — not a
//  collection of foods. A different portion size is simply a different,
//  separate template; LifeOS never scales or derives one from another.
//  Editing a template later must not rewrite old MealEntry history —
//  templates only ever seed a fresh, independent snapshot of totals/details
//  when used (see MealLoggingView.useTemplate).
//

import SwiftUI
import SwiftData

struct MealTemplatesView: View {
    @Bindable var selection: SelectedProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allTemplates: [MealTemplate]

    @State private var editingTemplate: MealTemplate?
    @State private var showingNewTemplate = false

    private var profileID: UUID? { selection.profile?.id }

    private var templates: [MealTemplate] {
        guard let profileID else { return [] }
        return allTemplates.filter { $0.profileID == profileID }
    }

    private var favorites: [MealTemplate] { NutritionEngine.sortedByRelevance(templates.filter(\.isFavorite)) }
    private var others: [MealTemplate] { NutritionEngine.sortedByRelevance(templates.filter { !$0.isFavorite }) }

    var body: some View {
        NavigationStack {
            List {
                if templates.isEmpty {
                    ContentUnavailableView("No Templates Yet", systemImage: "star", description: Text("Save a meal as a Template after logging it."))
                } else {
                    if !favorites.isEmpty {
                        Section("Favorites") {
                            ForEach(favorites) { template in row(for: template) }
                        }
                    }
                    Section(favorites.isEmpty ? "Templates" : "All templates") {
                        ForEach(others) { template in row(for: template) }
                    }
                }
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { showingNewTemplate = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editingTemplate) { template in
                EditMealTemplateView(template: template)
            }
            .sheet(isPresented: $showingNewTemplate) {
                if let profileID {
                    EditMealTemplateView(template: nil, profileID: profileID)
                }
            }
        }
    }

    private func row(for template: MealTemplate) -> some View {
        Button { editingTemplate = template } label: {
            HStack(spacing: LifeOSSpacing.md) {
                Button {
                    template.isFavorite.toggle()
                    modelContext.saveOrReport()
                } label: {
                    Image(systemName: template.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(template.isFavorite ? Color.lifeOSWatch : Color.secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name).font(.lifeOSCardTitle).foregroundStyle(.primary)
                    Text(usageCaption(template))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text("P \(Int(template.totals.proteinG))g")
                        Text("C \(Int(template.totals.carbsG))g")
                        Text("\(Int(template.totals.calories)) kcal")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(template) } label: { Label("Delete", systemImage: "trash") }
            Button { duplicate(template) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                .tint(.blue)
            Button { editingTemplate = template } label: { Label("Edit", systemImage: "pencil") }
                .tint(.orange)
        }
    }

    private func usageCaption(_ template: MealTemplate) -> String {
        guard template.useCount > 0, let lastUsedAt = template.lastUsedAt else { return "Not used yet" }
        return "Used \(template.useCount)× · last \(lastUsedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private func duplicate(_ template: MealTemplate) {
        guard let profileID else { return }
        let repository = SwiftDataNutritionRepository(context: modelContext)
        let copy = MealTemplate(
            profileID: profileID, name: "\(template.name) Copy", mealTypeDefault: template.mealTypeDefault,
            details: template.details, totals: template.totals
        )
        repository.insertTemplate(copy, foodEntries: [])
        repository.save()
    }

    private func delete(_ template: MealTemplate) {
        let repository = SwiftDataNutritionRepository(context: modelContext)
        try? repository.deleteTemplate(template)
        repository.save()
    }
}

/// Shared create/edit form for a MealTemplate — name, description, and
/// fixed totals. Renaming or editing a template here never touches any
/// MealEntry that was previously created from it; only
/// sourceTemplateNameSnapshot on those historical entries stays as it was
/// at creation time, and their totals/details are their own independent
/// copy, not a live reference to the template.
private struct EditMealTemplateView: View {
    var template: MealTemplate?
    var profileID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var details: String
    @State private var calories: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?

    init(template: MealTemplate?, profileID: UUID? = nil) {
        self.template = template
        self.profileID = profileID
        _name = State(initialValue: template?.name ?? "")
        _details = State(initialValue: template?.details ?? "")
        _calories = State(initialValue: template.flatMap { $0.totals.calories > 0 ? $0.totals.calories : nil })
        _protein = State(initialValue: template.flatMap { $0.totals.proteinG > 0 ? $0.totals.proteinG : nil })
        _carbs = State(initialValue: template.flatMap { $0.totals.carbsG > 0 ? $0.totals.carbsG : nil })
        _fat = State(initialValue: template.flatMap { $0.totals.fatG > 0 ? $0.totals.fatG : nil })
    }

    private var currentTotals: NutritionValue {
        NutritionValue(calories: calories ?? 0, proteinG: protein ?? 0, carbsG: carbs ?? 0, fatG: fat ?? 0)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Template name, e.g. \"Lamb Shank + 0.5 cup rice\"", text: $name)
                }
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
                    Text("This template's totals are fixed — a different portion size should be its own separate template.")
                }
            }
            .navigationTitle(template == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
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

    private func save() {
        let repository = SwiftDataNutritionRepository(context: modelContext)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)

        if let template {
            template.name = trimmedName
            template.details = trimmedDetails
            template.totals = currentTotals
            template.updatedAt = .now
        } else if let profileID {
            let newTemplate = MealTemplate(
                profileID: profileID, name: trimmedName, details: trimmedDetails, totals: currentTotals
            )
            repository.insertTemplate(newTemplate, foodEntries: [])
        }

        if repository.save() { dismiss() }
    }
}
