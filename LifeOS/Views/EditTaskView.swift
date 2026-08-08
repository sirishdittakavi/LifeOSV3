import SwiftData
import SwiftUI

struct EditTaskView: View {
    let activity: Activity

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AppCategory.name) private var categories: [AppCategory]
    @Query private var allActivities: [Activity]

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

    private let weekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    init(activity: Activity) {
        self.activity = activity
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
                    Picker("Area", selection: $categoryID) {
                        Text("Choose an Area").tag(UUID?.none)
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

                Section("Schedule") {
                    Picker("Repeat", selection: $repeatType) {
                        ForEach(RepeatType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if repeatType == .timesPerDay {
                        numberField("Times each day", value: $occurrencesPerDay)
                        numberField("Minutes between", value: $repeatIntervalMinutes)
                    }
                    if repeatType == .timesPerWeek {
                        numberField("Times each week", value: $occurrencesPerWeek)
                    }
                    if repeatType == .selectedWeekdays || repeatType == .timesPerWeek {
                        weekdayPicker
                    }
                    DatePicker(repeatType == .once ? "Date" : "Start date", selection: $startDate, displayedComponents: .date)
                    if repeatType != .once {
                        Toggle("Set an end date", isOn: $hasEndDate)
                        if hasEndDate {
                            DatePicker("End date", selection: $endDate, in: startDate..., displayedComponents: .date)
                        }
                    }
                    DatePicker("Start time", selection: $plannedStart, displayedComponents: .hourAndMinute)
                    numberField("Duration in minutes", value: $durationMinutes)
                }
            }
            .navigationTitle("Edit Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
        }
    }

    private func numberField(_ title: String, value: Binding<Int>) -> some View {
        TextField(title, value: value, format: .number)
            .keyboardType(.numberPad)
    }

    private var weekdayPicker: some View {
        HStack {
            ForEach(1...7, id: \.self) { day in
                Button {
                    if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                } label: {
                    Text(weekdaySymbols[day - 1])
                        .font(.caption2)
                        .frame(width: 32, height: 32)
                        .background(weekdays.contains(day) ? Color.blue : Color(.tertiarySystemFill))
                        .foregroundStyle(weekdays.contains(day) ? .white : .primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
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

        if modelContext.saveOrReport() {
            let areaActivities = allActivities.filter { $0.category?.id == category.id }
            Task {
                await ReminderService.updateReminders(
                    for: category,
                    activities: areaActivities
                )
            }
            dismiss()
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
            .sheet(item: $editingTask) { EditTaskView(activity: $0) }
        }
    }
}
