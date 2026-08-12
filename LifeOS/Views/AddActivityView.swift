//
//  AddActivityView.swift
//  LifeOS
//
//  DESIGN.md Section 22: fast task creation and flexible recurrence.
//  New activities are configuration, not code (Section 14 architecture rule).
//

import SwiftUI
import SwiftData

struct AddActivityView: View {
    let profile: Profile

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AppCategory.name) private var categories: [AppCategory]
    @Query private var activities: [Activity]

    @State private var name: String = ""
    @State private var selectedCategory: AppCategory?
    @State private var isCreatingCategory = false
    @State private var newCategoryName: String = ""

    @State private var hasTarget: Bool = false
    @State private var showingTrackingOptions = false
    @State private var targetValue: Double = 30
    @State private var targetUnit: String = "min"

    /// Additive, alongside the single target above — Refactor.md Phase 3.
    /// Not a replacement; `targetValue`/`targetUnit` are untouched.
    @State private var measurements: [DraftMeasurement] = []

    @State private var repeatType: RepeatType = .daily
    @State private var selectedWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var occurrencesPerDay: Int = 3
    @State private var occurrencesPerWeek: Int = 3
    @State private var repeatIntervalMinutes: Int = 30
    @State private var plannedStart: Date = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now
    @State private var durationMinutes: Int = 30
    @State private var startDate = Calendar.current.startOfDay(for: .now)
    @State private var hasEndDate = false
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now

    private let weekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var profileCategories: [AppCategory] {
        categories.filter { $0.profile?.id == profile.id && $0.isActive }
    }

    private var hasValidCategory: Bool {
        selectedCategory.map { ProfileScope.canAssign($0, to: profile) } == true
            || (isCreatingCategory && !newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        hasValidCategory &&
        (repeatType != .selectedWeekdays || !selectedWeekdays.isEmpty) &&
        scheduleFitsWithinDay &&
        startDateIsValid &&
        (!hasTarget || !targetUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        (!hasEndDate || endDate >= startDate)
    }

    private var scheduleFitsWithinDay: Bool {
        let calendar = Calendar.current
        let firstStartMinute = calendar.component(.hour, from: plannedStart) * 60 +
            calendar.component(.minute, from: plannedStart)
        return PlanningService.scheduleFitsWithinDay(
            repeatType: repeatType,
            occurrencesPerDay: occurrencesPerDay,
            occurrencesPerWeek: occurrencesPerWeek,
            selectedWeekdayCount: selectedWeekdays.count,
            firstStartMinute: firstStartMinute,
            intervalMinutes: repeatIntervalMinutes
        )
    }

    private var startDateIsValid: Bool {
        let calendar = Calendar.current
        let firstStartMinute = calendar.component(.hour, from: plannedStart) * 60 +
            calendar.component(.minute, from: plannedStart)
        return PlanningService.startDateIsValid(
            repeatType: repeatType,
            startDate: startDate,
            firstStartMinute: firstStartMinute,
            calendar: calendar
        )
    }

    init(profile: Profile, initialCategory: AppCategory? = nil) {
        self.profile = profile
        _selectedCategory = State(initialValue:
            initialCategory?.profile?.id == profile.id && initialCategory?.isActive == true ? initialCategory : nil
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("1. What will you do?") {
                    TextField("What do you want to do?", text: $name)
                    Text("Examples: Batting practice, homework, walk, study Swift")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("2. What does this improve?") {
                    if isCreatingCategory {
                        TextField("New area name, e.g. Speed", text: $newCategoryName)
                        Text("This creates a simple top-level area. You can organise it later if needed.")
                            .font(.caption).foregroundStyle(.secondary)
                        if !profileCategories.isEmpty {
                            Button("Choose an existing area") { isCreatingCategory = false }
                                .font(.caption)
                        }
                    } else {
                        Picker("Area", selection: $selectedCategory) {
                            Text("Choose an area").tag(AppCategory?.none)
                            ForEach(profileCategories) { category in
                                Text(CategoryHierarchy.breadcrumbName(for: category, in: profileCategories))
                                    .tag(AppCategory?.some(category))
                            }
                        }
                        Button {
                            isCreatingCategory = true
                            selectedCategory = nil
                        } label: {
                            Label("Create a new area here", systemImage: "plus.circle.fill")
                        }
                    }
                    Text("An area is simply something you care about improving, such as Baseball, School or Health.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    DisclosureGroup("Track a number (optional)", isExpanded: $showingTrackingOptions) {
                        Toggle("Set a target", isOn: $hasTarget)
                        if hasTarget {
                            LabeledContent("Target") {
                                HStack(spacing: 8) {
                                    TextField("30", value: $targetValue, format: .number)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .frame(maxWidth: 90)
                                    TextField("min", text: $targetUnit)
                                        .multilineTextAlignment(.trailing)
                                        .frame(maxWidth: 90)
                                }
                            }
                            Text("Examples: 30 minutes, 100 swings, 20 pages or 8,000 steps.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Measurements (optional)") {
                    ForEach($measurements) { $measurement in
                        measurementRow($measurement)
                    }
                    Button {
                        measurements.append(DraftMeasurement())
                    } label: {
                        Label("Add Measurement", systemImage: "plus.circle.fill")
                    }
                    if !measurements.isEmpty {
                        Text("Each measurement is tracked separately when you log this Task — e.g. Ground Balls 100, Catches 50, Throws 30.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("3. When should it happen?") {
                    Picker("Repeat", selection: $repeatType) {
                        ForEach(RepeatType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    if repeatType == .timesPerDay {
                        integerEntry("Times each day", value: $occurrencesPerDay, range: 1...99)
                        integerEntry("Minutes between", value: $repeatIntervalMinutes, range: 1...1439)
                    }

                    if repeatType == .timesPerWeek {
                        integerEntry("Times each week", value: $occurrencesPerWeek, range: 1...99)
                    }

                    if repeatType == .selectedWeekdays || repeatType == .timesPerWeek {
                        Text(repeatType == .timesPerWeek ? "Preferred days" : "Days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        weekdayPicker
                    }

                    if repeatType == .timesPerWeek && occurrencesPerWeek > max(1, selectedWeekdays.count) {
                        integerEntry("Minutes between repetitions", value: $repeatIntervalMinutes, range: 1...1439)
                    }

                    DatePicker(
                        repeatType == .once ? "Date" : "Start date",
                        selection: $startDate,
                        in: Calendar.current.startOfDay(for: .now)...,
                        displayedComponents: .date
                    )
                    if repeatType != .once {
                        Toggle("Set an end date", isOn: $hasEndDate)
                        if hasEndDate {
                            DatePicker("End date", selection: $endDate, in: startDate..., displayedComponents: .date)
                        }
                    }
                    DatePicker(repeatType == .timesPerDay ? "First start time" : "Start time", selection: $plannedStart, displayedComponents: .hourAndMinute)
                    integerEntry("Duration in minutes", value: $durationMinutes, range: 1...1440)

                    if !scheduleFitsWithinDay {
                        Label("The requested repetitions run past midnight. Choose an earlier time, shorter interval, or fewer repetitions.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if !startDateIsValid {
                        Label("Choose a future date and time for this one-time Task.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Label(scheduleSummary, systemImage: "calendar.badge.clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if profileCategories.isEmpty {
                    isCreatingCategory = true
                }
            }
        }
    }

    private func integerEntry(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Button {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.plain)

                TextField("", value: value, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 58)

                Button {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Sensible default units per measurement type, so most measurements
    /// never require typing a unit at all.
    private static let suggestedUnit: [MeasurementType: String] = [
        .duration: "min", .distance: "m", .percentage: "%"
    ]

    private func measurementRow(_ measurement: Binding<DraftMeasurement>) -> some View {
        VStack(alignment: .leading, spacing: LifeOSSpacing.sm) {
            HStack {
                TextField("Name, e.g. Ground Balls", text: measurement.name)
                Button(role: .destructive) {
                    measurements.removeAll { $0.id == measurement.wrappedValue.id }
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove measurement")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LifeOSSpacing.sm) {
                    ForEach(MeasurementType.allCases.filter { $0 != .custom }) { type in
                        LOChip(title: type.rawValue.capitalized, isSelected: measurement.wrappedValue.type == type) {
                            measurement.wrappedValue.type = type
                            if measurement.wrappedValue.unit.isEmpty, let suggestion = Self.suggestedUnit[type] {
                                measurement.wrappedValue.unit = suggestion
                            }
                        }
                    }
                }
            }
            if measurement.wrappedValue.type != .text {
                HStack(spacing: 8) {
                    TextField("Target (optional)", value: measurement.targetValue, format: .number)
                        .keyboardType(.decimalPad)
                    TextField("Unit", text: measurement.unit)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var weekdayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LifeOSSpacing.sm) {
                ForEach(1...7, id: \.self) { day in
                    LOChip(
                        title: weekdaySymbols[day - 1],
                        isSelected: selectedWeekdays.contains(day)
                    ) {
                        if selectedWeekdays.contains(day) {
                            selectedWeekdays.remove(day)
                        } else {
                            selectedWeekdays.insert(day)
                        }
                    }
                }
            }
        }
    }

    private var scheduleSummary: String {
        switch repeatType {
        case .once:
            return "One Task at \(formattedStartTime)."
        case .daily:
            return "Every day at \(formattedStartTime)."
        case .selectedWeekdays:
            return "\(selectedWeekdays.count) selected day\(selectedWeekdays.count == 1 ? "" : "s") each week at \(formattedStartTime)."
        case .timesPerDay:
            let count = max(1, occurrencesPerDay)
            return "\(count) time\(count == 1 ? "" : "s") per day, starting \(formattedStartTime), exactly \(max(1, repeatIntervalMinutes)) min apart."
        case .timesPerWeek:
            let count = max(1, occurrencesPerWeek)
            return "\(count) time\(count == 1 ? "" : "s") per week across your preferred days."
        }
    }

    private var formattedStartTime: String {
        plannedStart.formatted(date: .omitted, time: .shortened)
    }

    private func save() {
        var category = selectedCategory
        if isCreatingCategory, !newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty {
            let newCategory = AppCategory(
                profile: profile, name: newCategoryName,
                symbol: "target", colorToken: "blue",
                purpose: "Improve through consistent, measurable Task."
            )
            modelContext.insert(newCategory)
            category = newCategory
        }

        let calendar = Calendar.current
        let minutesSinceMidnight = calendar.component(.hour, from: plannedStart) * 60 + calendar.component(.minute, from: plannedStart)

        let activity = Activity(
            profile: profile,
            category: category,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .manual,
            targetValue: hasTarget ? targetValue : nil,
            targetUnit: hasTarget ? targetUnit : nil,
            repeatType: repeatType,
            weekdays: Array(selectedWeekdays),
            occurrencesPerDay: max(1, occurrencesPerDay),
            occurrencesPerWeek: max(1, occurrencesPerWeek),
            repeatIntervalMinutes: max(1, repeatIntervalMinutes),
            plannedStartMinutes: minutesSinceMidnight,
            estimatedDurationMinutes: max(1, durationMinutes),
            startDate: startDate,
            endDate: repeatType != .once && hasEndDate ? endDate : nil
        )
        modelContext.insert(activity)

        let definitions = measurements
            .enumerated()
            .compactMap { index, draft -> MeasurementDefinition? in
                let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { return nil }
                let trimmedUnit = draft.unit.trimmingCharacters(in: .whitespacesAndNewlines)
                return MeasurementDefinition(
                    activity: activity, name: trimmedName, type: draft.type,
                    unit: trimmedUnit.isEmpty ? nil : trimmedUnit,
                    targetValue: draft.targetValue, sortOrder: index
                )
            }
        definitions.forEach(modelContext.insert)

        // Generate today's calendar item immediately if this activity is
        // scheduled today, so it shows up on Today without waiting for the
        // next app-open regeneration pass.
        let newItems: [CalendarItem]
        do {
            newItems = try PlanningService.insertMissingCalendarItems(
                profile: profile, date: .now, activities: [activity], context: modelContext
            )
        } catch {
            PersistenceIssueCenter.shared.report(error)
            definitions.forEach(modelContext.delete)
            modelContext.delete(activity)
            if let category, isCreatingCategory { modelContext.delete(category) }
            return
        }

        if modelContext.saveOrReport() {
            refreshReminders(afterAdding: activity, to: category)
            dismiss()
        } else {
            newItems.forEach { modelContext.delete($0) }
            definitions.forEach(modelContext.delete)
            modelContext.delete(activity)
            if let category, isCreatingCategory { modelContext.delete(category) }
        }
    }

    /// A parent Area's reminder setting applies to Actions inside its Focus Areas too.
    /// Refresh every enabled Area that contains the new Action so the notification
    /// is ready immediately, without requiring the user to edit and save the Area.
    private func refreshReminders(afterAdding activity: Activity, to category: AppCategory?) {
        guard let category else { return }
        let profileCategories = categories.filter { $0.profile?.id == profile.id && $0.isActive }
        let reminderAreas = ([category] + CategoryHierarchy.ancestors(of: category, in: profileCategories))
            .filter { $0.reminderEnabled && $0.isActive }
        guard !reminderAreas.isEmpty else { return }

        let profileActivities = activities.filter { $0.profile?.id == profile.id && $0.id != activity.id } + [activity]
        Task {
            for reminderArea in reminderAreas {
                let includedIDs = CategoryHierarchy.idsIncludingDescendants(of: reminderArea, in: profileCategories)
                let reminderActivities = profileActivities.filter {
                    $0.category.map { includedIDs.contains($0.id) } == true
                }
                await ReminderService.updateReminders(for: reminderArea, activities: reminderActivities)
            }
        }
    }
}

/// Unsaved measurement, edited in the form before the Activity exists.
/// Turned into a MeasurementDefinition only on save (Refactor.md Phase 3).
private struct DraftMeasurement: Identifiable {
    let id = UUID()
    var name: String = ""
    var type: MeasurementType = .count
    var unit: String = ""
    var targetValue: Double?
}

#Preview {
    let profile = Profile(name: "Sirish", kind: .parent, colorToken: "blue")
    AddActivityView(profile: profile)
        .modelContainer(for: [Profile.self, SavedCategoryTemplate.self, AppCategory.self, Goal.self, GoalAreaContribution.self, ResultMeasure.self, ResultEntry.self, Activity.self, CalendarItem.self, ActivitySession.self, FoodEntry.self, WeightEntry.self, SportEntry.self, Relationship.self, MeasurementDefinition.self, MeasurementEntry.self], inMemory: true)
}
