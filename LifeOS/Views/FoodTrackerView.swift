import SwiftUI
import SwiftData

struct FoodTrackerView: View {
    @Bindable var selection: SelectedProfile
    @Query(sort: \FoodEntry.date, order: .reverse) private var entries: [FoodEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    @State private var showingAddFood = false
    @State private var showingMealPlan = false
    @State private var showingWeight = false
    @State private var showingGoals = false
    @State private var selectedMeal: MealType?

    private var actualEntries: [FoodEntry] {
        guard let profileID = selection.profile?.id else { return [] }
        return entries.filter { $0.profile?.id == profileID && !$0.isMealPlanItem }
    }

    private var todayEntries: [FoodEntry] {
        actualEntries.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var totals: NutritionTotals { NutritionTotals(entries: todayEntries) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LifeOSSpacing.lg) {
                    if let profile = selection.profile {
                        NutritionHero(totals: totals, profile: profile) {
                            showingAddFood = true
                        }
                        macroGrid(profile: profile)
                        mealSection
                        weightSection(profile: profile)
                    } else {
                        ContentUnavailableView("Choose a Profile", systemImage: "person.crop.circle")
                    }
                }
                .padding(LifeOSSpacing.lg)
            }
            .background(NutritionBackground())
            .navigationTitle("Nutrition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfilePicker(selection: selection) }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingMealPlan = true } label: {
                        Image(systemName: "calendar.badge.clock")
                    }
                    .accessibilityLabel("Weekly Meal Plan")
                    .accessibilityIdentifier("nutrition.weeklyPlan")
                    Button { showingGoals = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Nutrition targets")
                }
            }
            .sheet(isPresented: $showingAddFood) {
                if let profile = selection.profile { AddFoodEntryView(profile: profile) }
            }
            .sheet(item: $selectedMeal) { meal in
                if let profile = selection.profile {
                    MealDetailView(profile: profile, meal: meal, entries: todayEntries)
                }
            }
            .sheet(isPresented: $showingMealPlan) {
                if let profile = selection.profile { WeeklyMealPlanView(profile: profile) }
            }
            .sheet(isPresented: $showingWeight) { WeightTrackerView(selection: selection) }
            .sheet(isPresented: $showingGoals) {
                if let profile = selection.profile { ProfileGoalsView(profile: profile) }
            }
        }
    }

    private func macroGrid(profile: Profile) -> some View {
        HStack(spacing: 9) {
            NutritionMacroTile(title: "Protein", value: totals.protein, target: profile.proteinGoalGrams, unit: "g", tint: .green)
            NutritionMacroTile(title: "Carbs", value: totals.carbs, target: profile.carbohydrateGoalGrams, unit: "g", tint: .blue)
            NutritionMacroTile(title: "Fat", value: totals.fat, target: profile.fatGoalGrams, unit: "g", tint: .purple)
        }
    }

    private var mealSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TODAY'S MEALS").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Spacer()
                Button("Weekly plan") { showingMealPlan = true }.font(.caption.weight(.semibold))
            }
            VStack(spacing: 0) {
                ForEach([MealType.breakfast, .lunch, .snack, .dinner]) { meal in
                    Button { selectedMeal = meal } label: {
                        NutritionMealRow(meal: meal, entries: todayEntries.filter { $0.mealType == meal })
                    }
                    .buttonStyle(.plain)
                    if meal != .dinner { Divider().padding(.leading, 54) }
                }
            }
            .padding(.horizontal, 14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: LifeOSRadius.lg, style: .continuous))
        }
    }

    private func weightSection(profile: Profile) -> some View {
        let latest = weights.first { $0.profile?.id == profile.id }
        let display = latest.map {
            "\(profile.weightUnit.displayValue(kilograms: $0.kilograms).formatted(.number.precision(.fractionLength(1)))) \(profile.weightUnit.rawValue)"
        } ?? "Not logged"
        return VStack(alignment: .leading, spacing: 9) {
            Text("WEIGHT").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Button { showingWeight = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(display).font(.title3.weight(.bold)).foregroundStyle(.primary)
                        Text(latest == nil ? "Log your first weight" : "View daily, weekly and monthly history")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("Log", systemImage: "plus").font(.subheadline.weight(.semibold))
                }
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: LifeOSRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct NutritionTotals {
    var calories = 0.0
    var protein = 0.0
    var carbs = 0.0
    var fat = 0.0
    var water = 0.0

    init(entries: [FoodEntry]) {
        for entry in entries {
            calories += entry.calories
            protein += entry.proteinGrams
            carbs += entry.carbohydrateGrams
            fat += entry.fatGrams
            water += entry.waterMilliliters
        }
    }
}

private struct NutritionHero: View {
    let totals: NutritionTotals
    let profile: Profile
    let addFood: () -> Void

    private var fraction: Double {
        guard profile.calorieGoal > 0 else { return 0 }
        return min(max(totals.calories / profile.calorieGoal, 0), 1)
    }

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                SignatureProgressRing(fraction: fraction, gradient: ImprovementPillar.nutrition.gradient, lineWidth: 10, diameter: 108)
                VStack(spacing: 1) {
                    Text("\(Int(totals.calories))").font(.title2.weight(.bold).monospacedDigit())
                    Text("of \(Int(profile.calorieGoal)) kcal").font(.caption2).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("\(max(Int(profile.calorieGoal - totals.calories), 0)) kcal left")
                    .font(.title3.weight(.bold))
                Text("Actual intake today").font(.caption).foregroundStyle(.secondary)
                Button(action: addFood) { Label("Add food", systemImage: "plus.circle.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(LifeOSPrimaryButtonStyle())
                    .accessibilityIdentifier("nutrition.addFood")
            }
        }
        .lifeOSGlassCard(tint: .green, cornerRadius: LifeOSRadius.xl)
    }
}

private struct NutritionMacroTile: View {
    let title: String
    let value: Double
    let target: Double
    let unit: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(Int(value))/\(Int(target))\(unit)")
                .font(.subheadline.weight(.bold).monospacedDigit()).minimumScaleFactor(0.7).lineLimit(1)
            ProgressView(value: target > 0 ? min(value / target, 1) : 0).tint(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: LifeOSRadius.md, style: .continuous))
    }
}

private struct NutritionMealRow: View {
    let meal: MealType
    let entries: [FoodEntry]

    private var calories: Int { Int(entries.reduce(0) { $0 + $1.calories }) }
    private var symbol: String {
        switch meal {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.fill"
        case .snack: return "carrot.fill"
        case .drink: return "drop.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.green).frame(width: 38, height: 38).background(.green.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(meal.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(entries.isEmpty ? "Not logged" : entries.map(\.name).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(entries.isEmpty ? "+" : "\(calories) kcal").font(.caption.weight(.semibold)).foregroundStyle(entries.isEmpty ? .blue : .secondary)
        }
        .frame(minHeight: 58)
    }
}

private struct NutritionBackground: View {
    var body: some View {
        LinearGradient(colors: [Color.green.opacity(0.10), Color(.systemGroupedBackground), Color.blue.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
    }
}

private struct MealDetailView: View {
    let profile: Profile
    let meal: MealType
    let entries: [FoodEntry]
    @Environment(\.dismiss) private var dismiss
    @State private var showingAdd = false
    @State private var editingEntry: FoodEntry?

    var body: some View {
        NavigationStack {
            List {
                if entries.filter({ $0.mealType == meal }).isEmpty {
                    ContentUnavailableView("Nothing Logged", systemImage: "fork.knife", description: Text("Add what you actually ate."))
                } else {
                    ForEach(entries.filter { $0.mealType == meal }) { entry in
                        Button { editingEntry = entry } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(entry.name).font(.headline); Spacer(); Text("\(Int(entry.calories)) kcal") }
                                Text("P \(Int(entry.proteinGrams))g · C \(Int(entry.carbohydrateGrams))g · F \(Int(entry.fatGrams))g")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                Button { showingAdd = true } label: { Label("Add to \(meal.rawValue)", systemImage: "plus.circle.fill") }
            }
            .navigationTitle(meal.rawValue)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showingAdd) { AddFoodEntryView(profile: profile, initialMeal: meal) }
            .sheet(item: $editingEntry) { EditFoodEntryView(entry: $0) }
        }
    }
}

private struct AddFoodEntryView: View {
    let profile: Profile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var mealType: MealType
    @State private var name = ""
    @State private var servings = 1.0
    @State private var calories = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0
    @State private var water = 0.0
    @State private var note = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            calories > 0 || protein > 0 || carbs > 0 || fat > 0 || water > 0
    }

    init(profile: Profile, initialMeal: MealType = .breakfast, initialDate: Date = .now) {
        self.profile = profile
        _date = State(initialValue: initialDate)
        _mealType = State(initialValue: initialMeal)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    Picker("Type", selection: $mealType) { ForEach(MealType.allCases) { Text($0.rawValue).tag($0) } }
                    TextField("Food or meal (optional)", text: $name)
                    Stepper("Servings: \(servings.formatted(.number.precision(.fractionLength(0...2))))", value: $servings, in: 0.25...20, step: 0.25)
                    DatePicker("Time", selection: $date)
                }
                Section("Nutrition") {
                    nutritionField("Calories", value: $calories, unit: "kcal")
                    nutritionField("Protein", value: $protein, unit: "g")
                    nutritionField("Carbohydrates", value: $carbs, unit: "g")
                    nutritionField("Fat", value: $fat, unit: "g")
                    nutritionField("Water", value: $water, unit: "ml")
                }
                Section("Notes") { TextField("Optional", text: $note, axis: .vertical) }
            }
            .navigationTitle("Add Food")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add", action: save).disabled(!canSave) }
            }
        }
    }

    private func nutritionField(_ title: String, value: Binding<Double>, unit: String) -> some View {
        LabeledContent(title) {
            HStack { TextField("0", value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 85); Text(unit).foregroundStyle(.secondary) }
        }
    }

    private func save() {
        guard canSave else { return }
        let enteredName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let entryName = enteredName.isEmpty ? mealType.rawValue : enteredName
        let entry = FoodEntry(profile: profile, date: date, mealType: mealType, name: entryName, calories: calories, proteinGrams: protein, carbohydrateGrams: carbs, fatGrams: fat, waterMilliliters: water, note: note, nutritionSource: "Manual", servings: servings)
        modelContext.insert(entry)
        if modelContext.saveOrReport() { dismiss() } else { modelContext.delete(entry) }
    }
}

private struct EditFoodEntryView: View {
    let entry: FoodEntry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var mealType: MealType
    @State private var name: String
    @State private var servings: Double
    @State private var date: Date
    @State private var calories: Double
    @State private var protein: Double
    @State private var carbs: Double
    @State private var fat: Double
    @State private var water: Double
    @State private var note: String

    init(entry: FoodEntry) {
        self.entry = entry
        _mealType = State(initialValue: entry.mealType)
        _name = State(initialValue: entry.name)
        _servings = State(initialValue: entry.servings)
        _date = State(initialValue: entry.date)
        _calories = State(initialValue: entry.calories)
        _protein = State(initialValue: entry.proteinGrams)
        _carbs = State(initialValue: entry.carbohydrateGrams)
        _fat = State(initialValue: entry.fatGrams)
        _water = State(initialValue: entry.waterMilliliters)
        _note = State(initialValue: entry.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    Picker("Type", selection: $mealType) {
                        ForEach(MealType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Food or meal", text: $name)
                    Stepper("Servings: \(servings.formatted(.number.precision(.fractionLength(0...2))))", value: $servings, in: 0.25...20, step: 0.25)
                    DatePicker("Time", selection: $date)
                }
                Section("Nutrition") {
                    TextField("Calories", value: $calories, format: .number).keyboardType(.decimalPad)
                    TextField("Protein grams", value: $protein, format: .number).keyboardType(.decimalPad)
                    TextField("Carbohydrate grams", value: $carbs, format: .number).keyboardType(.decimalPad)
                    TextField("Fat grams", value: $fat, format: .number).keyboardType(.decimalPad)
                    TextField("Water milliliters", value: $water, format: .number).keyboardType(.decimalPad)
                }
                Section("Notes") { TextField("Optional", text: $note, axis: .vertical) }
            }
            .navigationTitle("Edit Food")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        entry.mealType = mealType
        entry.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.servings = servings
        entry.date = date
        entry.calories = calories
        entry.proteinGrams = protein
        entry.carbohydrateGrams = carbs
        entry.fatGrams = fat
        entry.waterMilliliters = water
        entry.note = note
        if modelContext.saveOrReport() { dismiss() }
    }
}

struct WeeklyMealPlanView: View {
    let profile: Profile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodEntry.date) private var allEntries: [FoodEntry]
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var showingAddPlanned = false
    @State private var showingAddActual = false
    @State private var editingPlanItem: FoodEntry?

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate)
        let start = interval?.start ?? calendar.startOfDay(for: selectedDate)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var planItems: [FoodEntry] {
        allEntries.filter { $0.profile?.id == profile.id && $0.isMealPlanItem && Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
            .sorted { mealOrder($0.mealType) < mealOrder($1.mealType) }
    }

    private var actualItems: [FoodEntry] {
        allEntries.filter { $0.profile?.id == profile.id && !$0.isMealPlanItem && Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LifeOSSpacing.lg) {
                    weekPicker
                    daySummary
                    Text("PLANNED VS ACTUAL").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(planItems) { item in
                            PlannedMealRow(item: item, state: state(for: item), actualName: actualName(for: item)) {
                                logPlannedMeal(item)
                            } edit: {
                                editingPlanItem = item
                            }
                            if item.id != planItems.last?.id { Divider().padding(.leading, 52) }
                        }
                        if planItems.isEmpty {
                            ContentUnavailableView("No Meals Planned", systemImage: "calendar.badge.plus", description: Text("Add meals for this day or copy a previous week."))
                                .padding(.vertical, 18)
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: LifeOSRadius.lg, style: .continuous))
                    HStack {
                        Button { showingAddActual = true } label: { Label("Add unplanned", systemImage: "plus") }.buttonStyle(LifeOSPrimaryButtonStyle())
                        Button { showingAddPlanned = true } label: { Label("Add to plan", systemImage: "calendar.badge.plus") }.buttonStyle(LifeOSSecondaryButtonStyle())
                    }
                }
                .padding(LifeOSSpacing.lg)
            }
            .background(NutritionBackground())
            .navigationTitle("Weekly Meal Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showingAddPlanned) { AddPlannedMealView(profile: profile, date: selectedDate) }
            .sheet(isPresented: $showingAddActual) { AddFoodEntryView(profile: profile, initialDate: selectedDate) }
            .sheet(item: $editingPlanItem) { EditPlannedMealView(entry: $0) }
        }
    }

    private var weekPicker: some View {
        HStack(spacing: 6) {
            ForEach(weekDates, id: \.self) { date in
                Button { selectedDate = date } label: {
                    VStack(spacing: 5) {
                        Text(date.formatted(.dateTime.weekday(.narrow))).font(.caption2)
                        Text(date.formatted(.dateTime.day())).font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(Calendar.current.isDate(date, inSameDayAs: selectedDate) ? Color.white : Color.primary)
                    .background(Calendar.current.isDate(date, inSameDayAs: selectedDate) ? Color.green : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var daySummary: some View {
        let logged = planItems.filter { state(for: $0) != .planned }.count
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide))).font(.title3.weight(.bold))
                Text("\(Int(planItems.reduce(0) { $0 + $1.calories })) planned kcal").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(logged) of \(planItems.count) logged").font(.caption.weight(.semibold)).foregroundStyle(.green)
        }
        .lifeOSGlassCard(tint: .green, cornerRadius: LifeOSRadius.lg)
    }

    private func state(for item: FoodEntry) -> PlannedMealState {
        let sameMeal = actualItems.filter { $0.mealType == item.mealType }
        if sameMeal.contains(where: { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }) { return .eaten }
        return sameMeal.isEmpty ? .planned : .changed
    }

    private func actualName(for item: FoodEntry) -> String? {
        guard state(for: item) == .changed else { return nil }
        return actualItems.first { $0.mealType == item.mealType }?.name
    }

    private func logPlannedMeal(_ item: FoodEntry) {
        guard state(for: item) == .planned else { return }
        let actual = FoodEntry(profile: profile, date: item.date, mealType: item.mealType, name: item.name, calories: item.calories, proteinGrams: item.proteinGrams, carbohydrateGrams: item.carbohydrateGrams, fatGrams: item.fatGrams, waterMilliliters: item.waterMilliliters, note: "Logged from weekly plan", nutritionSource: "Planned meal", servings: item.servings)
        modelContext.insert(actual)
        if !modelContext.saveOrReport() { modelContext.delete(actual) }
    }

    private func mealOrder(_ meal: MealType) -> Int {
        [MealType.breakfast, .lunch, .snack, .dinner, .drink].firstIndex(of: meal) ?? 5
    }
}

private enum PlannedMealState { case planned, eaten, changed }

private struct PlannedMealRow: View {
    let item: FoodEntry
    let state: PlannedMealState
    let actualName: String?
    let log: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: state == .eaten ? "checkmark.circle.fill" : state == .changed ? "arrow.triangle.2.circlepath" : "circle")
                .foregroundStyle(state == .eaten ? .green : state == .changed ? .orange : .secondary).frame(width: 38)
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.mealType.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(actualName.map { "Planned \(item.name) → actual \($0)" } ?? item.name).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button(state == .planned ? "Log" : state == .eaten ? "Eaten" : "Changed", action: log)
                .font(.caption.weight(.semibold)).disabled(state != .planned)
        }
        .frame(minHeight: 64)
    }
}

private struct AddPlannedMealView: View {
    let profile: Profile
    let date: Date
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var meal: MealType = .breakfast
    @State private var name = ""
    @State private var calories = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0

    var body: some View {
        NavigationStack {
            Form {
                Picker("Meal", selection: $meal) { ForEach(MealType.allCases) { Text($0.rawValue).tag($0) } }
                TextField("Planned food or meal", text: $name)
                Section("Nutrition") {
                    TextField("Calories", value: $calories, format: .number).keyboardType(.decimalPad)
                    TextField("Protein grams", value: $protein, format: .number).keyboardType(.decimalPad)
                    TextField("Carbohydrate grams", value: $carbs, format: .number).keyboardType(.decimalPad)
                    TextField("Fat grams", value: $fat, format: .number).keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Plan a Meal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add", action: save).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }

    private func save() {
        let planned = FoodEntry(profile: profile, date: date, mealType: meal, name: name.trimmingCharacters(in: .whitespacesAndNewlines), calories: calories, proteinGrams: protein, carbohydrateGrams: carbs, fatGrams: fat, nutritionSource: FoodEntry.mealPlanSource)
        modelContext.insert(planned)
        if modelContext.saveOrReport() { dismiss() } else { modelContext.delete(planned) }
    }
}

private struct EditPlannedMealView: View {
    let entry: FoodEntry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var meal: MealType
    @State private var name: String
    @State private var calories: Double
    @State private var protein: Double
    @State private var carbs: Double
    @State private var fat: Double

    init(entry: FoodEntry) {
        self.entry = entry
        _meal = State(initialValue: entry.mealType)
        _name = State(initialValue: entry.name)
        _calories = State(initialValue: entry.calories)
        _protein = State(initialValue: entry.proteinGrams)
        _carbs = State(initialValue: entry.carbohydrateGrams)
        _fat = State(initialValue: entry.fatGrams)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Meal", selection: $meal) { ForEach(MealType.allCases) { Text($0.rawValue).tag($0) } }
                TextField("Planned food or meal", text: $name)
                TextField("Calories", value: $calories, format: .number).keyboardType(.decimalPad)
                TextField("Protein grams", value: $protein, format: .number).keyboardType(.decimalPad)
                TextField("Carbohydrate grams", value: $carbs, format: .number).keyboardType(.decimalPad)
                TextField("Fat grams", value: $fat, format: .number).keyboardType(.decimalPad)
            }
            .navigationTitle("Edit Planned Meal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }

    private func save() {
        entry.mealType = meal
        entry.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.calories = calories
        entry.proteinGrams = protein
        entry.carbohydrateGrams = carbs
        entry.fatGrams = fat
        if modelContext.saveOrReport() { dismiss() }
    }
}
