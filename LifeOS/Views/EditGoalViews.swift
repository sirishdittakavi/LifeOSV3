import SwiftData
import SwiftUI

struct EditGoalView: View {
    let goal: Goal

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [AppCategory]
    @Query private var contributions: [GoalAreaContribution]
    @Query private var measures: [ResultMeasure]

    @State private var name: String
    @State private var purpose: String
    @State private var hasTargetDate: Bool
    @State private var targetDate: Date
    @State private var selectedAreaIDs: Set<UUID>
    @State private var isActive: Bool

    init(goal: Goal) {
        self.goal = goal
        _name = State(initialValue: goal.name)
        _purpose = State(initialValue: goal.purpose)
        _hasTargetDate = State(initialValue: goal.targetDate != nil)
        _targetDate = State(initialValue: goal.targetDate ?? Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now)
        _selectedAreaIDs = State(initialValue: [])
        _isActive = State(initialValue: goal.isActive)
    }

    private var profileAreas: [AppCategory] {
        guard let profile = goal.profile else { return [] }
        return ProfileScope.categories(for: profile, from: categories).sorted { $0.name < $1.name }
    }

    private var goalContributions: [GoalAreaContribution] {
        contributions.filter { $0.goal?.id == goal.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("Name", text: $name)
                    TextField("Why it matters", text: $purpose, axis: .vertical)
                    Toggle("Set a target date", isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker("Target date", selection: $targetDate, displayedComponents: .date)
                    }
                    Toggle("Active", isOn: $isActive)
                    Text(isActive ? "This Goal appears in your active Goals list." : "Archiving keeps every Result and Task record but hides this Goal from active progress.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Supporting Plans") {
                    ForEach(profileAreas) { area in
                        Button {
                            if selectedAreaIDs.contains(area.id) { selectedAreaIDs.remove(area.id) }
                            else { selectedAreaIDs.insert(area.id) }
                        } label: {
                            HStack {
                                Label(area.name, systemImage: area.symbol)
                                Spacer()
                                if selectedAreaIDs.contains(area.id) { Image(systemName: "checkmark.circle.fill") }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    Text("At least one Plan is required while a Goal is active.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Goal")
            .onAppear {
                selectedAreaIDs = Set(goalContributions.filter(\.isActive).compactMap { $0.category?.id })
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (isActive && selectedAreaIDs.isEmpty))
                }
            }
        }
    }

    private func save() {
        goal.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        goal.purpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        goal.targetDate = hasTargetDate ? targetDate : nil
        goal.isActive = isActive

        for area in profileAreas {
            if let existing = goalContributions.first(where: { $0.category?.id == area.id }) {
                existing.isActive = selectedAreaIDs.contains(area.id) && isActive
            } else if selectedAreaIDs.contains(area.id) {
                modelContext.insert(GoalAreaContribution(
                    goal: goal, category: area, statement: "\(area.name) supports \(goal.name).",
                    weeklyTargetSessions: area.weeklyTargetSessions,
                    weeklyTargetMinutes: area.weeklyTargetMinutes
                ))
            }
        }
        if !isActive {
            goalContributions.forEach { $0.isActive = false }
            measures.filter { $0.goal?.id == goal.id }.forEach {
                $0.isActive = false
                $0.reminderEnabled = false
            }
        }

        if modelContext.saveOrReport() {
            let goalMeasures = measures.filter { $0.goal?.id == goal.id }
            Task {
                for measure in goalMeasures {
                    await GoalReminderService.updateReminder(for: measure)
                }
            }
            dismiss()
        } else {
            modelContext.rollback()
        }
    }
}

struct EditResultMeasureView: View {
    let measure: ResultMeasure

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allMeasurementDefinitions: [MeasurementDefinition]
    @Query private var allBodyMetricDefinitions: [BodyMetricDefinition]
    @State private var name: String
    @State private var unit: String
    @State private var direction: ResultDirection
    @State private var baseline: Double
    @State private var target: Double
    @State private var minimum: Double
    @State private var maximum: Double
    @State private var cadence: ResultCheckInCadence
    @State private var nextDate: Date
    @State private var reminderEnabled: Bool
    @State private var reminderTime: Date
    @State private var isActive: Bool
    @State private var resultSource: ResultSource
    @State private var selectedMeasurementDefinitionID: UUID?
    @State private var selectedNutritionMetric: NutritionEngine.Metric?
    @State private var selectedBodyMetricDefinitionID: UUID?

    init(measure: ResultMeasure) {
        self.measure = measure
        _name = State(initialValue: measure.name)
        _unit = State(initialValue: measure.unit)
        _direction = State(initialValue: measure.direction)
        _baseline = State(initialValue: measure.baselineValue ?? 0)
        _target = State(initialValue: measure.targetValue ?? 0)
        _minimum = State(initialValue: measure.targetMinimum ?? 0)
        _maximum = State(initialValue: measure.targetMaximum ?? 0)
        _cadence = State(initialValue: measure.cadence)
        _nextDate = State(initialValue: measure.nextCheckInDate ?? Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now)
        _reminderEnabled = State(initialValue: measure.reminderEnabled)
        _reminderTime = State(initialValue: Calendar.current.date(bySettingHour: measure.reminderHour, minute: measure.reminderMinute, second: 0, of: .now) ?? .now)
        _isActive = State(initialValue: measure.isActive)
        let initialSource: ResultSource
        if measure.linkedNutritionMetric != nil { initialSource = .nutritionMetric }
        else if measure.linkedBodyMetricDefinitionID != nil { initialSource = .bodyMetric }
        else if measure.linkedMeasurementDefinitionID != nil { initialSource = .activityMeasurement }
        else { initialSource = .manual }
        _resultSource = State(initialValue: initialSource)
        _selectedMeasurementDefinitionID = State(initialValue: measure.linkedMeasurementDefinitionID)
        _selectedNutritionMetric = State(initialValue: measure.linkedNutritionMetric)
        _selectedBodyMetricDefinitionID = State(initialValue: measure.linkedBodyMetricDefinitionID)
    }

    /// Only numeric-style measurements (not free text) can back a numeric Result.
    /// Works identically for any Activity — Baseball, Guitar, Coding, etc.
    private var compatibleMeasurementDefinitions: [MeasurementDefinition] {
        guard let profileID = measure.goal?.profile?.id else { return [] }
        return allMeasurementDefinitions
            .filter { $0.isActive && $0.type != .text && $0.activity?.profile?.id == profileID }
            .sorted { ($0.activity?.name ?? "", $0.sortOrder) < ($1.activity?.name ?? "", $1.sortOrder) }
    }
    private var bodyMetricDefinitions: [BodyMetricDefinition] {
        guard let profileID = measure.goal?.profile?.id else { return [] }
        return allBodyMetricDefinitions
            .filter { $0.profileID == profileID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var valid: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch resultSource {
        case .manual: break
        case .activityMeasurement: guard selectedMeasurementDefinitionID != nil else { return false }
        case .nutritionMetric: guard selectedNutritionMetric != nil else { return false }
        case .bodyMetric: guard selectedBodyMetricDefinitionID != nil else { return false }
        }
        if measure.valueType == .text || measure.valueType == .milestone { return true }
        return ResultMeasureValidation.isValidTarget(
            valueType: measure.valueType, direction: direction,
            baseline: baseline, target: target, minimum: minimum, maximum: maximum
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                if measure.valueType == .number || measure.valueType == .rating {
                    Section("Result source") {
                        ResultLinkPicker(
                            resultSource: $resultSource,
                            selectedMeasurementDefinitionID: $selectedMeasurementDefinitionID,
                            selectedNutritionMetric: $selectedNutritionMetric,
                            selectedBodyMetricDefinitionID: $selectedBodyMetricDefinitionID,
                            compatibleMeasurementDefinitions: compatibleMeasurementDefinitions,
                            bodyMetricDefinitions: bodyMetricDefinitions
                        )
                    }
                }
                Section("Result measure") {
                    TextField("Name", text: $name)
                    Toggle("Active", isOn: $isActive)
                    if measure.valueType == .number || measure.valueType == .rating {
                        TextField("Unit", text: $unit)
                        Picker("Desired result", selection: $direction) {
                            ForEach(ResultDirection.allCases) { Text($0.rawValue).tag($0) }
                        }
                        TextField("Starting result", value: $baseline, format: .number).keyboardType(.decimalPad)
                        if direction == .increase || direction == .decrease {
                            TextField("Target result", value: $target, format: .number).keyboardType(.decimalPad)
                        } else {
                            TextField("Minimum", value: $minimum, format: .number).keyboardType(.decimalPad)
                            TextField("Maximum", value: $maximum, format: .number).keyboardType(.decimalPad)
                        }
                    }
                }
                Section("Check-in") {
                    Picker("Cadence", selection: $cadence) {
                        ForEach(ResultCheckInCadence.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if cadence != .onDemand {
                        DatePicker("Next result", selection: $nextDate, displayedComponents: .date)
                        Toggle("Remind me", isOn: $reminderEnabled)
                        if reminderEnabled { DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute) }
                    }
                }
            }
            .navigationTitle("Edit Result")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!valid) }
            }
        }
    }

    private func save() {
        measure.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        measure.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        measure.direction = direction
        measure.baselineValue = measure.valueType == .text || measure.valueType == .milestone ? nil : baseline
        measure.targetValue = direction == .increase || direction == .decrease ? target : nil
        measure.targetMinimum = direction == .targetRange || direction == .maintainRange ? minimum : nil
        measure.targetMaximum = direction == .targetRange || direction == .maintainRange ? maximum : nil
        measure.cadence = cadence
        measure.nextCheckInDate = cadence == .onDemand ? nil : nextDate
        measure.reminderEnabled = isActive && cadence != .onDemand && reminderEnabled
        measure.reminderHour = Calendar.current.component(.hour, from: reminderTime)
        measure.reminderMinute = Calendar.current.component(.minute, from: reminderTime)
        measure.isActive = isActive
        measure.linkedMeasurementDefinitionID = resultSource == .activityMeasurement ? selectedMeasurementDefinitionID : nil
        measure.linkedNutritionMetric = resultSource == .nutritionMetric ? selectedNutritionMetric : nil
        measure.linkedBodyMetricDefinitionID = resultSource == .bodyMetric ? selectedBodyMetricDefinitionID : nil
        if modelContext.saveOrReport() {
            Task { await GoalReminderService.updateReminder(for: measure) }
            dismiss()
        }
    }
}

struct EditResultEntryView: View {
    let entry: ResultEntry

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var numericValue: Double?
    @State private var textValue: String
    @State private var source: String
    @State private var note: String

    init(entry: ResultEntry) {
        self.entry = entry
        _date = State(initialValue: entry.date)
        _numericValue = State(initialValue: entry.numericValue)
        _textValue = State(initialValue: entry.textValue)
        _source = State(initialValue: entry.sourceLabel)
        _note = State(initialValue: entry.note)
    }

    private var canSave: Bool {
        guard let measure = entry.measure else { return false }
        return ResultMeasureValidation.isValidEntry(
            valueType: measure.valueType, numericValue: numericValue, textValue: textValue
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                if entry.measure?.valueType == .text {
                    TextField("Result", text: $textValue, axis: .vertical)
                } else {
                    TextField("Value", value: $numericValue, format: .number).keyboardType(.decimalPad)
                }
                TextField("Source", text: $source)
                TextField("Notes", text: $note, axis: .vertical)
            }
            .navigationTitle("Edit Check-in")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
        }
    }

    private func save() {
        entry.date = date
        entry.numericValue = numericValue
        entry.textValue = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.sourceLabel = source.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if modelContext.saveOrReport() { dismiss() }
    }
}
