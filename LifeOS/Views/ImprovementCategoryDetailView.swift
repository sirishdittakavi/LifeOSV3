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
    @Query private var sportEntries: [SportEntry]
    @State private var period: DashboardPeriod = .week
    @State private var showingAddTask = false
    @State private var showingAddSubcategory = false
    @State private var showingEdit = false
    @State private var activeTool: CategoryTool?
    @State private var showingTemplateSaved = false
    @State private var showingProgressDetails = false

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

    private var progress: CategoryProgress? {
        guard let profile = selection.profile else { return nil }
        return CategoryProgressEngine.progress(
            profile: profile, category: category,
            includedCategoryIDs: CategoryHierarchy.idsIncludingDescendants(of: category, in: profileCategories),
            period: period,
            activities: activities, calendarItems: calendarItems,
            foodEntries: foodEntries, weightEntries: weightEntries,
            sportEntries: sportEntries
        )
    }

    private var periodActionSummaries: [ActionPeriodSummary] {
        let interval = period.interval(containing: .now)
        let days = dates(in: interval)

        return categoryActivities.compactMap { activity in
            let plannedCount = days.reduce(0) { count, date in
                count + PlanningService.scheduledStartMinutes(activity, on: date).count
            }
            let existingItems = PlanningService.plannedItems(calendarItems.filter {
                $0.activity?.id == activity.id && interval.contains($0.date)
            })
            guard plannedCount > 0 || !existingItems.isEmpty else { return nil }
            return ActionPeriodSummary(
                activity: activity,
                plannedCount: max(plannedCount, existingItems.count),
                completedCount: existingItems.filter { $0.status == .done }.count,
                decidedCount: existingItems.filter {
                    $0.status == .done || $0.status == .skipped || $0.status == .rescheduled
                }.count
            )
        }
        .sorted { $0.activity.plannedStartMinutes < $1.activity.plannedStartMinutes }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                areaHeader

                Picker("Period", selection: $period) {
                    ForEach(DashboardPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if let progress {
                    Button { showingProgressDetails = true } label: {
                        CategoryProgressCard(progress: progress)
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(category.name) activity plan details")
                }

                VStack(spacing: 10) {
                    if let tool = categoryTool {
                        Button { activeTool = tool } label: {
                            Label(trackingButtonTitle(for: tool), systemImage: tool == .sport ? category.symbol : tool.symbol)
                        }
                        .buttonStyle(LifeOSPrimaryButtonStyle())
                    }

                    if categoryTool == nil {
                        Button { showingAddTask = true } label: {
                            Label("Add an Action", systemImage: "plus")
                        }
                        .buttonStyle(LifeOSPrimaryButtonStyle())
                    } else {
                        Button { showingAddTask = true } label: {
                            Label("Add an Action", systemImage: "plus")
                        }
                        .buttonStyle(LifeOSSecondaryButtonStyle())
                    }
                }

                if !childCategories.isEmpty {
                    sectionTitle("Focus Areas", detail: "Included in the activity plan above")
                    VStack(spacing: 0) {
                        ForEach(Array(childCategories.enumerated()), id: \.element.id) { index, child in
                            NavigationLink {
                                ImprovementCategoryDetailView(selection: selection, category: child)
                            } label: {
                                focusAreaRow(child)
                            }
                            .buttonStyle(.plain)
                            if index < childCategories.count - 1 { Divider().padding(.leading, 54) }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                sectionTitle(periodActionsTitle, detail: "Only actions planned in this period")
                actionList
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddTask = true } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingEdit = true } label: {
                        Label("Edit Area", systemImage: "pencil")
                    }
                    Button { showingAddSubcategory = true } label: {
                        Label("Add Optional Focus Area", systemImage: "rectangle.stack.badge.plus")
                    }
                    Button {
                        let saved = SavedCategoryTemplate(category: category, activities: directCategoryActivities)
                        modelContext.insert(saved)
                        try? modelContext.save()
                        showingTemplateSaved = true
                    } label: {
                        Label("Save as Reusable Plan", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Plan Saved", isPresented: $showingTemplateSaved) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(category.name) and its direct actions are now available under My Saved Plans for every profile on this device.")
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
            case .sport: SportTrackerView(selection: selection, category: category)
            }
        }
        .sheet(isPresented: $showingProgressDetails) {
            if let progress {
                CategoryProgressDetailView(progress: progress)
            }
        }
    }

    private var areaHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: category.symbol)
                .font(.title2)
                .frame(width: 48, height: 48)
                .foregroundStyle(ColorToken.color(for: category.colorToken))
                .background(ColorToken.color(for: category.colorToken).opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(category.pillar.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ColorToken.color(for: category.colorToken))
                Text(category.purpose.isEmpty ? "Organise the actions that support your Goals." : category.purpose)
                    .font(.subheadline)
                Text("Weekly activity plan · \(category.weeklyTargetSessions) times · \(category.weeklyTargetMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lifeOSCard()
    }

    @ViewBuilder
    private var actionList: some View {
        if categoryActivities.isEmpty {
            emptyActions(
                title: "No actions yet",
                message: "Add one small repeatable action. It will appear here and on the Schedule."
            )
        } else if periodActionSummaries.isEmpty {
            emptyActions(
                title: "Nothing planned for this \(period.emptyPeriodName)",
                message: "Your actions are safe. Change the period above or add an action for this time."
            )
        } else {
            VStack(spacing: 12) {
                ForEach(periodActionSummaries) { summary in
                    ActionPeriodCard(
                        summary: summary,
                        category: category,
                        profileCategories: profileCategories,
                        scheduleText: scheduleDescription(summary.activity)
                    )
                }
            }
        }
    }

    private func emptyActions(title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.plus")
                .font(.title2)
                .foregroundStyle(ColorToken.color(for: category.colorToken))
            Text(title).font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .lifeOSCard()
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.bold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func focusAreaRow(_ child: AppCategory) -> some View {
        let childProgress = progress(for: child)
        return HStack(spacing: 12) {
            Image(systemName: child.symbol)
                .frame(width: 38, height: 38)
                .foregroundStyle(ColorToken.color(for: child.colorToken))
                .background(ColorToken.color(for: child.colorToken).opacity(0.14))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(child.name).font(.headline).foregroundStyle(.primary)
                Text(childProgress?.progressText ?? "No target configured")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(childProgress?.status.rawValue ?? "")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    private func progress(for child: AppCategory) -> CategoryProgress? {
        guard let profile = selection.profile else { return nil }
        return CategoryProgressEngine.progress(
            profile: profile,
            category: child,
            includedCategoryIDs: CategoryHierarchy.idsIncludingDescendants(of: child, in: profileCategories),
            period: period,
            activities: activities,
            calendarItems: calendarItems,
            foodEntries: foodEntries,
            weightEntries: weightEntries,
            sportEntries: sportEntries
        )
    }

    private var periodActionsTitle: String {
        switch period {
        case .day: return "Today's Actions"
        case .week: return "This Week's Actions"
        case .month: return "This Month's Actions"
        }
    }

    private func trackingButtonTitle(for tool: CategoryTool) -> String {
        switch tool {
        case .food: return "Log Food or Nutrition"
        case .weight: return "Log Weight"
        case .sport: return "Log \(category.name) Training"
        }
    }

    private func dates(in interval: DateInterval) -> [Date] {
        var result: [Date] = []
        var date = Calendar.current.startOfDay(for: interval.start)
        while date < interval.end {
            result.append(date)
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return result
    }

    private var categoryTool: CategoryTool? {
        let name = ([category] + CategoryHierarchy.ancestors(of: category, in: profileCategories))
            .map(\.name).joined(separator: " ").lowercased()
        if name.contains("nutrition") || name.contains("food") { return .food }
        if name.contains("weight") || name.contains("body development") || name.contains("body composition") { return .weight }
        if category.pillar == .sport
            || CategoryHierarchy.ancestors(of: category, in: profileCategories).contains(where: { $0.pillar == .sport }) {
            return .sport
        }
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

private struct ActionPeriodSummary: Identifiable {
    let activity: Activity
    let plannedCount: Int
    let completedCount: Int
    let decidedCount: Int

    var id: UUID { activity.id }
    var fraction: Double {
        guard plannedCount > 0 else { return 0 }
        return min(Double(completedCount) / Double(plannedCount), 1)
    }
}

private struct ActionPeriodCard: View {
    let summary: ActionPeriodSummary
    let category: AppCategory
    let profileCategories: [AppCategory]
    let scheduleText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.activity.name).font(.headline)
                    if let actionCategory = summary.activity.category, actionCategory.id != category.id {
                        Text(CategoryHierarchy.breadcrumbName(for: actionCategory, in: profileCategories))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ColorToken.color(for: actionCategory.colorToken))
                    }
                    Text(scheduleText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("\(summary.completedCount)/\(summary.plannedCount)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(summary.completedCount >= summary.plannedCount ? .green : .blue)
            }
            ProgressView(value: summary.fraction)
                .tint(summary.completedCount >= summary.plannedCount ? .green : .blue)
            Text(summary.decidedCount == summary.plannedCount
                 ? "All planned occurrences decided"
                 : "\(summary.plannedCount - summary.decidedCount) still to do or decide")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .lifeOSCard(cornerRadius: 16)
    }
}

private extension DashboardPeriod {
    var emptyPeriodName: String {
        switch self {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        }
    }
}

private struct CategoryProgressDetailView: View {
    let progress: CategoryProgress
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CategoryProgressCard(progress: progress, showsDisclosureIndicator: false)
                }

                Section("Target and actual") {
                    if progress.targetSessions > 0 {
                        LabeledContent("Sessions") {
                            Text("\(progress.completedSessions) of \(progress.targetSessions)")
                        }
                    }
                    if progress.targetMinutes > 0 {
                        LabeledContent("Minutes") {
                            Text("\(progress.completedMinutes) of \(progress.targetMinutes)")
                        }
                    }
                    if progress.targetSessions == 0 && progress.targetMinutes == 0 {
                        Text("No target is configured for this period.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Plan adherence") {
                    LabeledContent("Status", value: progress.status.rawValue)
                    LabeledContent("Confidence", value: progress.confidence.rawValue)
                    if progress.dueTasks > 0 {
                        LabeledContent("Due actions decided") {
                            Text("\(progress.decidedDueTasks) of \(progress.dueTasks)")
                        }
                    }
                }

                Section("What to do next") {
                    Text(progress.nextAction)
                }
            }
            .navigationTitle("\(progress.period.rawValue) Activity Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private enum CategoryTool: String, Identifiable {
    case food, weight, sport
    var id: String { rawValue }
    var buttonTitle: String {
        switch self {
        case .food: return "Open Food & Nutrition Tracker"
        case .weight: return "Open Weight & Body Trend"
        case .sport: return "Open Sport Training Log"
        }
    }
    var symbol: String {
        switch self {
        case .food: return "fork.knife"
        case .weight: return "scalemass.fill"
        case .sport: return "figure.run"
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
                Section("Area") {
                    TextField("Name", text: $category.name)
                    Picker("Inside", selection: $parentCategoryID) {
                        Text("Top-level area").tag(UUID?.none)
                        ForEach(availableParents) { parent in
                            Text(CategoryHierarchy.breadcrumbName(for: parent, in: allCategories))
                                .tag(UUID?.some(parent.id))
                        }
                    }
                    Picker("Group", selection: Binding(
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

                Section("Weekly activity plan") {
                    Stepper("\(category.weeklyTargetSessions) times", value: $category.weeklyTargetSessions, in: 0...21)
                    Stepper("\(category.weeklyTargetMinutes) minutes", value: $category.weeklyTargetMinutes, in: 0...1200, step: 15)
                    Text("This is an effort target. Outcome targets belong to Goals.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Related areas (optional)") {
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
                        Text("Action reminders use each action's scheduled days and time.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Area Management") {
                    if category.isActive {
                        Button("Hide Area and Its Actions", role: .destructive) {
                            showingDeactivateConfirmation = true
                        }
                        Text("Use this for duplicates or areas you no longer want to track. History is kept.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Restore Area and Its Actions") {
                            category.isActive = true
                            activities.forEach { $0.isActive = true }
                            try? modelContext.save()
                            Task { await ReminderService.updateReminders(for: category, activities: activities) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Edit Area")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .confirmationDialog(
                "Hide \(category.name)?",
                isPresented: $showingDeactivateConfirmation,
                titleVisibility: .visible
            ) {
                Button("Hide Area and Actions", role: .destructive) {
                    category.isActive = false
                    activities.forEach { $0.isActive = false }
                    try? modelContext.save()
                    Task { await ReminderService.updateReminders(for: category, activities: activities) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It will disappear from active areas and stop generating scheduled actions. Existing history remains saved.")
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
