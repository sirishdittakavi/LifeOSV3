import SwiftUI
import SwiftData

struct ImprovementCategoryDetailView: View {
    @Bindable var selection: SelectedProfile
    let category: AppCategory
    @Environment(\.modelContext) private var modelContext
    @Query private var categories: [AppCategory]
    @Query private var activities: [Activity]
    @Query private var calendarItems: [CalendarItem]
    @Query private var foodEntries: [FoodEntry]
    @Query private var weightEntries: [WeightEntry]
    @Query private var baseballEntries: [BaseballEntry]
    @State private var period: DashboardPeriod = .week
    @State private var showingAddTask = false
    @State private var showingAddSubcategory = false
    @State private var showingEdit = false
    @State private var activeTool: CategoryTool?
    @State private var showingTemplateSaved = false

    private var categoryActivities: [Activity] {
        let includedIDs = CategoryHierarchy.idsIncludingDescendants(of: category, in: profileCategories)
        return activities.filter {
            $0.category.map { includedIDs.contains($0.id) } == true && $0.isActive
        }
            .sorted { $0.plannedStartMinutes < $1.plannedStartMinutes }
    }

    private var directCategoryActivities: [Activity] {
        activities.filter { $0.category?.id == category.id && $0.isActive }
    }

    private var profileCategories: [AppCategory] {
        categories.filter { $0.profile?.id == category.profile?.id && $0.isActive }
    }

    private var childCategories: [AppCategory] {
        CategoryHierarchy.directChildren(of: category, in: profileCategories)
    }

    private var relatedCategories: [AppCategory] {
        let related = Set(category.relatedCategoryIDs)
        return categories.filter { related.contains($0.id) }
    }

    private var progress: CategoryProgress? {
        guard let profile = selection.profile else { return nil }
        return CategoryProgressEngine.progress(
            profile: profile, category: category,
            includedCategoryIDs: CategoryHierarchy.idsIncludingDescendants(of: category, in: profileCategories),
            period: period,
            activities: activities, calendarItems: calendarItems,
            foodEntries: foodEntries, weightEntries: weightEntries,
            baseballEntries: baseballEntries
        )
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(category.pillar.rawValue, systemImage: category.symbol)
                        .font(.caption).bold()
                        .foregroundStyle(ColorToken.color(for: category.colorToken))
                    Text(category.purpose.isEmpty ? "Improve through consistent, measurable action." : category.purpose)
                        .font(.body)
                    Text("Weekly commitment: \(category.weeklyTargetSessions) sessions · \(category.weeklyTargetMinutes) minutes")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Subcategories and Programs") {
                if childCategories.isEmpty {
                    Text("Optional: split this area into programs, subjects, teams, projects, or other useful groups.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(childCategories) { child in
                        NavigationLink {
                            ImprovementCategoryDetailView(selection: selection, category: child)
                        } label: {
                            Label(child.name, systemImage: child.symbol)
                        }
                    }
                }
                Button { showingAddSubcategory = true } label: {
                    Label("Add Subcategory or Program", systemImage: "plus")
                }
            }

            Section {
                Picker("Period", selection: $period) {
                    ForEach(DashboardPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if let progress { CategoryProgressCard(progress: progress) }
            }

            if let tool = categoryTool {
                Section("Tracking") {
                    Button { activeTool = tool } label: {
                        Label(tool.buttonTitle, systemImage: tool.symbol)
                    }
                }
            }

            Section("Tasks and habits") {
                if categoryActivities.isEmpty {
                    Text("No scheduled tasks yet. Add the first action that creates improvement.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(categoryActivities) { activity in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(activity.name).font(.headline)
                            if let activityCategory = activity.category, activityCategory.id != category.id {
                                Text(CategoryHierarchy.breadcrumbName(for: activityCategory, in: profileCategories))
                                    .font(.caption2).bold()
                                    .foregroundStyle(ColorToken.color(for: activityCategory.colorToken))
                            }
                            Text(scheduleDescription(activity))
                                .font(.caption).foregroundStyle(.secondary)
                            if let target = activity.targetValue, let unit = activity.targetUnit {
                                Text("Target: \(target.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button { showingAddTask = true } label: { Label("Add Task or Habit", systemImage: "plus") }
            }

            Section("Connected improvement areas") {
                if relatedCategories.isEmpty {
                    Text("No relationships configured yet.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(relatedCategories) { related in
                                Label(related.name, systemImage: related.symbol)
                                    .font(.caption).bold()
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(ColorToken.color(for: related.colorToken).opacity(0.13))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }

            Section("Reminders") {
                Label(
                    category.reminderEnabled
                        ? "Task reminders and a weekly review are enabled."
                        : "Reminders are off.",
                    systemImage: category.reminderEnabled ? "bell.badge.fill" : "bell.slash"
                )
                .foregroundStyle(category.reminderEnabled ? .blue : .secondary)
            }
        }
        .navigationTitle(category.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        let saved = SavedCategoryTemplate(category: category, activities: directCategoryActivities)
                        modelContext.insert(saved)
                        try? modelContext.save()
                        showingTemplateSaved = true
                    } label: {
                        Label("Save as Reusable Template", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Template Saved", isPresented: $showingTemplateSaved) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(category.name) and its direct tasks are now available under My Saved Templates for every profile on this device.")
        }
        .sheet(isPresented: $showingAddTask) {
            if let profile = selection.profile {
                AddActivityView(profile: profile, initialCategory: category)
            }
        }
        .sheet(isPresented: $showingAddSubcategory) {
            if let profile = selection.profile {
                AddImprovementCategoryView(profile: profile, parentCategory: category)
            }
        }
        .sheet(isPresented: $showingEdit) {
            EditImprovementCategoryView(category: category, activities: categoryActivities)
        }
        .sheet(item: $activeTool) { tool in
            switch tool {
            case .food: FoodTrackerView(selection: selection)
            case .weight: WeightTrackerView(selection: selection)
            case .baseball: BaseballTrackerView(selection: selection)
            }
        }
    }

    private var categoryTool: CategoryTool? {
        let name = ([category] + CategoryHierarchy.ancestors(of: category, in: profileCategories))
            .map(\.name).joined(separator: " ").lowercased()
        if name.contains("nutrition") || name.contains("food") { return .food }
        if name.contains("weight") || name.contains("body development") || name.contains("body composition") { return .weight }
        if name.contains("baseball") { return .baseball }
        return nil
    }

    private func scheduleDescription(_ activity: Activity) -> String {
        let hour = activity.plannedStartMinutes / 60
        let minute = activity.plannedStartMinutes % 60
        let time = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now)?
            .formatted(date: .omitted, time: .shortened) ?? ""
        let repeatText: String
        switch activity.repeatType {
        case .once, .daily, .selectedWeekdays:
            repeatText = activity.repeatType.rawValue
        case .timesPerDay:
            repeatText = "\(activity.occurrencesPerDay)× daily · every \(activity.repeatIntervalMinutes) min"
        case .timesPerWeek:
            repeatText = "\(activity.occurrencesPerWeek)× weekly"
        }
        return "\(repeatText) · \(activity.estimatedDurationMinutes) min · \(time)"
    }
}

private enum CategoryTool: String, Identifiable {
    case food, weight, baseball
    var id: String { rawValue }
    var buttonTitle: String {
        switch self {
        case .food: return "Open Food & Nutrition Tracker"
        case .weight: return "Open Weight & Body Trend"
        case .baseball: return "Open Baseball Training Log"
        }
    }
    var symbol: String {
        switch self {
        case .food: return "fork.knife"
        case .weight: return "scalemass.fill"
        case .baseball: return "figure.baseball"
        }
    }
}

struct EditImprovementCategoryView: View {
    @Bindable var category: AppCategory
    let activities: [Activity]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allCategories: [AppCategory]
    @State private var relatedIDs: Set<UUID>
    @State private var reminderTime: Date
    @State private var parentCategoryID: UUID?
    @State private var showingDeactivateConfirmation = false

    init(category: AppCategory, activities: [Activity]) {
        self.category = category
        self.activities = activities
        _relatedIDs = State(initialValue: Set(category.relatedCategoryIDs))
        _parentCategoryID = State(initialValue: category.parentCategoryID)
        _reminderTime = State(initialValue: Calendar.current.date(
            bySettingHour: category.reminderHour,
            minute: category.reminderMinute,
            second: 0,
            of: .now
        ) ?? .now)
    }

    private var availableRelations: [AppCategory] {
        allCategories.filter { $0.profile?.id == category.profile?.id && $0.id != category.id && $0.isActive }
            .sorted { $0.name < $1.name }
    }

    private var availableParents: [AppCategory] {
        let profileCategories = allCategories.filter {
            $0.profile?.id == category.profile?.id && $0.id != category.id && $0.isActive
        }
        let descendantIDs = Set(CategoryHierarchy.descendants(of: category, in: allCategories).map(\.id))
        return profileCategories.filter { !descendantIDs.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Improvement area") {
                    TextField("Name", text: $category.name)
                    Picker("Inside", selection: $parentCategoryID) {
                        Text("Top-level improvement area").tag(UUID?.none)
                        ForEach(availableParents) { parent in
                            Text(CategoryHierarchy.breadcrumbName(for: parent, in: allCategories))
                                .tag(UUID?.some(parent.id))
                        }
                    }
                    Picker("Pillar", selection: Binding(
                        get: { category.pillar }, set: { category.pillar = $0 }
                    )) {
                        ForEach(ImprovementPillar.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Icon", selection: $category.symbol) {
                        ForEach(CategoryAppearanceOptions.icons) { option in
                            Label(option.name, systemImage: option.symbol).tag(option.symbol)
                        }
                    }
                    Picker("Colour", selection: $category.colorToken) {
                        ForEach(CategoryAppearanceOptions.colors, id: \.self) { token in
                            Label(token.capitalized, systemImage: "circle.fill")
                                .foregroundStyle(ColorToken.color(for: token))
                                .tag(token)
                        }
                    }
                    TextField("Purpose", text: $category.purpose, axis: .vertical)
                }

                Section("Weekly target") {
                    Stepper("\(category.weeklyTargetSessions) sessions", value: $category.weeklyTargetSessions, in: 0...21)
                    Stepper("\(category.weeklyTargetMinutes) minutes", value: $category.weeklyTargetMinutes, in: 0...1200, step: 15)
                }

                Section("Connected areas") {
                    ForEach(availableRelations) { related in
                        Button {
                            if relatedIDs.contains(related.id) { relatedIDs.remove(related.id) }
                            else { relatedIDs.insert(related.id) }
                        } label: {
                            HStack {
                                Label(related.name, systemImage: related.symbol)
                                Spacer()
                                if relatedIDs.contains(related.id) { Image(systemName: "checkmark") }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section("Reminders") {
                    Toggle("Enable reminders", isOn: $category.reminderEnabled)
                    if category.reminderEnabled {
                        DatePicker("Weekly review time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        Text("Task reminders use each task's scheduled days and time.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Category Management") {
                    if category.isActive {
                        Button("Deactivate Category and Its Tasks", role: .destructive) {
                            showingDeactivateConfirmation = true
                        }
                        Text("Use this for duplicates or areas you no longer want to track. History is kept.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Reactivate Category and Its Tasks") {
                            category.isActive = true
                            activities.forEach { $0.isActive = true }
                            try? modelContext.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Edit Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .confirmationDialog(
                "Deactivate \(category.name)?",
                isPresented: $showingDeactivateConfirmation,
                titleVisibility: .visible
            ) {
                Button("Deactivate Category and Tasks", role: .destructive) {
                    category.isActive = false
                    activities.forEach { $0.isActive = false }
                    try? modelContext.save()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It will disappear from active categories and stop generating scheduled tasks. Existing history remains saved.")
            }
        }
    }

    private func save() {
        category.parentCategoryID = parentCategoryID
        category.relatedCategoryIDs = Array(relatedIDs)
        category.reminderHour = Calendar.current.component(.hour, from: reminderTime)
        category.reminderMinute = Calendar.current.component(.minute, from: reminderTime)
        try? modelContext.save()
        Task { await ReminderService.updateReminders(for: category, activities: activities) }
        dismiss()
    }
}
