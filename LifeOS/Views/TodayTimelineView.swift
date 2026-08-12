//
//  TodayTimelineView.swift
//  LifeOS
//
//  The execution surface for a selected Profile. Every number comes from
//  real plan and evidence records; presentation never invents progress.
//

import SwiftUI
import SwiftData
import Combine

struct TodayTimelineView: View {
    @Bindable var selection: SelectedProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query private var activities: [Activity]
    @Query private var allItems: [CalendarItem]
    @Query private var foodEntries: [FoodEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]
    @Query private var sportEntries: [SportEntry]
    @Query private var categories: [AppCategory]
    @Query private var resultMeasures: [ResultMeasure]
    @Query private var measurementDefinitions: [MeasurementDefinition]

    @State private var showingAddActivity = false
    @State private var showingAddWhatHappened = false
    @State private var recordingItem: CalendarItem?
    @State private var resultMeasureToRecord: ResultMeasure?
    @State private var selectedTask: Activity?
    @State private var feedbackTrigger = 0
    @State private var completedExpanded = false
    @State private var showingTaskOverview = false
    @State private var showingFoodTracker = false
    @State private var showingWeightTracker = false
    @State private var showingSportTracker = false
    @State private var selectedOverviewPlan: AppCategory?
    @State private var currentTime = Date.now

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// Refactor.md Step 4: recreated fresh on every access from this View's
    /// live @Query results, so all derived Today state and actions route
    /// through TodayViewModel instead of living on the View directly.
    private var viewModel: TodayViewModel {
        TodayViewModel(
            profile: selection.profile, items: allItems, activities: activities,
            resultMeasures: resultMeasures, currentTime: currentTime,
            repository: SwiftDataCalendarRepository(context: modelContext)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TodayAtmosphericBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        dayHeading
                        overviewGrid
                        todaySections
                        dueResults
                        compactDailyProgress
                    }
                    .padding(.horizontal, LifeOSSpacing.lg)
                    .padding(.top, LifeOSSpacing.sm)
                    .padding(.bottom, LifeOSSpacing.xxl)
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ProfilePicker(selection: selection)
                        .frame(minHeight: 44)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        feedbackTrigger += 1
                        showingAddActivity = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Add Task")
                    .accessibilityIdentifier("today.addTask")
                    .accessibilityHint("Opens the new Task form")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                addWhatHappenedButton
            }
            .sensoryFeedback(.selection, trigger: feedbackTrigger)
            .onAppear { refresh(at: .now, generate: true) }
            .onChange(of: selection.profile?.id) { viewModel.generateTodayItemsIfNeeded() }
            .onReceive(clock) { refresh(at: $0) }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                refresh(at: .now, generate: true)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refresh(at: .now, generate: true) }
            }
            .sheet(isPresented: $showingAddActivity) {
                if let profile = selection.profile { AddActivityView(profile: profile) }
            }
            .sheet(isPresented: $showingAddWhatHappened) {
                if let profile = selection.profile { AddWhatHappenedView(profile: profile) }
            }
            .sheet(item: $recordingItem) { item in
                RecordActualView(item: item)
            }
            .sheet(item: $selectedTask) { TaskDetailView(activity: $0) }
            .sheet(isPresented: $showingTaskOverview) {
                TodayTaskOverviewView(items: viewModel.todayItems)
            }
            .sheet(isPresented: $showingFoodTracker) {
                FoodTrackerView(selection: selection)
            }
            .sheet(isPresented: $showingWeightTracker) {
                WeightTrackerView(selection: selection)
            }
            .sheet(isPresented: $showingSportTracker) {
                if let category = sportPlan {
                    SportTrackerView(selection: selection, category: category)
                }
            }
            .sheet(item: $selectedOverviewPlan) { category in
                NavigationStack {
                    ImprovementCategoryDetailView(selection: selection, category: category)
                }
            }
            .sheet(item: $resultMeasureToRecord) { measure in
                if let profile = selection.profile {
                    AddResultEntryView(profile: profile, measure: measure)
                }
            }
        }
    }

    private var dayHeading: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(currentTime.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.title2.weight(.bold))
                Text(viewModel.summary.remaining == 0 && viewModel.summary.total > 0
                     ? "Your plan is complete."
                     : "One clear Task at a time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Image(systemName: viewModel.summary.remaining == 0 && viewModel.summary.total > 0
                  ? "checkmark.seal.fill" : "sun.max.fill")
                .font(.title2)
                .foregroundStyle(viewModel.summary.remaining == 0 && viewModel.summary.total > 0 ? .green : .orange)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 4)
    }

    private var addWhatHappenedButton: some View {
        Button {
            feedbackTrigger += 1
            showingAddWhatHappened = true
        } label: {
            Label("Log What Happened", systemImage: "plus.circle.fill")
        }
        .buttonStyle(LifeOSTonalButtonStyle())
        .padding(.horizontal, LifeOSSpacing.lg)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .accessibilityHint("Record an unscheduled Task, meal, weight, or sport session")
        .accessibilityIdentifier("today.logWhatHappened")
    }

    /// A compact daily execution summary, not a hero metric — the count
    /// (done/total) is the one dominant value, with a thin indicator as a
    /// secondary reinforcement. Deliberately does not also print a large
    /// percentage alongside it; that redundant triple (percent + count +
    /// bar) is exactly what buried the actual Tasks list before. The
    /// underlying percent is still computed and folded into the
    /// accessibility label so VoiceOver users get the same information.
    private var compactDailyProgress: some View {
        let percent = Int((viewModel.summary.percentComplete * 100).rounded())
        let isComplete = viewModel.summary.remaining == 0 && viewModel.summary.total > 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today").font(.lifeOSSecondary).foregroundStyle(.secondary)
                Spacer()
                if viewModel.summary.total > 0 {
                    Label("\(viewModel.summary.done)/\(viewModel.summary.total)", systemImage: "checkmark")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(isComplete ? Color.lifeOSOnTrack : .primary)
                } else {
                    Text("No Tasks scheduled")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if viewModel.summary.total > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(isComplete ? Color.lifeOSOnTrack : Color.lifeOSFocus)
                            .frame(width: proxy.size.width * viewModel.summary.percentComplete)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(LifeOSSpacing.md)
        .lifeOSElevated(cornerRadius: LifeOSRadius.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's progress, \(percent) percent, \(viewModel.summary.done) of \(viewModel.summary.total) Tasks complete")
        .accessibilityIdentifier("today.progress")
    }

    private var sportPlan: AppCategory? {
        guard let profile = selection.profile else { return nil }
        return categories.first {
            $0.profile?.id == profile.id && $0.isActive && $0.trackingKind == .sport
        }
    }

    private var overviewPlans: [AppCategory] {
        guard let profile = selection.profile else { return [] }
        let profilePlans = categories.filter { $0.profile?.id == profile.id && $0.isActive }
        return CategoryHierarchy.uniqueTopLevelCategories(in: profilePlans)
            .sorted {
                let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
                return comparison == .orderedSame
                    ? $0.id.uuidString < $1.id.uuidString
                    : comparison == .orderedAscending
            }
    }

    /// Compact by design — Plans exist on Today for balance/context, not as
    /// a second dashboard. A task-based Plan shows one dominant status
    /// value; only domain-tracked Plans (nutrition/weight/sport) keep a
    /// trend indicator, since those genuinely have a useful sub-metric.
    private var overviewGrid: some View {
        let profile = selection.profile
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("Plans", symbol: "rectangle.3.group.fill")
                Spacer()
                if overviewPlans.count > 3 {
                    Label("Swipe for more", systemImage: "arrow.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(overviewPlans) { plan in
                        let snapshot = overviewSnapshot(for: plan, profile: profile)
                        TodayOverviewTile(
                            title: plan.name,
                            symbol: plan.symbol,
                            tint: ColorToken.color(for: plan.colorToken),
                            value: snapshot.value,
                            valueStatus: snapshot.valueStatus,
                            detail: snapshot.detail,
                            progress: snapshot.progress,
                            action: { selectedOverviewPlan = plan }
                        )
                        // Column count tracks the actual Plan count (capped
                        // at 3) so 1–2 Plans get real width instead of
                        // always splitting into thirds and truncating
                        // titles/detail text mid-word.
                        .containerRelativeFrame(.horizontal, count: max(1, min(overviewPlans.count, 3)), span: 1, spacing: 8)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .frame(height: 108)
            .accessibilityLabel("Plans, horizontal list")
            .accessibilityHint("Swipe left or right to see more Plans")
        }
    }

    /// Refactor.md Step 7 follow-up: the progress fraction each case shows
    /// now flows through ProgressMetric (current/target/unit -> .progress)
    /// instead of each case hand-computing and capping its own fraction.
    /// Display text stays bespoke per domain — a single ProgressMetric
    /// can't carry nutrition's two independent numbers (calories shown,
    /// protein progress-bearing), so this only consolidates the
    /// progress-bearing calculation, not the presentation strings.
    private func overviewSnapshot(for plan: AppCategory, profile: Profile?) -> TodayPlanSnapshot {
        let planIDs = CategoryHierarchy.idsIncludingDescendants(of: plan, in: categories)
        let planItems = viewModel.todayItems.filter {
            $0.activity?.category.map { planIDs.contains($0.id) } == true
        }
        let planSummary = ProgressEngine.completionSummary(
            items: PlanningService.plannedItems(planItems)
        )
        let taskMetric = ProgressMetric(
            id: plan.id, title: plan.name, currentValue: Double(planSummary.done),
            targetValue: planSummary.total > 0 ? Double(planSummary.total) : nil,
            unit: "tasks", statusText: "", destinationCategoryID: plan.id, destinationGoalID: nil
        )

        switch plan.trackingKind {
        case .nutrition:
            guard let profile else { return TodayPlanSnapshot(value: "0 kcal", detail: "No profile", progress: nil) }
            let totals = ProgressEngine.nutritionTotals(profile: profile, date: currentTime, entries: foodEntries)
            let metric = ProgressMetricBuilder.metric(nutrition: totals, profile: profile)
            return TodayPlanSnapshot(
                value: "\(Int(totals.calories)) kcal",
                detail: "\(Int(metric.currentValue))/\(Int(metric.targetValue ?? 0))g protein",
                progress: metric.progress
            )
        case .bodyWeight:
            let latest = weightEntries.first { $0.profile?.id == profile?.id }
            let unit = profile?.weightUnit ?? .kilograms
            let value = latest.map {
                "\(unit.displayValue(kilograms: $0.kilograms).formatted(.number.precision(.fractionLength(1)))) \(unit.rawValue)"
            } ?? "No entry"
            return TodayPlanSnapshot(value: value, detail: "Latest check-in", progress: nil)
        case .sport:
            let minutes = sportEntries.filter {
                $0.profile?.id == profile?.id
                    && $0.category.map { planIDs.contains($0.id) } == true
                    && Calendar.current.isDateInToday($0.date)
            }.reduce(0) { $0 + $1.durationMinutes }
            let taskDetail = planSummary.total > 0
                ? "\(planSummary.done)/\(planSummary.total) Tasks done"
                : "Open training details"
            return TodayPlanSnapshot(value: "\(minutes) min", detail: taskDetail,
                                     progress: taskMetric.targetValue != nil ? taskMetric.progress : nil)
        case .tasks:
            // One dominant value with semantic status treatment — no
            // simultaneous count + "N remaining" + progress bar triple.
            return TodayPlanSnapshot(
                value: "\(planSummary.done)/\(planSummary.total)",
                valueStatus: planSummary.total > 0 && planSummary.remaining == 0 ? .complete : .neutral,
                detail: planSummary.total == 0 ? "No Tasks today" : nil,
                progress: nil
            )
        }
    }

    @ViewBuilder
    private var dueResults: some View {
        if !viewModel.dueResultMeasures.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionLabel("Result Check-ins", symbol: "scope")
                    Spacer()
                    Text("\(viewModel.dueResultMeasures.count) due")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.orange.opacity(0.12), in: Capsule())
                }

                ForEach(viewModel.dueResultMeasures.prefix(3)) { measure in
                    Button {
                        feedbackTrigger += 1
                        resultMeasureToRecord = measure
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.blue)
                                .frame(width: 36, height: 36)
                                .background(.blue.opacity(0.10), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(measure.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(measure.goal?.name ?? "Goal")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text("Enter")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.blue)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.completedSection")
                    .accessibilityLabel("Enter \(measure.name) result for \(measure.goal?.name ?? "goal")")
                }
            }
            .lifeOSGlassCard(tint: .orange)
        }
    }

    private var todaySections: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("Today's Tasks", symbol: "checklist")
                Spacer()
                Button("View all") { showingTaskOverview = true }
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("today.tasksOverview")
            }
            if viewModel.todayItems.isEmpty {
                ContentUnavailableView(
                    "Nothing Scheduled",
                    systemImage: "calendar.badge.plus",
                    description: Text("Add a Task or log something that happened.")
                )
                .frame(maxWidth: .infinity, minHeight: 230)
                .lifeOSGlassCard(tint: .blue)
            } else {
                if let nextItem = viewModel.nextItem {
                    sectionLabel("Next Task", symbol: "arrow.forward.circle.fill")
                    itemRow(nextItem)
                }
                if !viewModel.restOfDayItems.isEmpty {
                    sectionLabel("Rest of Day", symbol: "calendar.day.timeline.left")
                        .padding(.top, 6)
                    ForEach(viewModel.restOfDayItems) { item in itemRow(item) }
                }
                if !viewModel.overdueItems.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        sectionLabel("Overdue", symbol: "clock.badge.exclamationmark.fill")
                            .foregroundStyle(.orange)
                        Text("Earlier Tasks remain available—complete, skip or edit them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                    ForEach(viewModel.overdueItems) { item in itemRow(item) }
                }
                if !viewModel.decidedItems.isEmpty {
                    Button {
                        withAnimation(.lifeOSReveal) { completedExpanded.toggle() }
                    } label: {
                        HStack {
                            sectionLabel("Completed & Decided", symbol: "checkmark.circle.fill")
                            Spacer()
                            Text("\(viewModel.decidedItems.count)").font(.caption.weight(.bold))
                            Image(systemName: completedExpanded ? "chevron.up" : "chevron.down")
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if completedExpanded {
                        ForEach(viewModel.decidedItems) { item in itemRow(item) }
                    }
                }
            }
        }
    }

    private func itemRow(_ item: CalendarItem) -> some View {
        CalendarItemRow(
            item: item,
            onStart: { feedbackTrigger += 1; viewModel.start(item) },
            onDone: { feedbackTrigger += 1; finish(item) },
            onSkip: { feedbackTrigger += 1; viewModel.skip(item) },
            onUndoSkip: { feedbackTrigger += 1; viewModel.undoSkip(item) },
            onDetails: { selectedTask = item.activity },
            isOverdue: PlanningService.isOverdue(item, now: currentTime)
        )
    }

    /// If the Activity has nothing worth recording (no legacy target, no
    /// active measurements), Finish completes immediately — no sheet, no
    /// blank form to dismiss. Otherwise it opens the existing focused
    /// measurement-entry sheet, unchanged.
    /// Only the "does this need a form" decision lives on the View — it's
    /// UI-level (depends on what's currently on screen). The actual
    /// persistence/rollback for the immediate-finish path lives on
    /// `TodayViewModel.quickFinish`, on the same repository boundary as
    /// `start`/`skip`/`undoSkip`, not duplicated here.
    private func finish(_ item: CalendarItem) {
        let hasTarget = item.activity?.targetValue != nil
        let hasMeasurements = item.activity.map { activity in
            measurementDefinitions.contains { $0.activity?.id == activity.id && $0.isActive }
        } ?? false
        if hasTarget || hasMeasurements {
            recordingItem = item
        } else {
            viewModel.quickFinish(item, at: .now)
        }
    }

    private func sectionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.lifeOSSectionTitle)
            .foregroundStyle(.primary)
    }

    private func refresh(at date: Date, generate: Bool = false) {
        let changedDay = !Calendar.current.isSameDay(currentTime, as: date)
        currentTime = date
        if generate || changedDay { viewModel.generateTodayItemsIfNeeded() }
    }
}

private struct TodayAtmosphericBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: colorScheme == .dark
                    ? [.indigo.opacity(0.18), .clear, .blue.opacity(0.08)]
                    : [.blue.opacity(0.10), .clear, .mint.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.blue.opacity(colorScheme == .dark ? 0.10 : 0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: 160, y: -280)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct TodayPlanSnapshot {
    let value: String
    var valueStatus: LOStatus? = nil
    let detail: String?
    let progress: Double?
}

/// Compact by design: icon, one dominant value (semantic-colored when a
/// status applies), and at most one secondary line — never a value+detail+
/// progress-bar triple for a plain task-based Plan. Domain-tracked Plans
/// (nutrition/weight/sport) may still pass `progress` for a genuinely
/// useful trend, since those aren't just a completion count.
private struct TodayOverviewTile: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    var valueStatus: LOStatus? = nil
    let detail: String?
    let progress: Double?
    let action: () -> Void

    private var safeProgress: Double? {
        guard let progress, progress.isFinite else { return nil }
        return min(max(progress, 0), 1)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.13), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(value)
                        .font(.lifeOSValueEmphasis)
                        .foregroundStyle(valueStatus?.color ?? .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let safeProgress {
                        ProgressView(value: safeProgress)
                            .tint(tint)
                            .padding(.top, 1)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .padding(10)
            .lifeOSElevated(cornerRadius: LifeOSRadius.sm, tint: tint)
            .contentShape(RoundedRectangle(cornerRadius: LifeOSRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)\(detail.map { ", \($0)" } ?? "")")
        .accessibilityHint("Opens \(title)")
        .accessibilityIdentifier("today.overview.\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }
}

private struct TodayTaskOverviewView: View {
    let items: [CalendarItem]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTask: Activity?

    private var sortedItems: [CalendarItem] {
        items.sorted { ($0.plannedStart ?? .distantFuture) < ($1.plannedStart ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if sortedItems.isEmpty {
                        ContentUnavailableView(
                            "No Tasks Today",
                            systemImage: "checklist",
                            description: Text("Scheduled Tasks will appear here.")
                        )
                    } else {
                        ForEach(sortedItems) { item in
                            Button {
                                selectedTask = item.activity
                            } label: {
                                HStack(spacing: 12) {
                                    Text(item.plannedStart?.formatted(date: .omitted, time: .shortened) ?? "Any time")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 62, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.activity?.name ?? "Task")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(taskDetail(for: item))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    StatusBadge(status: item.status, isOverdue: PlanningService.isOverdue(item))
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(minHeight: 48)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows all Task details")
                            .accessibilityIdentifier("today.task.\(item.activity?.name.lowercased() ?? "unknown")")
                        }
                    }
                } header: {
                    Text("All \(sortedItems.count) Tasks")
                } footer: {
                    Text("Tap any Task to view its full details and edit its schedule, duration, target, and Plan.")
                }
            }
            .navigationTitle("Today's Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedTask) { TaskDetailView(activity: $0) }
        }
    }

    private func taskDetail(for item: CalendarItem) -> String {
        let plan = item.activity?.category?.name ?? "No Plan"
        let duration = item.activity?.estimatedDurationMinutes ?? 0
        return duration > 0 ? "\(plan) · \(duration) min" : plan
    }
}

private struct CalendarItemRow: View {
    let item: CalendarItem
    let onStart: () -> Void
    let onDone: () -> Void
    let onSkip: () -> Void
    let onUndoSkip: () -> Void
    let onDetails: () -> Void
    let isOverdue: Bool

    private var categoryColor: Color {
        item.activity?.category.map { ColorToken.color(for: $0.colorToken) } ?? .blue
    }

    /// icon + title + time/duration + concise status + one status/action
    /// control. Tapping the row body opens Task Detail; tapping the status
    /// control performs the single obvious action directly (Skipped →
    /// Undo Skip) or opens a `Menu` when there's a real choice (Planned,
    /// In Progress) — see `statusCluster` below. Either way, the specific
    /// actions stay individually identified so LifeOSUITests can still
    /// find and tap `today.done.*`/`today.skip.*` once the menu is open.
    var body: some View {
        HStack(spacing: LifeOSSpacing.md) {
            Button(action: onDetails) {
                HStack(spacing: 12) {
                    LOIconBadge(symbol: item.activity?.category?.symbol ?? "circle.fill", tint: categoryColor, diameter: 40)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.activity?.name ?? "Task")
                            .font(.lifeOSCardTitle)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if isOverdue {
                                Image(systemName: "exclamationmark.circle.fill").font(.caption2)
                            } else if item.status == .inProgress {
                                Image(systemName: "bolt.fill").font(.caption2)
                            }
                            Text(timeAndDurationText)
                        }
                        .font(.lifeOSSecondary)
                        .foregroundStyle(isOverdue ? Color.lifeOSAttention : (item.status == .inProgress ? Color.lifeOSFocus : .secondary))
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows all Task details")

            statusCluster
        }
        .padding(LifeOSSpacing.md)
        .lifeOSElevated(cornerRadius: LifeOSRadius.md, tint: categoryColor)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.card.\(taskIdentifier)")
    }

    private var timeAndDurationText: String {
        let time = item.plannedStart?.formatted(date: .omitted, time: .shortened) ?? "Any time"
        guard let duration = item.activity?.estimatedDurationMinutes, duration > 0 else { return time }
        return "\(time) · \(duration) min"
    }

    /// ONE status/action control per row. When there's exactly one sensible
    /// next action (Skip → Undo Skip), tapping the control performs it
    /// directly. When there's a real choice (Planned → Start/Finish/Skip;
    /// In Progress → Finish/Skip), the control is a `Menu` — still a single
    /// visible affordance, but its items stay individually identified so
    /// `today.done.*`/`today.skip.*` remain real, distinctly-tappable
    /// elements once the menu is open, per LifeOSUITests.
    @ViewBuilder
    private var statusCluster: some View {
        switch item.status {
        case .planned:
            Menu {
                Button(action: onStart) { Label("Start", systemImage: "play.fill") }
                Button(action: onDone) { Label("Finish", systemImage: "checkmark") }
                    .accessibilityIdentifier("today.done.\(taskIdentifier)")
                Button(action: onSkip) { Label("Skip", systemImage: "arrow.uturn.forward") }
                    .accessibilityIdentifier("today.skip.\(taskIdentifier)")
            } label: {
                actionGlyph(symbol: "circle", tint: .lifeOSFocus)
            }
            .accessibilityIdentifier("today.actions.\(taskIdentifier)")
            .accessibilityLabel("Task actions")
            .accessibilityHint("Start, finish, or skip this Task")
        case .inProgress:
            Menu {
                Button(action: onDone) { Label("Finish", systemImage: "checkmark") }
                    .accessibilityIdentifier("today.done.\(taskIdentifier)")
                Button(action: onSkip) { Label("Skip", systemImage: "arrow.uturn.forward") }
                    .accessibilityIdentifier("today.skip.\(taskIdentifier)")
            } label: {
                actionGlyph(symbol: "bolt.fill", tint: .lifeOSFocus)
            }
            .accessibilityIdentifier("today.actions.\(taskIdentifier)")
            .accessibilityLabel("Task actions")
            .accessibilityHint("Finish or skip this Task")
        case .done:
            LOStatusControl(status: .complete, size: 30)
                .accessibilityLabel(completionText)
        case .skipped:
            Button(action: onUndoSkip) {
                actionGlyph(symbol: "arrow.uturn.backward", tint: .lifeOSFocus)
            }
            .buttonStyle(LOScalePressStyle())
            .accessibilityLabel("Undo Skip")
            .accessibilityHint("Returns this occurrence to the active Home plan")
            .accessibilityIdentifier("today.undoSkip.\(taskIdentifier)")
        case .rescheduled, .unplanned:
            EmptyView()
        }
    }

    /// The visible glyph is deliberately smaller than its tap target — a
    /// 44×44pt hit area with a ~34pt drawn circle centered inside, so the
    /// row stays visually quiet while still meeting the minimum touch
    /// target for an interactive control.
    private func actionGlyph(symbol: String, tint: Color) -> some View {
        ZStack {
            Circle().fill(tint.opacity(0.14)).frame(width: 34, height: 34)
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(tint)
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }

    private var completionText: String {
        guard let target = item.activity?.targetValue,
              let unit = item.activity?.targetUnit else { return "Completed" }
        return "Completed · target \(target.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }

    private var taskIdentifier: String {
        (item.activity?.name ?? "unknown")
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }
}

private struct StatusBadge: View {
    let status: CalendarItemStatus
    var isOverdue = false

    /// Maps calendar-item status to the app-wide semantic status roles, so
    /// this badge always means the same thing every other status pill means.
    private var loStatus: LOStatus {
        if isOverdue { return .attention }
        switch status {
        case .done: return .complete
        case .inProgress: return .focus
        case .skipped: return .neutral
        case .rescheduled: return .inProgress
        case .unplanned: return .recovery
        case .planned: return .neutral
        }
    }

    var body: some View {
        Label(isOverdue ? "Overdue" : status.rawValue, systemImage: loStatus.symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(loStatus.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(loStatus.color.opacity(0.10), in: Capsule())
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Profile.self, SavedCategoryTemplate.self, AppCategory.self, Goal.self, GoalAreaContribution.self, ResultMeasure.self, ResultEntry.self, Activity.self, CalendarItem.self, ActivitySession.self, FoodEntry.self, WeightEntry.self, SportEntry.self], inMemory: true)
}
