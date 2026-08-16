import SwiftData
import SwiftUI

struct EditTaskView: View {
    let activity: Activity
    /// Called after a true delete (not archive) so a presenter holding a
    /// direct reference to this Activity — or to one of its CalendarItems,
    /// which a no-history delete also removes — can dismiss itself too.
    /// Without this, the presenter re-renders a deleted SwiftData object as
    /// a blank "Task" row instead of closing.
    var onActivityDeleted: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AppCategory.name) private var categories: [AppCategory]
    @Query private var allActivities: [Activity]
    @Query private var allCalendarItems: [CalendarItem]
    @Query private var allMeasurementDefinitions: [MeasurementDefinition]

    @State private var name: String
    @State private var categoryID: UUID?
    @State private var hasTarget: Bool
    @State private var targetValue: Double
    @State private var targetUnit: String
    @State private var repeatType: RepeatType
    @State private var weekdays: Set<Int>
    @State private var occurrencesPerDay: Int
    @State private var occurrencesPerWeek: Int
    @State private var repeatIntervalMinutes: Int
    @State private var plannedStart: Date
    @State private var durationMinutes: Int
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var isActive: Bool
    @State private var showingDeleteConfirmation = false

    /// Additive, alongside targetValue/targetUnit above — Refactor.md
    /// Phase 3. Add/delete act immediately (their own save), matching the
    /// Task Management section's pattern below, rather than deferring to
    /// the main Save button.
    @State private var newMeasurementName = ""
    @State private var newMeasurementType: MeasurementType = .count
    @State private var newMeasurementUnit = ""
    @State private var newMeasurementTarget: Double?

    private let weekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    init(activity: Activity, onActivityDeleted: @escaping () -> Void = {}) {
        self.activity = activity
        self.onActivityDeleted = onActivityDeleted
        _name = State(initialValue: activity.name)
        _categoryID = State(initialValue: activity.category?.id)
        _hasTarget = State(initialValue: activity.targetValue != nil)
        _targetValue = State(initialValue: activity.targetValue ?? 30)
        _targetUnit = State(initialValue: activity.targetUnit ?? "min")
        _repeatType = State(initialValue: activity.repeatType)
        _weekdays = State(initialValue: Set(activity.weekdays))
        _occurrencesPerDay = State(initialValue: activity.occurrencesPerDay)
        _occurrencesPerWeek = State(initialValue: activity.occurrencesPerWeek)
        _repeatIntervalMinutes = State(initialValue: activity.repeatIntervalMinutes)
        let start = Calendar.current.date(
            byAdding: .minute, value: activity.plannedStartMinutes,
            to: Calendar.current.startOfDay(for: .now)
        ) ?? .now
        _plannedStart = State(initialValue: start)
        _durationMinutes = State(initialValue: activity.estimatedDurationMinutes)
        _startDate = State(initialValue: activity.startDate)
        _hasEndDate = State(initialValue: activity.endDate != nil)
        _endDate = State(initialValue: activity.endDate ?? Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now)
        _isActive = State(initialValue: activity.isActive)
    }

    private var profileCategories: [AppCategory] {
        guard let profile = activity.profile else { return [] }
        return ProfileScope.categories(for: profile, from: categories).sorted { $0.name < $1.name }
    }

    private var firstStartMinute: Int {
        Calendar.current.component(.hour, from: plannedStart) * 60
            + Calendar.current.component(.minute, from: plannedStart)
    }

    private var hasHistory: Bool {
        PlanningService.hasAnyHistory(for: activity, in: allCalendarItems)
    }

    private var measurementDefinitions: [MeasurementDefinition] {
        allMeasurementDefinitions
            .filter { $0.activity?.id == activity.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && categoryID.flatMap { id in profileCategories.first(where: { $0.id == id }) } != nil
            && (!hasTarget || (!targetUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && targetValue >= 0))
            && durationMinutes > 0 && occurrencesPerDay > 0 && occurrencesPerWeek > 0
            && repeatIntervalMinutes > 0
            && (repeatType != .selectedWeekdays || !weekdays.isEmpty)
            && PlanningService.scheduleFitsWithinDay(
                repeatType: repeatType,
                occurrencesPerDay: occurrencesPerDay,
                occurrencesPerWeek: occurrencesPerWeek,
                selectedWeekdayCount: weekdays.count,
                firstStartMinute: firstStartMinute,
                intervalMinutes: repeatIntervalMinutes
            )
            && (!hasEndDate || endDate >= startDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("task.name")
                    Picker("Plan", selection: $categoryID) {
                        Text("Choose a Plan").tag(UUID?.none)
                        ForEach(profileCategories) { area in
                            Text(CategoryHierarchy.breadcrumbName(for: area, in: profileCategories))
                                .tag(UUID?.some(area.id))
                        }
                    }
                    Toggle("Active", isOn: $isActive)
                    Text(isActive ? "This Task can appear in the schedule." : "Archived Tasks keep their history but stop appearing in future schedules.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Number to track (optional)") {
                    Toggle("Track a number", isOn: $hasTarget)
                    if hasTarget {
                        TextField("Target", value: $targetValue, format: .number)
                            .keyboardType(.decimalPad)
                        TextField("Unit, e.g. min or swings", text: $targetUnit)
                    }
                }

                Section("Measurements (optional)") {
                    if !measurementDefinitions.isEmpty {
                        ForEach(measurementDefinitions) { definition in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(definition.name).font(.subheadline)
                                    Text(definition.type.rawValue.capitalized + (definition.unit.map { " · \($0)" } ?? ""))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let target = definition.targetValue {
                                    Text(target.formatted(.number.precision(.fractionLength(0...2))))
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                        .onDelete(perform: deleteMeasurementDefinitions)
                    }
                    TextField("Name, e.g. Ground Balls", text: $newMeasurementName)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: LifeOSSpacing.sm) {
                            ForEach(MeasurementType.allCases.filter { $0 != .custom }) { type in
                                LOChip(title: type.rawValue.capitalized, isSelected: newMeasurementType == type) {
                                    newMeasurementType = type
                                }
                            }
                        }
                    }
                    if newMeasurementType != .text {
                        HStack(spacing: 8) {
                            TextField("Target (optional)", value: $newMeasurementTarget, format: .number)
                                .keyboardType(.decimalPad)
                            TextField("Unit", text: $newMeasurementUnit)
                        }
                    }
                    Button {
                        addMeasurement()
                    } label: {
                        Label("Add Measurement", systemImage: "plus.circle.fill")
                    }
                    .disabled(newMeasurementName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !measurementDefinitions.isEmpty {
                        Text("Each measurement is tracked separately — e.g. Ground Balls 100, Catches 50, Throws 30.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Schedule") {
                    Picker("Repeat", selection: $repeatType) {
                        ForEach(RepeatType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if repeatType == .timesPerDay {
                        numberField("Times each day", value: $occurrencesPerDay, range: 1...99)
                        numberField("Minutes between", value: $repeatIntervalMinutes, range: 1...1439)
                    }
                    if repeatType == .timesPerWeek {
                        numberField("Times each week", value: $occurrencesPerWeek, range: 1...99)
                    }
                    if repeatType == .selectedWeekdays || repeatType == .timesPerWeek {
                        weekdayPicker
                    }
                    DatePicker(repeatType == .once ? "Date" : "Start date", selection: $startDate, displayedComponents: .date)
                        .accessibilityIdentifier("task.startDate")
                    if repeatType != .once {
                        Toggle("Set an end date", isOn: $hasEndDate)
                        if hasEndDate {
                            DatePicker("End date", selection: $endDate, in: startDate..., displayedComponents: .date)
                        }
                    }
                    DatePicker("Start time", selection: $plannedStart, displayedComponents: .hourAndMinute)
                    numberField("Duration in minutes", value: $durationMinutes, range: 1...1440)
                        .accessibilityIdentifier("task.duration")
                }

                Section("Task Management") {
                    Button(hasHistory ? "Archive Task" : "Delete Task", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                    .accessibilityIdentifier("task.delete")
                    Text(hasHistory
                        ? "This Task has history, so it will be archived instead of deleted. It keeps its history but stops appearing in future schedules."
                        : "This Task has no history yet, so it can be safely deleted.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("task.save")
                }
            }
            .confirmationDialog(
                hasHistory ? "Archive \(activity.name)?" : "Delete \(activity.name)?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(hasHistory ? "Archive Task" : "Delete Task", role: .destructive, action: deleteOrArchive)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(hasHistory
                    ? "Existing history remains saved. The Task stops appearing in future schedules."
                    : "This Task has no recorded history, so this permanently removes it.")
            }
        }
    }

    private func addMeasurement() {
        let trimmedName = newMeasurementName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let trimmedUnit = newMeasurementUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        let definition = MeasurementDefinition(
            activity: activity, name: trimmedName, type: newMeasurementType,
            unit: trimmedUnit.isEmpty ? nil : trimmedUnit,
            targetValue: newMeasurementTarget, sortOrder: measurementDefinitions.count
        )
        modelContext.insert(definition)
        if modelContext.saveOrReport() {
            newMeasurementName = ""
            newMeasurementUnit = ""
            newMeasurementTarget = nil
            newMeasurementType = .count
        } else {
            modelContext.delete(definition)
        }
    }

    private func deleteMeasurementDefinitions(at offsets: IndexSet) {
        offsets.map { measurementDefinitions[$0] }.forEach(modelContext.delete)
        modelContext.saveOrReport()
    }

    /// Deletes an Activity outright only when it has never produced a real
    /// record; otherwise archives it (mirrors the Area "Hide" flow) so
    /// history is never silently discarded. See DESIGN.md §4.
    private func deleteOrArchive() {
        let category = activity.category
        let historyExists = hasHistory

        if historyExists {
            activity.isActive = false
            PlanningService.reconcileUntouchedOccurrences(
                for: activity, in: allCalendarItems
            ).forEach(modelContext.delete)
        } else {
            allCalendarItems
                .filter { $0.activity?.id == activity.id }
                .forEach(modelContext.delete)
            modelContext.delete(activity)
        }

        guard modelContext.saveOrReport() else { return }
        if let category {
            let remainingActivities = allActivities.filter {
                $0.category?.id == category.id && (historyExists || $0.id != activity.id)
            }
            let deletedActivityID = activity.id
            Task {
                // A hard-deleted (no-history) Activity is excluded from
                // remainingActivities above, so updateReminders' own
                // cancellation pass would never see its identifier prefix —
                // cancel it explicitly first so its reminders don't outlive it.
                if !historyExists {
                    await ReminderService.cancelAllReminders(activityID: deletedActivityID, center: RealNotificationCenter.shared)
                }
                await ReminderService.updateReminders(for: category, activities: remainingActivities, center: RealNotificationCenter.shared)
            }
        }
        if !historyExists { onActivityDeleted() }
        dismiss()
    }

    private func numberField(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Button {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Decrease \(title)")

                TextField("", value: value, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 58)
                    .accessibilityLabel(title)

                Button {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Increase \(title)")
            }
        }
    }

    private var weekdayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LifeOSSpacing.sm) {
            ForEach(1...7, id: \.self) { day in
                LOChip(title: weekdaySymbols[day - 1], isSelected: weekdays.contains(day)) {
                    if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                }
            }
            }
        }
    }

    private func save() {
        guard canSave,
              let categoryID,
              let category = profileCategories.first(where: { $0.id == categoryID }) else { return }

        activity.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        activity.category = category
        activity.targetValue = hasTarget ? targetValue : nil
        activity.targetUnit = hasTarget ? targetUnit.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        activity.repeatType = repeatType
        activity.weekdays = Array(weekdays).sorted()
        activity.occurrencesPerDay = max(occurrencesPerDay, 1)
        activity.occurrencesPerWeek = max(occurrencesPerWeek, 1)
        activity.repeatIntervalMinutes = max(repeatIntervalMinutes, 1)
        activity.plannedStartMinutes = firstStartMinute
        activity.estimatedDurationMinutes = max(durationMinutes, 1)
        activity.startDate = startDate
        activity.endDate = repeatType == .once || !hasEndDate ? nil : endDate
        activity.isActive = isActive

        let staleItems = PlanningService.reconcileUntouchedOccurrences(
            for: activity, in: allCalendarItems
        )
        staleItems.forEach(modelContext.delete)

        do {
            let hasTodayHistory = PlanningService.hasHistory(
                for: activity, on: .now, in: allCalendarItems
            )
            if let profile = activity.profile, !hasTodayHistory {
                try PlanningService.insertMissingCalendarItems(
                    profile: profile, date: .now,
                    activities: [activity], context: modelContext
                )
            }
        } catch {
            modelContext.rollback()
            PersistenceIssueCenter.shared.report(error)
            return
        }

        if modelContext.saveOrReport() {
            let areaActivities = allActivities.filter { $0.category?.id == category.id }
            Task {
                await ReminderService.updateReminders(
                    for: category,
                    activities: areaActivities,
                    center: RealNotificationCenter.shared
                )
            }
            dismiss()
        } else {
            modelContext.rollback()
        }
    }
}

struct ManageAreaTasksView: View {
    let category: AppCategory
    let profileCategories: [AppCategory]

    @Environment(\.dismiss) private var dismiss
    @Query private var activities: [Activity]
    @State private var editingTask: Activity?

    private var areaTasks: [Activity] {
        let ids = CategoryHierarchy.idsIncludingDescendants(of: category, in: profileCategories)
        return activities.filter {
            $0.profile?.id == category.profile?.id && $0.category.map { ids.contains($0.id) } == true
        }
        .sorted {
            if $0.isActive != $1.isActive { return $0.isActive && !$1.isActive }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if areaTasks.isEmpty {
                    ContentUnavailableView("No Tasks", systemImage: "checklist", description: Text("Add a Task from the Area screen."))
                } else {
                    ForEach(areaTasks) { task in
                        Button { editingTask = task } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.name).foregroundStyle(.primary)
                                    Text(task.isActive ? task.repeatType.rawValue : "Archived")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Manage Tasks")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editingTask) { TaskDetailView(activity: $0) }
        }
    }
}

#if DEBUG
/// Screenshot-only: which exceptional occurrence action to perform
/// automatically on appear, without simulator tap automation.
enum DebugTaskDetailAutoAction {
    case reschedule, skip
}
#endif

struct TaskDetailView: View {
    let activity: Activity
    #if DEBUG
    var debugAutoAction: DebugTaskDetailAutoAction? = nil
    #endif

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var calendarItems: [CalendarItem]
    @Query private var contributions: [GoalAreaContribution]
    @State private var showingEdit = false
    @State private var historyPeriod: DashboardPeriod = .week
    @State private var showingReschedule = false
    @State private var rescheduleDate: Date = .now
    @State private var occurrenceActionFailed = false

    private var linkedGoals: [Goal] {
        guard let categoryID = activity.category?.id else { return [] }
        var seen = Set<UUID>()
        return contributions.compactMap { contribution in
            guard contribution.isActive,
                  contribution.category?.id == categoryID,
                  let goal = contribution.goal,
                  goal.isActive,
                  seen.insert(goal.id).inserted else { return nil }
            return goal
        }
    }

    /// The single next actionable occurrence for this exact Activity,
    /// resolved by CalendarItem identity (never by Task name, time, or
    /// profile name) — the only occurrence Skip/Reschedule below can act on.
    private var nextOccurrence: CalendarItem? {
        calendarItems
            .filter { $0.activity?.id == activity.id && $0.status == .planned }
            .sorted { ($0.plannedStart ?? $0.date) < ($1.plannedStart ?? $1.date) }
            .first
    }

    private var history: [CalendarItem] {
        calendarItems.filter { $0.activity?.id == activity.id }
            .sorted { ($0.plannedStart ?? $0.date) > ($1.plannedStart ?? $1.date) }
    }

    private var periodHistory: [CalendarItem] {
        let interval = historyPeriod.interval(containing: .now)
        return history.filter { interval.contains($0.date) }
    }

    private var completedMinutes: Int {
        periodHistory.filter { $0.status == .done }.reduce(0) { total, item in
            if let start = item.actualStart, let end = item.actualEnd {
                return total + max(Int(end.timeIntervalSince(start) / 60), 0)
            }
            return total + (item.activity?.estimatedDurationMinutes ?? 0)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(activity.category?.name ?? "Plan", systemImage: activity.category?.symbol ?? "list.bullet.clipboard")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(activity.category.map { ColorToken.color(for: $0.colorToken) } ?? .blue)
                        Text(activity.name).font(.lifeOSScreenTitle)
                        Text(activity.isActive ? "Active Task" : "Archived Task")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(activity.isActive ? Color.lifeOSOnTrack : .secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("Task details") {
                    detail("Plan", activity.category?.name ?? "Not assigned")
                    detail("Duration", "\(activity.estimatedDurationMinutes) minutes")
                    detail("Start time", formattedTime)
                    detail("Repeats", repeatDescription)
                    detail("Starts", activity.startDate.formatted(date: .abbreviated, time: .omitted))
                    if let endDate = activity.endDate {
                        detail("Ends", endDate.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let target = activity.targetValue {
                        detail("Target", "\(target.formatted(.number.precision(.fractionLength(0...2)))) \(activity.targetUnit ?? "")")
                    } else {
                        detail("Target", "Completion only")
                    }
                }

                if let nextOccurrence {
                    Section("Next Occurrence") {
                        detail("Date", nextOccurrence.date.formatted(date: .abbreviated, time: .omitted))
                        detail("Time", nextOccurrence.plannedStart?.formatted(date: .omitted, time: .shortened) ?? "Any time")
                        HStack(spacing: LifeOSSpacing.sm) {
                            Button {
                                rescheduleDate = nextOccurrence.plannedStart ?? nextOccurrence.date
                                showingReschedule = true
                            } label: {
                                Label("Reschedule", systemImage: "calendar.badge.clock")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(LifeOSSecondaryButtonStyle())
                            .accessibilityIdentifier("task.detail.reschedule")

                            Button(role: .destructive) {
                                skip(nextOccurrence)
                            } label: {
                                Label("Skip", systemImage: "forward.end")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(LifeOSSecondaryButtonStyle())
                            .accessibilityIdentifier("task.detail.skip")
                        }
                    }
                }

                Section("Supports") {
                    if linkedGoals.isEmpty {
                        Text("No Progress Goal connected through this Plan.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(linkedGoals) { goal in
                            Label(goal.name, systemImage: "scope")
                        }
                    }
                }

                Section("History") {
                    Picker("History period", selection: $historyPeriod) {
                        ForEach(DashboardPeriod.allCases) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("Completed") {
                        Text("\(periodHistory.filter { $0.status == .done }.count) of \(periodHistory.count)")
                            .fontWeight(.semibold).monospacedDigit()
                    }
                    LabeledContent("Time completed") {
                        Text("\(completedMinutes) min").fontWeight(.semibold).monospacedDigit()
                    }

                    if periodHistory.isEmpty {
                        Text("No occurrences recorded yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(periodHistory.prefix(10)) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.date.formatted(date: .abbreviated, time: .omitted))
                                    Text(item.plannedStart?.formatted(date: .omitted, time: .shortened) ?? "Any time")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.status.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(statusColor(item.status))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.inline)
            #if DEBUG
            .onAppear {
                guard let nextOccurrence, let debugAutoAction else { return }
                switch debugAutoAction {
                case .reschedule:
                    rescheduleDate = nextOccurrence.plannedStart ?? nextOccurrence.date
                    showingReschedule = true
                case .skip:
                    skip(nextOccurrence)
                }
            }
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingEdit = true } label: {
                        Label("Edit Task", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("task.edit")
                    .accessibilityHint("Edit the Task name, Plan, target, schedule, time, and duration")
                }
            }
            .sheet(isPresented: $showingEdit) {
                EditTaskView(activity: activity, onActivityDeleted: { dismiss() })
            }
            .sheet(isPresented: $showingReschedule) {
                if let nextOccurrence {
                    RescheduleOccurrenceSheet(date: rescheduleDate) { newDate in
                        reschedule(nextOccurrence, to: newDate)
                        showingReschedule = false
                    }
                }
            }
            .alert("Couldn't Update This Occurrence", isPresented: $occurrenceActionFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please try again.")
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
    }

    private func skip(_ item: CalendarItem) {
        if !TaskOccurrenceActions.skip(item, context: modelContext) {
            occurrenceActionFailed = true
        }
    }

    private func reschedule(_ item: CalendarItem, to newDate: Date) {
        if TaskOccurrenceActions.reschedule(item, activity: activity, to: newDate, context: modelContext) == nil {
            occurrenceActionFailed = true
        }
    }

    private var formattedTime: String {
        let hour = activity.plannedStartMinutes / 60
        let minute = activity.plannedStartMinutes % 60
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now)?
            .formatted(date: .omitted, time: .shortened) ?? "Any time"
    }

    private var repeatDescription: String {
        switch activity.repeatType {
        case .once: return "Once"
        case .daily: return "Every day"
        case .selectedWeekdays: return weekdayNames
        case .timesPerDay: return "\(activity.occurrencesPerDay) times daily, \(activity.repeatIntervalMinutes) minutes apart"
        case .timesPerWeek: return "\(activity.occurrencesPerWeek) times weekly · \(weekdayNames)"
        }
    }

    private var weekdayNames: String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return activity.weekdays.sorted().compactMap { day in
            symbols.indices.contains(day - 1) ? symbols[day - 1] : nil
        }.joined(separator: ", ")
    }

    private func statusColor(_ status: CalendarItemStatus) -> Color {
        switch status {
        case .done: return .lifeOSOnTrack
        case .inProgress: return .lifeOSFocus
        case .skipped: return .lifeOSNeutral
        case .rescheduled: return .lifeOSWatch
        case .unplanned: return .lifeOSRecovery
        case .planned: return .lifeOSNeutral
        }
    }
}

/// A minimal date/time picker for moving one specific occurrence.
private struct RescheduleOccurrenceSheet: View {
    @State var date: Date
    let onConfirm: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("New date & time", selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
            }
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") { onConfirm(date) }
                        .accessibilityIdentifier("task.detail.reschedule.confirm")
                }
            }
        }
    }
}
