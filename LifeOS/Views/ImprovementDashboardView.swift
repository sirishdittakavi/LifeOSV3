import SwiftUI
import SwiftData
import Charts

struct ImprovementDashboardView: View {
    @Bindable var selection: SelectedProfile
    @Query private var categories: [AppCategory]
    @Query private var goals: [Goal]
    @Query private var contributions: [GoalAreaContribution]
    @Query private var measures: [ResultMeasure]
    @Query private var resultEntries: [ResultEntry]
    @Query private var activities: [Activity]
    @Query private var calendarItems: [CalendarItem]
    @State private var period: DashboardPeriod = .week
    @State private var showingAddGoal = false
    @State private var showingAddAction = false
    @State private var showingAddArea = false
    @State private var showingStarterPlans = false

    private var profileCategories: [AppCategory] {
        guard let profile = selection.profile else { return [] }
        return categories.filter { $0.profile?.id == profile.id && $0.isActive }
    }

    private var profileGoals: [Goal] {
        guard let profile = selection.profile else { return [] }
        return goals.filter { $0.profile?.id == profile.id && $0.isActive }
            .sorted { $0.targetDate ?? .distantFuture < $1.targetDate ?? .distantFuture }
    }

    private var progresses: [GoalProgress] {
        profileGoals.map {
            GoalProgressEngine.progress(
                goal: $0, period: period, categories: profileCategories,
                contributions: contributions, measures: measures, entries: resultEntries,
                activities: activities, calendarItems: calendarItems
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Picker("Effort period", selection: $period) {
                        ForEach(DashboardPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    GoalCoverageSummary(progresses: progresses, period: period)

                    if progresses.isEmpty {
                        ContentUnavailableView {
                            Label("No Goals Yet", systemImage: "scope")
                        } description: {
                            Text("Create a measurable Goal, connect the Areas that support it, and add results when they become available.")
                        } actions: {
                            Button("Create First Goal") { showingAddGoal = true }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 24)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("GOALS").font(.caption.bold()).foregroundStyle(.secondary)
                            ForEach(progresses) { progress in
                                NavigationLink {
                                    GoalDetailView(
                                        selection: selection, goal: progress.goal, period: period
                                    )
                                } label: {
                                    GoalProgressCard(progress: progress)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !profileCategories.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("AREAS SUPPORT THE GOALS")
                                .font(.caption.bold()).foregroundStyle(.secondary)
                            Text("Areas organise the plan. Only measured results determine whether a Goal is working.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfilePicker(selection: selection) }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingAddGoal = true } label: {
                            Label("Add a Goal", systemImage: "scope")
                        }
                        Button { showingAddAction = true } label: {
                            Label("Add an Action", systemImage: "checkmark.circle.badge.plus")
                        }
                        .disabled(profileCategories.isEmpty)
                        Button { showingAddArea = true } label: {
                            Label("Add an Area", systemImage: "plus.square")
                        }
                        Button { showingStarterPlans = true } label: {
                            Label("Start from a Plan", systemImage: "square.grid.2x2")
                        }
                    } label: { Image(systemName: "plus") }
                    .disabled(selection.profile == nil)
                }
            }
            .sheet(isPresented: $showingAddGoal) {
                if let profile = selection.profile { AddGoalView(profile: profile) }
            }
            .sheet(isPresented: $showingAddAction) {
                if let profile = selection.profile { AddActivityView(profile: profile) }
            }
            .sheet(isPresented: $showingAddArea) {
                if let profile = selection.profile {
                    AddImprovementCategoryView(profile: profile, startMode: .custom)
                }
            }
            .sheet(isPresented: $showingStarterPlans) {
                if let profile = selection.profile { AddImprovementCategoryView(profile: profile) }
            }
        }
    }
}

private struct GoalCoverageSummary: View {
    let progresses: [GoalProgress]
    let period: DashboardPeriod

    private var moving: Int {
        progresses.filter { $0.status == .achieved || $0.status == .onTrack }.count
    }
    private var review: Int { progresses.filter { $0.status == .needsAttention }.count }
    private var waiting: Int {
        progresses.filter { $0.status == .awaitingResult || $0.status == .notEnoughEvidence }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RESULTS + \(period.rawValue.uppercased()) EFFORT")
                .font(.caption.bold()).foregroundStyle(.secondary)
            Text(progresses.isEmpty
                 ? "Define what success looks like"
                 : "\(moving) of \(progresses.count) Goals are moving or reached")
                .font(.title3.bold())
            if !progresses.isEmpty {
                HStack(spacing: 8) {
                    CoveragePill(value: moving, label: "moving", color: .green)
                    CoveragePill(value: review, label: "review", color: .orange)
                    CoveragePill(value: waiting, label: "waiting", color: .gray)
                }
            }
            Text("Action completion shows adherence. Result check-ins show whether the real outcome changed.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .lifeOSCard()
    }
}

private struct CoveragePill: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        Text("\(value) \(label)")
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(color.opacity(0.14)).foregroundStyle(color)
            .clipShape(Capsule())
    }
}

private struct GoalProgressCard: View {
    let progress: GoalProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.goal.name).font(.headline).foregroundStyle(.primary)
                    Text(progress.resultSummary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }

            if let fraction = progress.resultFraction {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Result progress").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(fraction * 100))%").font(.caption.bold())
                    }
                    ProgressView(value: fraction).tint(statusColor)
                }
            }

            HStack(spacing: 10) {
                Label(progress.status.rawValue, systemImage: statusSymbol)
                    .font(.caption.bold()).foregroundStyle(statusColor)
                if let effort = progress.effortFraction {
                    Text("Plan \(Int(effort * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(progress.confidence.rawValue)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(progress.nextAction).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .lifeOSCard()
    }

    private var statusColor: Color {
        switch progress.status {
        case .achieved: return .green
        case .onTrack: return .blue
        case .needsAttention: return .orange
        case .awaitingResult, .notEnoughEvidence: return .gray
        }
    }

    private var statusSymbol: String {
        switch progress.status {
        case .achieved: return "checkmark.seal.fill"
        case .onTrack: return "arrow.up.right.circle.fill"
        case .needsAttention: return "exclamationmark.circle.fill"
        case .awaitingResult: return "square.and.pencil"
        case .notEnoughEvidence: return "hourglass"
        }
    }
}

private struct GoalDetailView: View {
    @Bindable var selection: SelectedProfile
    let goal: Goal
    let period: DashboardPeriod
    @Query private var categories: [AppCategory]
    @Query private var contributions: [GoalAreaContribution]
    @Query private var measures: [ResultMeasure]
    @Query private var entries: [ResultEntry]
    @Query private var activities: [Activity]
    @Query private var calendarItems: [CalendarItem]
    @State private var selectedMeasure: ResultMeasure?
    @State private var showingAddMeasure = false

    private var profileCategories: [AppCategory] {
        categories.filter { $0.profile?.id == goal.profile?.id && $0.isActive }
    }
    private var goalMeasures: [ResultMeasure] {
        measures.filter { $0.goal?.id == goal.id && $0.isActive }
            .sorted { $0.role == .primary && $1.role != .primary }
    }
    private var progress: GoalProgress {
        GoalProgressEngine.progress(
            goal: goal, period: period, categories: profileCategories,
            contributions: contributions, measures: measures, entries: entries,
            activities: activities, calendarItems: calendarItems
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(goal.purpose.isEmpty ? "A measurable result supported by consistent action." : goal.purpose)
                    if let targetDate = goal.targetDate {
                        Label("Target date \(targetDate.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .lifeOSCard()

                GoalProgressCard(progress: progress)

                ForEach(goalMeasures) { measure in
                    resultMeasureCard(measure)
                }

                Button { showingAddMeasure = true } label: {
                    Label("Add Supporting Result", systemImage: "chart.line.uptrend.xyaxis")
                }
                .buttonStyle(LifeOSSecondaryButtonStyle())

                VStack(alignment: .leading, spacing: 10) {
                    Text("SUPPORTING AREA CONTRIBUTIONS")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    if progress.contributions.isEmpty {
                        Text("No Areas are connected yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(progress.contributions) { item in
                            contributionCard(item)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedMeasure) { measure in
            if let profile = selection.profile {
                AddResultEntryView(profile: profile, measure: measure)
            }
        }
        .sheet(isPresented: $showingAddMeasure) {
            AddResultMeasureView(goal: goal)
        }
    }

    private func resultMeasureCard(_ measure: ResultMeasure) -> some View {
        let measureEntries = entries.filter { $0.measure?.id == measure.id }
            .sorted { $0.date < $1.date }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(measure.role.rawValue.uppercased())
                        .font(.caption2.bold()).foregroundStyle(.secondary)
                    Text(measure.name).font(.headline)
                    Text(targetDescription(measure)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Enter Result") { selectedMeasure = measure }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }

            if measure.valueType != .text && !measureEntries.isEmpty {
                Chart {
                    ForEach(measureEntries) { entry in
                        if let value = entry.numericValue {
                            LineMark(x: .value("Date", entry.date), y: .value(measure.name, value))
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Date", entry.date), y: .value(measure.name, value))
                        }
                    }
                    if let target = measure.targetValue {
                        RuleMark(y: .value("Target", target))
                            .foregroundStyle(.green)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("Target").font(.caption2.bold()).foregroundStyle(.green)
                            }
                    }
                    if let minimum = measure.targetMinimum {
                        RuleMark(y: .value("Target minimum", minimum))
                            .foregroundStyle(.green.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    if let maximum = measure.targetMaximum {
                        RuleMark(y: .value("Target maximum", maximum))
                            .foregroundStyle(.green.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .chartYAxisLabel(measure.unit)
                .frame(height: 170)
            } else if let latest = measureEntries.last {
                Text(latest.textValue).font(.subheadline)
            } else {
                ContentUnavailableView(
                    "No Results Yet", systemImage: "chart.xyaxis.line",
                    description: Text("Enter the first result when it becomes available.")
                )
                .frame(minHeight: 110)
            }

            if let next = measure.nextCheckInDate {
                Label("Next check-in \(next.formatted(date: .abbreviated, time: .omitted))", systemImage: "bell")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Enter when available").font(.caption).foregroundStyle(.secondary)
            }
        }
        .lifeOSCard()
    }

    private func contributionCard(_ item: GoalContributionProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(item.contribution.category?.name ?? "Area", systemImage: item.contribution.category?.symbol ?? "square.grid.2x2")
                    .font(.headline)
                Spacer()
                Text("\(item.completedActions)/\(item.plannedActions)")
                    .font(.subheadline.bold())
            }
            if !item.contribution.statement.isEmpty {
                Text(item.contribution.statement).font(.caption).foregroundStyle(.secondary)
            }
            if let fraction = item.adherenceFraction {
                ProgressView(value: fraction).tint(.blue)
            }
            Text("\(item.completedMinutes) of \(item.plannedMinutes) planned minutes completed")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .lifeOSCard(cornerRadius: 16)
    }

    private func targetDescription(_ measure: ResultMeasure) -> String {
        switch measure.valueType {
        case .milestone: return "Complete this milestone"
        case .text: return "Written evidence · \(measure.cadence.rawValue)"
        case .number, .rating:
            switch measure.direction {
            case .increase, .decrease:
                let value = measure.targetValue?.formatted(.number.precision(.fractionLength(0...2))) ?? "Not set"
                return "Target \(value)\(measure.unit.isEmpty ? "" : " \(measure.unit)")"
            case .targetRange, .maintainRange:
                let low = measure.targetMinimum?.formatted(.number.precision(.fractionLength(0...2))) ?? "?"
                let high = measure.targetMaximum?.formatted(.number.precision(.fractionLength(0...2))) ?? "?"
                return "Target \(low)–\(high)\(measure.unit.isEmpty ? "" : " \(measure.unit)")"
            }
        }
    }
}

private struct AddGoalView: View {
    let profile: Profile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var categories: [AppCategory]
    @State private var name = ""
    @State private var purpose = ""
    @State private var hasTargetDate = true
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now
    @State private var selectedAreaIDs: Set<UUID> = []
    @State private var measureName = ""
    @State private var valueType: ResultValueType = .number
    @State private var unit = ""
    @State private var direction: ResultDirection = .increase
    @State private var baseline = 0.0
    @State private var target = 0.0
    @State private var rangeMinimum = 0.0
    @State private var rangeMaximum = 0.0
    @State private var cadence: ResultCheckInCadence = .monthly
    @State private var nextCheckInDate = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var reminderEnabled = true
    @State private var reminderTime = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now

    private var profileAreas: [AppCategory] {
        categories.filter { $0.profile?.id == profile.id && $0.isActive }
            .sorted { $0.name < $1.name }
    }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !measureName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedAreaIDs.isEmpty &&
        (valueType == .text || valueType == .milestone || validNumericTarget)
    }
    private var validNumericTarget: Bool {
        ResultMeasureValidation.isValidTarget(
            valueType: valueType, direction: direction,
            baseline: baseline, target: target,
            minimum: rangeMinimum, maximum: rangeMaximum
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("1. What result do you want?") {
                    TextField("Example: Improve Mathematics score", text: $name)
                    TextField("Why does this matter?", text: $purpose, axis: .vertical)
                    Toggle("Set a target date", isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker("Target date", selection: $targetDate, in: Date.now..., displayedComponents: .date)
                    }
                }

                Section("2. How will you measure it?") {
                    TextField("Example: Mock-test score", text: $measureName)
                    Picker("Result type", selection: $valueType) {
                        ForEach(ResultValueType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if valueType == .number || valueType == .rating {
                        TextField("Unit, such as %, kg, mph or seconds", text: $unit)
                        Picker("Desired result", selection: $direction) {
                            ForEach(ResultDirection.allCases) { Text($0.rawValue).tag($0) }
                        }
                        TextField("Starting result", value: $baseline, format: .number)
                            .keyboardType(.decimalPad)
                        if direction == .increase || direction == .decrease {
                            TextField("Target result", value: $target, format: .number)
                                .keyboardType(.decimalPad)
                        } else {
                            TextField("Minimum", value: $rangeMinimum, format: .number)
                                .keyboardType(.decimalPad)
                            TextField("Maximum", value: $rangeMaximum, format: .number)
                                .keyboardType(.decimalPad)
                        }
                    }
                }

                Section("3. Which Areas support this Goal?") {
                    if profileAreas.isEmpty {
                        Text("Create an Area first, then return to create this Goal.")
                            .foregroundStyle(.secondary)
                    } else {
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
                    }
                    Text("Actions inside selected Areas automatically count as supporting effort.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("4. When is a result available?") {
                    Picker("Check-in", selection: $cadence) {
                        ForEach(ResultCheckInCadence.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if cadence != .onDemand {
                        DatePicker("Next result", selection: $nextCheckInDate, in: Date.now..., displayedComponents: .date)
                        Toggle("Remind me", isOn: $reminderEnabled)
                        if reminderEnabled {
                            DatePicker("Reminder time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        }
                    }
                }
            }
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let goal = Goal(
            profile: profile, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            purpose: purpose.trimmingCharacters(in: .whitespacesAndNewlines),
            targetDate: hasTargetDate ? targetDate : nil
        )
        modelContext.insert(goal)

        let measure = ResultMeasure(
            goal: goal, name: measureName.trimmingCharacters(in: .whitespacesAndNewlines),
            valueType: valueType, unit: unit.trimmingCharacters(in: .whitespacesAndNewlines),
            direction: direction,
            baselineValue: valueType == .text || valueType == .milestone ? nil : baseline,
            targetValue: direction == .increase || direction == .decrease ? target : nil,
            targetMinimum: direction == .targetRange || direction == .maintainRange ? rangeMinimum : nil,
            targetMaximum: direction == .targetRange || direction == .maintainRange ? rangeMaximum : nil,
            cadence: cadence, nextCheckInDate: cadence == .onDemand ? nil : nextCheckInDate,
            reminderEnabled: cadence != .onDemand && reminderEnabled,
            reminderHour: Calendar.current.component(.hour, from: reminderTime),
            reminderMinute: Calendar.current.component(.minute, from: reminderTime)
        )
        modelContext.insert(measure)

        profileAreas.filter { selectedAreaIDs.contains($0.id) }.forEach { area in
            modelContext.insert(GoalAreaContribution(
                goal: goal, category: area,
                statement: "\(area.name) supports \(goal.name).",
                weeklyTargetSessions: area.weeklyTargetSessions,
                weeklyTargetMinutes: area.weeklyTargetMinutes
            ))
        }
        try? modelContext.save()
        Task { await GoalReminderService.updateReminder(for: measure) }
        dismiss()
    }
}

struct AddResultEntryView: View {
    let profile: Profile
    let measure: ResultMeasure
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var date = Date.now
    @State private var numericValue: Double?
    @State private var ratingValue = 3
    @State private var milestoneComplete: Bool?
    @State private var textValue = ""
    @State private var source = "Manual"
    @State private var note = ""

    private var storedNumericValue: Double? {
        switch measure.valueType {
        case .number: return numericValue
        case .rating: return Double(ratingValue)
        case .milestone: return milestoneComplete.map { $0 ? 1 : 0 }
        case .text: return nil
        }
    }

    private var canSave: Bool {
        ResultMeasureValidation.isValidEntry(
            valueType: measure.valueType,
            numericValue: storedNumericValue,
            textValue: textValue
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Result") {
                    LabeledContent("Goal", value: measure.goal?.name ?? "Goal")
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    switch measure.valueType {
                    case .number:
                        LabeledContent(measure.name) {
                            HStack {
                                TextField("Value", value: $numericValue, format: .number)
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                Text(measure.unit).foregroundStyle(.secondary)
                            }
                        }
                    case .rating:
                        Stepper("\(measure.name): \(ratingValue)/5", value: $ratingValue, in: 1...5)
                    case .milestone:
                        Picker("Status", selection: $milestoneComplete) {
                            Text("Choose").tag(Bool?.none)
                            Text("Completed").tag(Bool?.some(true))
                            Text("Not completed").tag(Bool?.some(false))
                        }
                    case .text:
                        TextField("Assessment", text: $textValue, axis: .vertical)
                    }
                }
                Section("Evidence (optional)") {
                    TextField("Source, such as Mock Test or Coach", text: $source)
                    TextField("Notes", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Enter Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard canSave else { return }
        modelContext.insert(ResultEntry(
            profile: profile, measure: measure, date: date, numericValue: storedNumericValue,
            textValue: textValue.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceLabel: source.trimmingCharacters(in: .whitespacesAndNewlines), note: note
        ))
        measure.nextCheckInDate = measure.cadence.nextDate(after: date)
        try? modelContext.save()
        Task { await GoalReminderService.updateReminder(for: measure) }
        dismiss()
    }
}

private struct AddResultMeasureView: View {
    let goal: Goal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var unit = ""
    @State private var baseline = 0.0
    @State private var target = 0.0
    @State private var direction: ResultDirection = .increase
    @State private var cadence: ResultCheckInCadence = .monthly
    @State private var nextDate = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var reminderEnabled = true
    @State private var reminderTime = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now

    private var validTarget: Bool {
        ResultMeasureValidation.isValidTarget(
            valueType: .number, direction: direction,
            baseline: baseline, target: target, minimum: 0, maximum: 0
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Supporting Result") {
                    TextField("Example: Monthly mock-test score", text: $name)
                    TextField("Unit", text: $unit)
                    Picker("Direction", selection: $direction) {
                        Text(ResultDirection.increase.rawValue).tag(ResultDirection.increase)
                        Text(ResultDirection.decrease.rawValue).tag(ResultDirection.decrease)
                    }
                    TextField("Starting result", value: $baseline, format: .number).keyboardType(.decimalPad)
                    TextField("Target result", value: $target, format: .number).keyboardType(.decimalPad)
                    Picker("Check-in", selection: $cadence) {
                        ForEach(ResultCheckInCadence.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if cadence != .onDemand {
                        DatePicker("Next result", selection: $nextDate, in: Date.now..., displayedComponents: .date)
                        Toggle("Remind me", isOn: $reminderEnabled)
                        if reminderEnabled {
                            DatePicker("Reminder time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        }
                    }
                }
            }
            .navigationTitle("Add Result Measure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !validTarget)
                }
            }
        }
    }

    private func save() {
        let measure = ResultMeasure(
            goal: goal, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            role: .supporting, unit: unit.trimmingCharacters(in: .whitespacesAndNewlines),
            direction: direction, baselineValue: baseline, targetValue: target,
            cadence: cadence, nextCheckInDate: cadence == .onDemand ? nil : nextDate,
            reminderEnabled: cadence != .onDemand && reminderEnabled,
            reminderHour: Calendar.current.component(.hour, from: reminderTime),
            reminderMinute: Calendar.current.component(.minute, from: reminderTime)
        )
        modelContext.insert(measure)
        try? modelContext.save()
        Task { await GoalReminderService.updateReminder(for: measure) }
        dismiss()
    }
}

// Area cards intentionally report activity-plan adherence, not outcome success.
struct CategoryProgressCard: View {
    let progress: CategoryProgress
    var showsDisclosureIndicator = true

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color(.tertiarySystemFill), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress.primaryFraction)
                    .stroke(statusColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(progress.primaryFraction * 100))%")
                    .font(.caption2.bold())
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label(progress.category.name, systemImage: progress.category.symbol)
                        .font(.headline).foregroundStyle(.primary)
                    Spacer()
                    if showsDisclosureIndicator {
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Text(progress.progressText).font(.caption).foregroundStyle(.secondary)
                Text("Activity plan · \(progress.status.rawValue)")
                    .font(.caption2.bold()).foregroundStyle(statusColor)
                Text("This shows adherence, not whether an outcome improved.")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .lifeOSCard(cornerRadius: 16)
    }

    private var statusColor: Color {
        switch progress.status {
        case .complete: return .green
        case .onTrack: return .blue
        case .needsAttention: return .orange
        case .behind: return .red
        case .insufficientData, .notScheduled: return .gray
        }
    }
}
