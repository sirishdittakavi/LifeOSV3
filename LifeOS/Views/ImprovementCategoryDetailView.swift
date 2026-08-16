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
    @Query private var measurementDefinitions: [MeasurementDefinition]
    @Query private var measurementEntries: [MeasurementEntry]
    @Query private var activitySessions: [ActivitySession]
    @State private var period: DashboardPeriod = .week
    @State private var showingAddTask = false
    @State private var showingAddSubcategory = false
    @State private var showingEdit = false
    @State private var activeTool: CategoryTool?
    @State private var showingTemplateSaved = false
    @State private var showingProgressDetails = false
    @State private var showingManageTasks = false
    @State private var editingTask: Activity?

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

    /// Today's occurrences across this Area's Tasks, in schedule order —
    /// powers the "Today" section's task list, the same data `TodayViewModel`
    /// already surfaces for the Today screen, just scoped to this Area.
    private var todayItemsForArea: [CalendarItem] {
        let activityIDs = Set(categoryActivities.map(\.id))
        return calendarItems
            .filter {
                $0.activity.map { activityIDs.contains($0.id) } == true
                    && Calendar.current.isDateInToday($0.date)
            }
            .sorted { ($0.plannedStart ?? .distantFuture) < ($1.plannedStart ?? .distantFuture) }
    }

    /// Reuses `TodayViewModel`'s existing start/skip/quickFinish logic (the
    /// same actions the Today screen drives) rather than re-implementing
    /// status transitions here.
    private var todayViewModel: TodayViewModel {
        TodayViewModel(
            profile: selection.profile,
            items: calendarItems,
            activities: activities,
            resultMeasures: [],
            currentTime: .now,
            repository: SwiftDataCalendarRepository(context: modelContext)
        )
    }

    /// Measurements across every Task in this Area, each shown against
    /// today's total independently — never blended across measurements or
    /// units, per the measurement-behavior spec.
    private var areaMeasurements: [MeasurementProgressRow] {
        let activityIDs = Set(categoryActivities.map(\.id))
        let interval = DateInterval(start: Calendar.current.startOfDay(for: .now), duration: 86_400)
        return measurementDefinitions
            .filter { definition in
                guard definition.isActive, let activityID = definition.activity?.id else { return false }
                return activityIDs.contains(activityID)
            }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { definition in
                MeasurementProgressRow(
                    id: definition.id,
                    activityName: definition.activity?.name ?? "",
                    definition: definition,
                    total: ProgressEngine.measurementTotal(for: definition, entries: measurementEntries, interval: interval)
                )
            }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                areaHeader

                todayCard

                progressSection

                if !areaMeasurements.isEmpty {
                    measurementsSection
                }

                activitiesSection

                if !childCategories.isEmpty {
                    subAreasSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(Color.lifeOSCanvas)
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingAddTask = true } label: {
                        Label("Add a Task", systemImage: "plus")
                    }
                    Button { showingEdit = true } label: {
                        Label("Edit Area", systemImage: "pencil")
                    }
                    Button { showingManageTasks = true } label: {
                        Label("Manage Tasks", systemImage: "checklist")
                    }
                    Button { showingAddSubcategory = true } label: {
                        Label("Add Optional Sub-area", systemImage: "rectangle.stack.badge.plus")
                    }
                    Button {
                        let saved = SavedCategoryTemplate(category: category, activities: directCategoryActivities)
                        modelContext.insert(saved)
                        if modelContext.saveOrReport() {
                            showingTemplateSaved = true
                        } else {
                            modelContext.delete(saved)
                        }
                    } label: {
                        Label("Save as Reusable Area", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Area Saved", isPresented: $showingTemplateSaved) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(category.name) and its direct Tasks are now available under My Saved Areas for every profile on this device.")
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
        .sheet(isPresented: $showingManageTasks) {
            ManageAreaTasksView(category: category, profileCategories: profileCategories)
        }
        .sheet(item: $editingTask) { TaskDetailView(activity: $0) }
        .sheet(item: $activeTool) { tool in
            switch tool {
            case .food: NutritionDashboardView(selection: selection)
            case .weight: BodyTrackingView(selection: selection)
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
            LOIconBadge(symbol: category.symbol, tint: ColorToken.color(for: category.colorToken), diameter: 48)

            VStack(alignment: .leading, spacing: 5) {
                Text(category.pillar.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ColorToken.color(for: category.colorToken))
                Text(category.purpose.isEmpty ? "Organise the Tasks that support your Goals." : category.purpose)
                    .font(.subheadline)
                Text("Weekly Task plan · \(category.weeklyTargetSessions) times · \(category.weeklyTargetMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lifeOSCard(tint: ColorToken.color(for: category.colorToken))
    }

    /// "What should I do today?" — every occurrence of this Area's Tasks
    /// scheduled for today, each with a status glyph. Tap the row for
    /// details, tap the status control to mark it done directly.
    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            LOSectionHeader(title: "Today")
            if todayItemsForArea.isEmpty {
                Text("Nothing scheduled today.")
                    .font(.lifeOSSecondary)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(todayItemsForArea) { item in
                        todayTaskRow(item)
                    }
                }
            }
        }
    }

    /// v1 task interaction is deliberately a single tap: planned → done.
    /// Start/Finish/Skip stay available as advanced actions elsewhere
    /// (Today screen, Task detail) but are not surfaced here. A completed
    /// Task can be tapped again to undo an accidental completion — this
    /// never creates a duplicate record, it removes the session `quickFinish`
    /// created and puts the Task back to `.planned`.
    private func todayTaskRow(_ item: CalendarItem) -> some View {
        LOTaskRow(
            title: item.activity?.name ?? "Task",
            subtitle: item.plannedStart?.formatted(date: .omitted, time: .shortened),
            symbol: item.activity?.category?.symbol ?? category.symbol,
            status: loStatus(for: item),
            onTap: { if let activity = item.activity { editingTask = activity } },
            onStatusTap: statusTapAction(for: item)
        )
        .accessibilityIdentifier("plan.task.status.\(item.activity?.name.lowercased() ?? "unknown")")
    }

    private func statusTapAction(for item: CalendarItem) -> (() -> Void)? {
        switch item.status {
        case .planned, .inProgress:
            return {
                if todayViewModel.quickFinish(item, at: .now),
                   let activityID = item.activity?.id, let plannedStart = item.plannedStart {
                    ReminderService.cancelReminder(activityID: activityID, occurrence: plannedStart, center: RealNotificationCenter.shared)
                }
            }
        case .done:
            return { undoComplete(item) }
        case .skipped, .rescheduled, .unplanned:
            return nil
        }
    }

    /// Reverts a completed occurrence back to `.planned` and removes the
    /// `ActivitySession` `quickFinish` created for it, so undo never leaves
    /// a duplicate or orphaned record behind.
    private func undoComplete(_ item: CalendarItem) {
        guard item.status == .done else { return }
        let sessionsToRemove = activitySessions.filter { $0.calendarItem?.id == item.id }
        let previousStatus = item.status
        let previousStart = item.actualStart
        let previousEnd = item.actualEnd

        item.status = .planned
        item.actualStart = nil
        item.actualEnd = nil
        sessionsToRemove.forEach { modelContext.delete($0) }

        if !modelContext.saveOrReport() {
            item.status = previousStatus
            item.actualStart = previousStart
            item.actualEnd = previousEnd
            sessionsToRemove.forEach { modelContext.insert($0) }
        }
    }

    private func loStatus(for item: CalendarItem) -> LOStatus {
        switch item.status {
        case .done: return .complete
        case .inProgress: return .focus
        case .skipped: return .neutral
        case .rescheduled: return .inProgress
        case .unplanned: return .recovery
        case .planned: return .neutral
        }
    }

    /// "Am I improving?" — period progress, kept separate from today's facts
    /// so a reader never mistakes today's numbers for a period total.
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LOSectionHeader(title: "Progress")
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
                .accessibilityLabel("Open \(category.name) Task progress details for \(period.rawValue)")
            }
        }
    }

    /// "What numbers matter?" — each measurement shown against its own
    /// target independently, never blended across measurements or units.
    private var measurementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LOSectionHeader(title: "Measurements")
            VStack(spacing: 8) {
                ForEach(areaMeasurements) { row in
                    measurementRow(row)
                }
            }
        }
    }

    /// "What can I do in this Area?" — every Task, plus the ability to add
    /// one (or open this Area's tracker tool, when it has one). Labeled
    /// "Tasks", not "Activities" — the app calls a schedulable `Activity`
    /// a "Task" everywhere else in the UI ("Add a Task", "Manage Tasks"),
    /// so this section stays consistent rather than introducing a second
    /// user-facing name for the same thing.
    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Tasks", detail: periodActionsDetail)

            VStack(spacing: 10) {
                if let tool = categoryTool {
                    Button { activeTool = tool } label: {
                        Label(trackingButtonTitle(for: tool), systemImage: tool == .sport ? category.symbol : tool.symbol)
                    }
                    .buttonStyle(LifeOSPrimaryButtonStyle())

                    Button { showingAddTask = true } label: {
                        Label("Add a Task", systemImage: "plus")
                    }
                    .buttonStyle(LifeOSSecondaryButtonStyle())
                } else {
                    Button { showingAddTask = true } label: {
                        Label("Add a Task", systemImage: "plus")
                    }
                    .buttonStyle(LifeOSPrimaryButtonStyle())
                }
            }

            actionList
        }
    }

    private var subAreasSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Sub-areas", detail: "Included in this Area's progress")
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
    }

    private func measurementRow(_ row: MeasurementProgressRow) -> some View {
        LOCard {
            if let target = row.definition.targetValue, target > 0 {
                LOProgressBar(
                    label: "\(row.activityName) · \(row.definition.name)",
                    currentText: formattedMeasurement(row.total),
                    targetText: "\(formattedMeasurement(target)) \(row.definition.unit ?? "")",
                    fraction: row.total / target,
                    status: row.total / target >= 1 ? .complete : .inProgress
                )
            } else {
                HStack {
                    Text("\(row.activityName) · \(row.definition.name)").font(.lifeOSBody)
                    Spacer()
                    Text("\(formattedMeasurement(row.total)) \(row.definition.unit ?? "")")
                        .font(.lifeOSSecondary).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formattedMeasurement(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }

    @ViewBuilder
    private var actionList: some View {
        if categoryActivities.isEmpty {
            emptyActions(
                title: "No Tasks yet",
                message: "Add one small repeatable Task. It will appear here and on the Schedule."
            )
        } else if periodActionSummaries.isEmpty {
            emptyActions(
                title: "Nothing planned for this \(period.emptyPeriodName)",
                message: "Your Tasks are safe. Change the period above or add a Task for this time."
            )
        } else {
            VStack(spacing: 12) {
                ForEach(periodActionSummaries) { summary in
                    Button { editingTask = summary.activity } label: {
                        ActionPeriodCard(
                            summary: summary,
                            category: category,
                            profileCategories: profileCategories,
                            scheduleText: scheduleDescription(summary.activity)
                        )
                    }
                    .buttonStyle(.plain)
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

    private var periodActionsDetail: String {
        switch period {
        case .day: return "Planned for today"
        case .week: return "Planned this week"
        case .month: return "Planned this month"
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
        let hierarchy = [category] + CategoryHierarchy.ancestors(of: category, in: profileCategories)
        let kind = hierarchy.first(where: { $0.trackingKind != .tasks })?.trackingKind ?? .tasks
        switch kind {
        case .nutrition: return .food
        case .bodyWeight: return .weight
        case .sport: return .sport
        case .tasks: return nil
        }
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
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(summary.completedCount)/\(summary.plannedCount)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(summary.completedCount >= summary.plannedCount ? .green : .blue)
                    Label("Edit", systemImage: "pencil")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                }
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

                Section("Task adherence") {
                    LabeledContent("Status", value: progress.status.rawValue)
                    LabeledContent("Confidence", value: progress.confidence.rawValue)
                    if progress.dueTasks > 0 {
                        LabeledContent("Due Tasks decided") {
                            Text("\(progress.decidedDueTasks) of \(progress.dueTasks)")
                        }
                    }
                }

                Section("What to do next") {
                    Text(progress.nextAction)
                }
            }
            .navigationTitle("\(progress.period.rawValue) Task Progress")
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
    let category: AppCategory
    let activities: [Activity]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allCategories: [AppCategory]
    @Query private var allCalendarItems: [CalendarItem]
    @State private var relatedIDs: Set<UUID>
    @State private var reminderTime: Date
    @State private var parentCategoryID: UUID?
    @State private var showingDeactivateConfirmation = false
    @State private var name: String
    @State private var pillar: ImprovementPillar
    @State private var trackingKind: AreaTrackingKind
    @State private var symbol: String
    @State private var colorToken: String
    @State private var purpose: String
    @State private var weeklyTargetSessions: Int
    @State private var weeklyTargetMinutes: Int
    @State private var reminderEnabled: Bool

    init(category: AppCategory, activities: [Activity]) {
        self.category = category
        self.activities = activities
        _relatedIDs = State(initialValue: Set(category.relatedCategoryIDs))
        _parentCategoryID = State(initialValue: category.parentCategoryID)
        _name = State(initialValue: category.name)
        _pillar = State(initialValue: category.pillar)
        _trackingKind = State(initialValue: category.trackingKind)
        _symbol = State(initialValue: category.symbol)
        _colorToken = State(initialValue: category.colorToken)
        _purpose = State(initialValue: category.purpose)
        _weeklyTargetSessions = State(initialValue: category.weeklyTargetSessions)
        _weeklyTargetMinutes = State(initialValue: category.weeklyTargetMinutes)
        _reminderEnabled = State(initialValue: category.reminderEnabled)
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
                    TextField("Name", text: $name)
                    Picker("Inside", selection: $parentCategoryID) {
                        Text("Top-level area").tag(UUID?.none)
                        ForEach(availableParents) { parent in
                            Text(CategoryHierarchy.breadcrumbName(for: parent, in: allCategories))
                                .tag(UUID?.some(parent.id))
                        }
                    }
                    Picker("Group", selection: $pillar) {
                        ForEach(ImprovementPillar.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Tracking", selection: $trackingKind) {
                        ForEach(AreaTrackingKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    Text(trackingKind.explanation)
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Icon", selection: $symbol) {
                        ForEach(CategoryAppearanceOptions.icons) { option in
                            Label(option.name, systemImage: option.symbol).tag(option.symbol)
                        }
                    }
                    Picker("Colour", selection: $colorToken) {
                        ForEach(CategoryAppearanceOptions.colors, id: \.self) { token in
                            Label(token.capitalized, systemImage: "circle.fill")
                                .foregroundStyle(ColorToken.color(for: token))
                                .tag(token)
                        }
                    }
                    TextField("Purpose", text: $purpose, axis: .vertical)
                }

                Section("Weekly activity plan") {
                    Stepper("\(weeklyTargetSessions) times", value: $weeklyTargetSessions, in: 0...21)
                    Stepper("\(weeklyTargetMinutes) minutes", value: $weeklyTargetMinutes, in: 0...1200, step: 15)
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
                    Toggle("Enable reminders", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker("Weekly review time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        Text("Task reminders use each Task's scheduled days and time.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Area Management") {
                    if category.isActive {
                        Button("Hide Area and Its Tasks", role: .destructive) {
                            showingDeactivateConfirmation = true
                        }
                        Text("Use this for duplicates or areas you no longer want to track. History is kept.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Restore Area and Its Tasks") {
                            category.isActive = true
                            activities.forEach { $0.isActive = true }
                            if modelContext.saveOrReport() {
                                Task { await ReminderService.updateReminders(for: category, activities: activities, center: RealNotificationCenter.shared) }
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Area")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog(
                "Hide \(category.name)?",
                isPresented: $showingDeactivateConfirmation,
                titleVisibility: .visible
            ) {
                Button("Hide Area and Tasks", role: .destructive) {
                    category.isActive = false
                    activities.forEach { $0.isActive = false }
                    activities.flatMap { activity in
                        PlanningService.reconcileUntouchedOccurrences(
                            for: activity, in: allCalendarItems
                        )
                    }.forEach(modelContext.delete)
                    if modelContext.saveOrReport() {
                        Task { await ReminderService.updateReminders(for: category, activities: activities, center: RealNotificationCenter.shared) }
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It will disappear from active areas and stop generating scheduled Tasks. Existing history remains saved.")
            }
        }
    }

    private func save() {
        category.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        category.pillar = pillar
        category.trackingKind = trackingKind
        category.symbol = symbol
        category.colorToken = colorToken
        category.purpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        category.weeklyTargetSessions = weeklyTargetSessions
        category.weeklyTargetMinutes = weeklyTargetMinutes
        category.reminderEnabled = reminderEnabled
        category.parentCategoryID = parentCategoryID
        category.relatedCategoryIDs = Array(relatedIDs)
        category.reminderHour = Calendar.current.component(.hour, from: reminderTime)
        category.reminderMinute = Calendar.current.component(.minute, from: reminderTime)
        if modelContext.saveOrReport() {
            Task { await ReminderService.updateReminders(for: category, activities: activities, center: RealNotificationCenter.shared) }
            dismiss()
        }
    }
}
