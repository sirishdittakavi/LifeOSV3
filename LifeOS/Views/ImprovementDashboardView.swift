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
    @Query private var measurementDefinitions: [MeasurementDefinition]
    @Query private var measurementEntries: [MeasurementEntry]
    @State private var period: DashboardPeriod = .week
    @State private var showingAddGoal = false
    @State private var showingAddAction = false
    @State private var showingAddArea = false
    @State private var showingStarterPlans = false
    @State private var showingGoalTemplates = false
    @State private var pendingGoalTemplate: GoalStarterTemplate?

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
                activities: activities, calendarItems: calendarItems,
                measurementDefinitions: measurementDefinitions, measurementEntries: measurementEntries
            )
        }
    }

    private var reportInterval: DateInterval { period.interval(containing: .now) }
    private var report: PeriodCompletionReport? {
        guard let profile = selection.profile else { return nil }
        return ProgressEngine.periodCompletionReport(
            profile: profile, interval: reportInterval,
            items: calendarItems, activities: activities
        )
    }
    private var topLevelPlans: [AppCategory] {
        profileCategories.filter { CategoryHierarchy.isTopLevel($0, in: profileCategories) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Picker("Effort period", selection: $period) {
                        ForEach(DashboardPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let report {
                        PeriodActivityReportCard(report: report, period: period)
                        planBreakdown
                    }

                    LOSectionHeader(title: "Goal Outcomes")

                    GoalCoverageSummary(progresses: progresses, period: period)

                    if progresses.isEmpty {
                        ContentUnavailableView {
                            Label("No Progress Goals Yet", systemImage: "scope")
                        } description: {
                            Text("Choose the result you want from a Plan, then record check-ins when evidence becomes available.")
                        } actions: {
                            VStack(spacing: 10) {
                                LOPrimaryButton(title: "Choose a Goal Template") {
                                    showingGoalTemplates = true
                                }
                                Button("Create a Custom Goal") {
                                    pendingGoalTemplate = nil
                                    showingAddGoal = true
                                }
                                .buttonStyle(LifeOSSecondaryButtonStyle())
                            }
                        }
                        .padding(.top, 24)
                    } else {
                        goalIndex
                    }

                    if !profileCategories.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Plans Create the Progress")
                                .font(.lifeOSSecondary).foregroundStyle(.secondary)
                            Text("Plans contain your regular Tasks. Results show whether that work is moving you forward.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .background(Color.lifeOSCanvas)
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfilePicker(selection: selection) }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingGoalTemplates = true } label: {
                            Label("Choose a Goal Template", systemImage: "square.grid.2x2")
                        }
                        Button {
                            pendingGoalTemplate = nil
                            showingAddGoal = true
                        } label: {
                            Label("Create a Custom Goal", systemImage: "scope")
                        }
                        Button { showingAddAction = true } label: {
                            Label("Add a Task", systemImage: "checkmark.circle.badge.plus")
                        }
                        .disabled(profileCategories.isEmpty)
                        Button { showingAddArea = true } label: {
                            Label("Create a Plan", systemImage: "plus.square")
                        }
                        Button { showingStarterPlans = true } label: {
                            Label("Start from a Plan Template", systemImage: "square.grid.2x2")
                        }
                    } label: { Image(systemName: "plus") }
                    .disabled(selection.profile == nil)
                }
            }
            .sheet(isPresented: $showingGoalTemplates, onDismiss: {
                if pendingGoalTemplate != nil { showingAddGoal = true }
            }) {
                GoalTemplatePickerView { template in
                    pendingGoalTemplate = template
                    showingGoalTemplates = false
                }
            }
            .sheet(isPresented: $showingAddGoal, onDismiss: {
                pendingGoalTemplate = nil
            }) {
                if let profile = selection.profile {
                    AddGoalView(profile: profile, template: pendingGoalTemplate)
                }
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

    private var planBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            LOSectionHeader(title: "Plans")
            Text("Tap a Plan for its Tasks")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(topLevelPlans) { plan in
                let ids = CategoryHierarchy.idsIncludingDescendants(of: plan, in: profileCategories)
                let items = PlanningService.plannedItems(calendarItems.filter {
                    reportInterval.contains($0.date) && $0.activity?.category.map { ids.contains($0.id) } == true && $0.status != .rescheduled
                })
                let planActivities = activities.filter {
                    $0.profile?.id == selection.profile?.id &&
                    $0.category.map { ids.contains($0.id) } == true
                }
                let summary = selection.profile.map {
                    ProgressEngine.periodCompletionReport(
                        profile: $0, interval: reportInterval,
                        items: items, activities: planActivities
                    )
                }
                NavigationLink { ImprovementCategoryDetailView(selection: selection, category: plan) } label: {
                    PlanReportRow(plan: plan, report: summary)
                }
                .buttonStyle(.plain)
            }
            if topLevelPlans.isEmpty {
                Text("Create a Plan to group Tasks and see its activity here.")
                    .font(.subheadline).foregroundStyle(.secondary).lifeOSCard()
            }
        }
    }

    private var goalIndex: some View {
        VStack(alignment: .leading, spacing: 18) {
            LOSectionHeader(title: "Goals by Plan")
            ForEach(profileCategories.filter { category in
                progresses.contains { progress in
                    progress.contributions.contains { $0.contribution.category?.id == category.id }
                }
            }) { category in
                let areaGoals = progresses.filter { progress in
                    progress.contributions.contains { $0.contribution.category?.id == category.id }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label(category.name, systemImage: category.symbol)
                        .font(.headline)
                        .foregroundStyle(ColorToken.color(for: category.colorToken))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(areaGoals) { progress in goalLink(progress, category: category) }
                    }
                }
                .lifeOSGlassCard(tint: ColorToken.color(for: category.colorToken), cornerRadius: 26)
            }

            let ungrouped = progresses.filter(\.contributions.isEmpty)
            if !ungrouped.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Unassigned", systemImage: "square.dashed")
                        .font(.headline).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(ungrouped) { progress in goalLink(progress, category: nil) }
                    }
                }
            }
        }
    }

    private func goalLink(_ progress: GoalProgress, category: AppCategory?) -> some View {
        NavigationLink {
            GoalDetailView(selection: selection, goal: progress.goal, period: period)
        } label: {
            GoalIndexTile(progress: progress, tint: category.map { ColorToken.color(for: $0.colorToken) } ?? .blue)
        }
        .buttonStyle(.plain)
    }
}

private struct PeriodActivityReportCard: View {
    let report: PeriodCompletionReport
    let period: DashboardPeriod
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Task Activity").font(.lifeOSSecondary).foregroundStyle(.secondary)
                    Text("\(report.done) of \(report.total) complete").font(.title2.bold())
                    Text(period.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(report.percentComplete, format: .percent.precision(.fractionLength(0))).font(.lifeOSHeroMetric).foregroundStyle(Color.lifeOSFocus)
            }
            Chart(report.buckets) { bucket in
                BarMark(x: .value("Day", bucket.date, unit: .day), y: .value("Completed", bucket.done)).foregroundStyle(Color.lifeOSFocus.gradient)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                if period != .month {
                    AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) }
                }
            }
            .frame(height: 112)
            HStack(spacing: 8) {
                ReportStatusPill(value: report.done, label: "done", color: .lifeOSOnTrack)
                ReportStatusPill(value: report.skipped, label: "skipped", color: .lifeOSWatch)
                ReportStatusPill(value: report.missed, label: "missed", color: .lifeOSAttention)
                ReportStatusPill(value: report.remaining, label: "left", color: .lifeOSFocus)
            }
        }
        .lifeOSGlassCard(tint: .blue, cornerRadius: 26)
    }
}

private struct ReportStatusPill: View {
    let value: Int; let label: String; let color: Color
    var body: some View {
        VStack(spacing: 2) { Text("\(value)").font(.subheadline.bold()); Text(label).font(.caption2) }
            .frame(maxWidth: .infinity).padding(.vertical, 8).foregroundStyle(color)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PlanReportRow: View {
    let plan: AppCategory; let report: PeriodCompletionReport?
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: plan.symbol).font(.headline).foregroundStyle(ColorToken.color(for: plan.colorToken))
                .frame(width: 42, height: 42).background(ColorToken.color(for: plan.colorToken).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(plan.name).font(.headline); Spacer(); Text("\(report?.done ?? 0)/\(report?.total ?? 0)").font(.subheadline.bold()).foregroundStyle(.secondary) }
                ProgressView(value: report?.percentComplete ?? 0).tint(ColorToken.color(for: plan.colorToken))
                Text((report?.total ?? 0) == 0 ? "No Tasks in this period" : "\(report?.remaining ?? 0) left · \(report?.missed ?? 0) missed · \(report?.skipped ?? 0) skipped")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .lifeOSCard().accessibilityElement(children: .combine).accessibilityHint("Shows this Plan's Tasks and history")
    }
}

private struct GoalIndexTile: View {
    let progress: GoalProgress
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.gradient)
                Image(systemName: "scope").font(.title2.bold()).foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)
            Text(progress.goal.name).font(.subheadline.weight(.semibold)).lineLimit(2)
            Spacer(minLength: 0)
            if let fraction = progress.resultFraction {
                ProgressView(value: fraction).tint(tint)
                Text("\(Int((fraction * 100).rounded()))% toward goal")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            } else {
                Text(progress.status.rawValue).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 145, alignment: .topLeading)
        .padding(13)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.75)
        }
        .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct GoalTemplatePickerView: View {
    let onSelect: (GoalStarterTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose an editable starting point. Review the Result, personal values, supporting Plans and reminder before saving.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Goal Templates") {
                    ForEach(GoalStarterTemplates.all) { template in
                        Button {
                            onSelect(template)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: template.symbol)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(ColorToken.color(for: template.colorToken))
                                    .frame(width: 38, height: 38)
                                    .background(
                                        ColorToken.color(for: template.colorToken).opacity(0.12),
                                        in: Circle()
                                    )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(template.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("\(template.measureName) · \(template.cadence.rawValue)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if template.needsPersonalValues {
                                        Text("Personal values required")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Choose a Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
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
            Text("Task completion shows consistency. Result check-ins show whether the real outcome changed.")
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
                    Text("Effort \(Int(effort * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(progress.confidence.rawValue)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Label(connectedPlans, systemImage: "list.bullet.clipboard")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(progress.nextAction).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .lifeOSCard()
    }

    private var connectedPlans: String {
        let names = progress.contributions.compactMap { $0.contribution.category?.name }
        return names.isEmpty ? "No Areas connected" : "Areas: \(names.joined(separator: ", "))"
    }

    private var statusColor: Color {
        switch progress.status {
        case .achieved: return .lifeOSOnTrack
        case .onTrack: return .lifeOSFocus
        case .needsAttention: return .lifeOSAttention
        case .awaitingResult, .notEnoughEvidence: return .lifeOSNeutral
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
    @Query private var measurementDefinitions: [MeasurementDefinition]
    @Query private var measurementEntries: [MeasurementEntry]
    @State private var selectedMeasure: ResultMeasure?
    @State private var showingAddMeasure = false
    @State private var showingEditGoal = false
    @State private var editingMeasure: ResultMeasure?
    @State private var editingEntry: ResultEntry?

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
            activities: activities, calendarItems: calendarItems,
            measurementDefinitions: measurementDefinitions, measurementEntries: measurementEntries
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(goal.purpose.isEmpty ? "A measurable result supported by consistent Tasks." : goal.purpose)
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
                    LOSectionHeader(title: "Supporting Areas")
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
        .background(Color.lifeOSCanvas)
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingEditGoal = true } label: { Label("Edit Goal", systemImage: "pencil") }
                    .accessibilityLabel("Edit Goal")
            }
        }
        .sheet(item: $selectedMeasure) { measure in
            if let profile = selection.profile {
                AddResultEntryView(profile: profile, measure: measure)
            }
        }
        .sheet(isPresented: $showingAddMeasure) {
            AddResultMeasureView(goal: goal)
        }
        .sheet(isPresented: $showingEditGoal) { EditGoalView(goal: goal) }
        .sheet(item: $editingMeasure) { EditResultMeasureView(measure: $0) }
        .sheet(item: $editingEntry) { EditResultEntryView(entry: $0) }
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
                HStack(spacing: 8) {
                    Button("Enter Result") { selectedMeasure = measure }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Button { editingMeasure = measure } label: {
                        Label("Edit", systemImage: "pencil")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Edit \(measure.name) result settings")
                }
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

            if !measureEntries.isEmpty {
                Divider()
                Text("RECENT CHECK-INS").font(.caption2.bold()).foregroundStyle(.secondary)
                ForEach(Array(measureEntries.suffix(3).reversed())) { entry in
                    Button { editingEntry = entry } label: {
                        HStack {
                            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text(entryDisplay(entry, measure: measure))
                                .foregroundStyle(.secondary)
                            Image(systemName: "pencil")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
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
                    .accessibilityIdentifier("progress.task.completed")
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

    private func entryDisplay(_ entry: ResultEntry, measure: ResultMeasure) -> String {
        if let value = entry.numericValue {
            return value.formatted(.number.precision(.fractionLength(0...2)))
                + (measure.unit.isEmpty ? "" : " \(measure.unit)")
        }
        return entry.textValue.isEmpty ? "Check-in" : entry.textValue
    }
}

private struct AddGoalView: View {
    let profile: Profile
    let template: GoalStarterTemplate?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var categories: [AppCategory]
    @Query private var allMeasurementDefinitions: [MeasurementDefinition]
    @Query private var allBodyMetricDefinitions: [BodyMetricDefinition]
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
    @State private var didApplySuggestedAreas = false
    @State private var resultSource: ResultSource = .manual
    @State private var selectedMeasurementDefinitionID: UUID?
    @State private var selectedNutritionMetric: NutritionEngine.Metric?
    @State private var selectedBodyMetricDefinitionID: UUID?
    @State private var setupStep = 0

    init(profile: Profile, template: GoalStarterTemplate? = nil) {
        self.profile = profile
        self.template = template
        _name = State(initialValue: template?.name ?? "")
        _purpose = State(initialValue: template?.purpose ?? "")
        _measureName = State(initialValue: template?.measureName ?? "")
        _valueType = State(initialValue: template?.valueType ?? .number)
        _unit = State(initialValue: template?.unit ?? "")
        _direction = State(initialValue: template?.direction ?? .increase)
        _baseline = State(initialValue: template?.baseline ?? 0)
        _target = State(initialValue: template?.target ?? 0)
        _rangeMinimum = State(initialValue: template?.targetMinimum ?? 0)
        _rangeMaximum = State(initialValue: template?.targetMaximum ?? 0)
        _cadence = State(initialValue: template?.cadence ?? .monthly)
        let cadence = template?.cadence ?? .monthly
        _nextCheckInDate = State(initialValue:
            cadence.nextDate(after: .now) ?? Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
        )
        _reminderEnabled = State(initialValue: cadence != .onDemand)
    }

    private var profileAreas: [AppCategory] {
        categories.filter { $0.profile?.id == profile.id && $0.isActive }
            .sorted { $0.name < $1.name }
    }
    /// Only numeric-style measurements (not free text) can back a numeric Result.
    /// Works identically for any Activity — Baseball, Guitar, Coding, etc.
    private var compatibleMeasurementDefinitions: [MeasurementDefinition] {
        allMeasurementDefinitions
            .filter { $0.isActive && $0.type != .text && $0.activity?.profile?.id == profile.id }
            .sorted { ($0.activity?.name ?? "", $0.sortOrder) < ($1.activity?.name ?? "", $1.sortOrder) }
    }
    private var bodyMetricDefinitions: [BodyMetricDefinition] {
        allBodyMetricDefinitions
            .filter { $0.profileID == profile.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !measureName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedAreaIDs.isEmpty &&
        (valueType == .text || valueType == .milestone || validNumericTarget) &&
        (resultSource == .manual || valueType == .text || valueType == .milestone
            || (resultSource == .activityMeasurement && selectedMeasurementDefinitionID != nil)
            || (resultSource == .nutritionMetric && selectedNutritionMetric != nil)
            || (resultSource == .bodyMetric && selectedBodyMetricDefinitionID != nil))
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
            VStack(spacing: 0) {
                ProgressView(value: Double(setupStep + 1), total: 3)
                    .tint(.lifeOSAccent)
                    .padding(.horizontal, LifeOSSpacing.lg)
                    .padding(.top, LifeOSSpacing.sm)

                ScrollView {
                    VStack(alignment: .leading, spacing: LifeOSSpacing.lg) {
                        setupContent
                    }
                    .padding(LifeOSSpacing.lg)
                }

                setupFooter
            }
            .background(Color.lifeOSCanvas)
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { applySuggestedAreasIfNeeded() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private var setupContent: some View {
        switch setupStep {
        case 0: goalSetup
        case 1: outcomeSetup
        default: planSetup
        }
    }

    private var goalSetup: some View {
        VStack(alignment: .leading, spacing: LifeOSSpacing.lg) {
            Text("What would you like to improve?")
                .font(.lifeOSScreenTitle)
            Text("Use your own words. LifeOS will connect the goal to the tasks that support it.")
                .font(.lifeOSBody)
                .foregroundStyle(.secondary)
            LOCard {
                VStack(alignment: .leading, spacing: LifeOSSpacing.md) {
                    TextField("For example, feel confident in maths", text: $name, axis: .vertical)
                        .font(.title3.weight(.medium))
                    Divider()
                    TextField("Why does this matter? (optional)", text: $purpose, axis: .vertical)
                        .font(.lifeOSBody)
                }
            }
            if let template {
                Label("Starting from \(template.name) — everything remains editable.", systemImage: template.symbol)
                    .font(.lifeOSSecondary)
                    .foregroundStyle(ColorToken.color(for: template.colorToken))
            }
        }
    }

    private var outcomeSetup: some View {
        VStack(alignment: .leading, spacing: LifeOSSpacing.lg) {
            Text("How will you know it improved?")
                .font(.lifeOSScreenTitle)
            Text("This is the outcome you observe. Tasks show your effort separately.")
                .font(.lifeOSBody)
                .foregroundStyle(.secondary)
            LOCard {
                VStack(alignment: .leading, spacing: LifeOSSpacing.md) {
                    TextField("For example, mock-test score", text: $measureName)
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
                    Toggle("Set a target date", isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker("Target date", selection: $targetDate, in: Date.now..., displayedComponents: .date)
                    }
                }
            }
        }
    }

    private var planSetup: some View {
        VStack(alignment: .leading, spacing: LifeOSSpacing.lg) {
            Text("Which plan will support this?")
                .font(.lifeOSScreenTitle)
            Text("Choose the areas where you will create tasks. You can add details and measurements later.")
                .font(.lifeOSBody)
                .foregroundStyle(.secondary)
            LOCard {
                VStack(alignment: .leading, spacing: LifeOSSpacing.sm) {
                    if profileAreas.isEmpty {
                        Text("Create a plan first, then return to link it to this goal.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(profileAreas) { area in
                            Button {
                                if selectedAreaIDs.contains(area.id) { selectedAreaIDs.remove(area.id) }
                                else { selectedAreaIDs.insert(area.id) }
                            } label: {
                                HStack {
                                    LOIconBadge(symbol: area.symbol, tint: ColorToken.color(for: area.colorToken), diameter: 34)
                                    Text(area.name).font(.lifeOSCardTitle)
                                    Spacer()
                                    Image(systemName: selectedAreaIDs.contains(area.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedAreaIDs.contains(area.id) ? Color.lifeOSAccent : .secondary)
                                }
                                .padding(.vertical, LifeOSSpacing.xs)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            LOCard {
                VStack(alignment: .leading, spacing: LifeOSSpacing.sm) {
                    Picker("Check-in", selection: $cadence) {
                        ForEach(ResultCheckInCadence.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if cadence != .onDemand {
                        DatePicker("First check-in", selection: $nextCheckInDate, in: Date.now..., displayedComponents: .date)
                        Toggle("Remind me", isOn: $reminderEnabled)
                        if reminderEnabled {
                            DatePicker("Reminder time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        }
                    }
                }
            }
        }
    }

    private var setupFooter: some View {
        HStack(spacing: LifeOSSpacing.sm) {
            if setupStep > 0 {
                Button("Back") { withAnimation(.lifeOSTap) { setupStep -= 1 } }
                    .buttonStyle(LifeOSInlineButtonStyle(tint: .lifeOSAccent, emphasis: .raised))
            }
            LOPrimaryButton(
                title: setupStep == 2 ? "Create Goal" : "Continue",
                symbol: setupStep == 2 ? "checkmark" : "arrow.right",
                isDisabled: setupStep == 0
                    ? name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    : setupStep == 1
                        ? measureName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !validNumericTarget
                        : !canSave
            ) {
                if setupStep == 2 { save() }
                else { withAnimation(.lifeOSTap) { setupStep += 1 } }
            }
        }
        .padding(LifeOSSpacing.lg)
        .background(.ultraThinMaterial)
    }

    private func applySuggestedAreasIfNeeded() {
        guard !didApplySuggestedAreas, let template else { return }
        didApplySuggestedAreas = true
        let suggestions = template.suggestedAreaNames.map { $0.lowercased() }
        selectedAreaIDs = Set(profileAreas.filter { area in
            let areaName = area.name.lowercased()
            return suggestions.contains { suggestion in
                areaName.contains(suggestion) || suggestion.contains(areaName)
            }
        }.map(\.id))
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
            reminderMinute: Calendar.current.component(.minute, from: reminderTime),
            linkedMeasurementDefinitionID: (valueType == .number || valueType == .rating) && resultSource == .activityMeasurement
                ? selectedMeasurementDefinitionID : nil,
            linkedNutritionMetric: (valueType == .number || valueType == .rating) && resultSource == .nutritionMetric
                ? selectedNutritionMetric : nil,
            linkedBodyMetricDefinitionID: (valueType == .number || valueType == .rating) && resultSource == .bodyMetric
                ? selectedBodyMetricDefinitionID : nil
        )
        modelContext.insert(measure)

        let addedContributions = profileAreas.filter { selectedAreaIDs.contains($0.id) }.map { area in
            let contribution = GoalAreaContribution(
                goal: goal, category: area,
                statement: "\(area.name) supports \(goal.name).",
                weeklyTargetSessions: area.weeklyTargetSessions,
                weeklyTargetMinutes: area.weeklyTargetMinutes
            )
            modelContext.insert(contribution)
            return contribution
        }
        if modelContext.saveOrReport() {
            Task { await GoalReminderService.updateReminder(for: measure, center: RealNotificationCenter.shared) }
            dismiss()
        } else {
            addedContributions.forEach { modelContext.delete($0) }
            modelContext.delete(measure)
            modelContext.delete(goal)
        }
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
        let entry = ResultEntry(
            profile: profile, measure: measure, date: date, numericValue: storedNumericValue,
            textValue: textValue.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceLabel: source.trimmingCharacters(in: .whitespacesAndNewlines), note: note
        )
        modelContext.insert(entry)
        measure.nextCheckInDate = measure.cadence.nextDate(after: date)
        if modelContext.saveOrReport() {
            Task { await GoalReminderService.updateReminder(for: measure, center: RealNotificationCenter.shared) }
            dismiss()
        } else {
            modelContext.rollback()
        }
    }
}

enum ResultSource: String, CaseIterable, Identifiable {
    case manual = "Manual check-in"
    case activityMeasurement = "Activity measurement"
    case nutritionMetric = "Nutrition"
    case bodyMetric = "Body metric"
    var id: String { rawValue }
}

/// Shared Result-source picker content for the three linkage forms (New
/// Goal, Add Result Measure, Edit Result Measure) so they can't drift out
/// of sync. Plain-language labels only (Protein, Weight, ...) — never
/// surfaces linkedNutritionMetricID/linkedBodyMetricDefinitionID to the
/// user. Additive alongside the existing manual/Activity-measurement
/// sources; nothing about those two changes here.
struct ResultLinkPicker: View {
    @Binding var resultSource: ResultSource
    @Binding var selectedMeasurementDefinitionID: UUID?
    @Binding var selectedNutritionMetric: NutritionEngine.Metric?
    @Binding var selectedBodyMetricDefinitionID: UUID?
    let compatibleMeasurementDefinitions: [MeasurementDefinition]
    let bodyMetricDefinitions: [BodyMetricDefinition]

    var body: some View {
        Picker("Source", selection: $resultSource) {
            ForEach(ResultSource.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)

        switch resultSource {
        case .manual:
            EmptyView()
        case .activityMeasurement:
            if compatibleMeasurementDefinitions.isEmpty {
                Text("No compatible Activity measurements yet. Add one from an Activity's Measurements section.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Measurement", selection: $selectedMeasurementDefinitionID) {
                    Text("Choose").tag(UUID?.none)
                    ForEach(compatibleMeasurementDefinitions) { definition in
                        Text("\(definition.activity?.name ?? "Activity") · \(definition.name)")
                            .tag(UUID?.some(definition.id))
                    }
                }
                Text("Progress will total this measurement's entries since the Goal was created — no manual check-ins needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .nutritionMetric:
            Picker("Metric", selection: $selectedNutritionMetric) {
                Text("Choose").tag(NutritionEngine.Metric?.none)
                ForEach(NutritionEngine.Metric.allCases) { metric in
                    Text(metric.displayName).tag(NutritionEngine.Metric?.some(metric))
                }
            }
            Text("Progress will total this from your Nutrition log since the Goal was created.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .bodyMetric:
            if bodyMetricDefinitions.isEmpty {
                Text("No Body Tracking metrics yet. Add one from Body Tracking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Metric", selection: $selectedBodyMetricDefinitionID) {
                    Text("Choose").tag(UUID?.none)
                    ForEach(bodyMetricDefinitions) { definition in
                        Text(definition.name).tag(UUID?.some(definition.id))
                    }
                }
                Text("Progress will use your latest recorded value for this metric.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AddResultMeasureView: View {
    let goal: Goal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allMeasurementDefinitions: [MeasurementDefinition]
    @Query private var allBodyMetricDefinitions: [BodyMetricDefinition]
    @State private var name = ""
    @State private var unit = ""
    @State private var baseline = 0.0
    @State private var target = 0.0
    @State private var direction: ResultDirection = .increase
    @State private var cadence: ResultCheckInCadence = .monthly
    @State private var nextDate = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var reminderEnabled = true
    @State private var reminderTime = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now
    @State private var resultSource: ResultSource = .manual
    @State private var selectedMeasurementDefinitionID: UUID?
    @State private var selectedNutritionMetric: NutritionEngine.Metric?
    @State private var selectedBodyMetricDefinitionID: UUID?

    /// Only numeric-style measurements (not free text) can back a numeric Result.
    /// Works identically for any Activity — Baseball, Guitar, Coding, etc.
    private var compatibleMeasurementDefinitions: [MeasurementDefinition] {
        guard let profileID = goal.profile?.id else { return [] }
        return allMeasurementDefinitions
            .filter { $0.isActive && $0.type != .text && $0.activity?.profile?.id == profileID }
            .sorted { ($0.activity?.name ?? "", $0.sortOrder) < ($1.activity?.name ?? "", $1.sortOrder) }
    }
    private var bodyMetricDefinitions: [BodyMetricDefinition] {
        guard let profileID = goal.profile?.id else { return [] }
        return allBodyMetricDefinitions
            .filter { $0.profileID == profileID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var validTarget: Bool {
        ResultMeasureValidation.isValidTarget(
            valueType: .number, direction: direction,
            baseline: baseline, target: target, minimum: 0, maximum: 0
        )
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validTarget &&
            (resultSource == .manual
                || (resultSource == .activityMeasurement && selectedMeasurementDefinitionID != nil)
                || (resultSource == .nutritionMetric && selectedNutritionMetric != nil)
                || (resultSource == .bodyMetric && selectedBodyMetricDefinitionID != nil))
    }

    var body: some View {
        NavigationStack {
            Form {
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
                    Button("Save", action: save).disabled(!canSave)
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
            reminderMinute: Calendar.current.component(.minute, from: reminderTime),
            linkedMeasurementDefinitionID: resultSource == .activityMeasurement ? selectedMeasurementDefinitionID : nil,
            linkedNutritionMetric: resultSource == .nutritionMetric ? selectedNutritionMetric : nil,
            linkedBodyMetricDefinitionID: resultSource == .bodyMetric ? selectedBodyMetricDefinitionID : nil
        )
        modelContext.insert(measure)
        if modelContext.saveOrReport() {
            Task { await GoalReminderService.updateReminder(for: measure, center: RealNotificationCenter.shared) }
            dismiss()
        } else {
            modelContext.delete(measure)
        }
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
                Text("Task plan · \(progress.status.rawValue)")
                    .font(.caption2.bold()).foregroundStyle(statusColor)
                Text("This shows adherence, not whether an outcome improved.")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .lifeOSCard(cornerRadius: 16)
    }

    private var statusColor: Color {
        switch progress.status {
        case .complete: return .lifeOSOnTrack
        case .onTrack: return .lifeOSFocus
        case .needsAttention: return .lifeOSWatch
        case .behind: return .lifeOSAttention
        case .insufficientData, .notScheduled: return .lifeOSNeutral
        }
    }
}
