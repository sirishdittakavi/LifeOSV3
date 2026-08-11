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
    @State private var showingAddPlan = false
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
                        compactDailyProgress
                        overviewGrid
                        dueResults
                        todaySections
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
            .sheet(isPresented: $showingAddPlan) {
                if let profile = selection.profile {
                    AddImprovementCategoryView(profile: profile)
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
        .buttonStyle(LifeOSPrimaryButtonStyle())
        .padding(.horizontal, LifeOSSpacing.lg)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .accessibilityHint("Record an unscheduled Task, meal, weight, or sport session")
        .accessibilityIdentifier("today.logWhatHappened")
    }

    private var compactDailyProgress: some View {
        let percent = Int((viewModel.summary.percentComplete * 100).rounded())
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today's progress")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("\(percent)%")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.blue)
            }
            ProgressView(value: viewModel.summary.percentComplete)
                .tint(viewModel.summary.remaining == 0 && viewModel.summary.total > 0 ? .green : .blue)
                .scaleEffect(y: 1.7)
            Text(viewModel.summary.total == 0
                 ? "No Tasks scheduled today"
                 : "\(viewModel.summary.done) of \(viewModel.summary.total) Tasks complete")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .lifeOSGlassCard(tint: .blue, cornerRadius: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's progress, \(percent) percent, \(viewModel.summary.done) of \(viewModel.summary.total) Tasks complete")
        .accessibilityIdentifier("today.progress")
    }

    private var dailySignals: some View {
        let profile = selection.profile
        let todayFood = foodEntries.filter {
            $0.profile?.id == profile?.id && !$0.isMealPlanItem
                && Calendar.current.isDateInToday($0.date)
        }
        let protein = todayFood.reduce(0.0) { $0 + $1.proteinGrams }
        let latestWeight = weightEntries.first { $0.profile?.id == profile?.id }
        let todaySportEntries = sportEntries.filter {
            $0.profile?.id == profile?.id && Calendar.current.isDateInToday($0.date)
        }
        let sportMinutes = todaySportEntries.reduce(0) { $0 + $1.durationMinutes }
        let profileSportCategories = categories.filter {
            $0.profile?.id == profile?.id && $0.trackingKind == .sport && $0.isActive
        }
        let loggedSportNames = Set(todaySportEntries.compactMap { $0.category?.name })
        let sportName = loggedSportNames.count == 1
            ? (loggedSportNames.first ?? "Sport")
            : (loggedSportNames.isEmpty && profileSportCategories.count == 1
                ? profileSportCategories[0].name : "Sport")
        let sportSymbol = todaySportEntries.compactMap(\.category).first?.symbol
            ?? profileSportCategories.first { $0.name == sportName }?.symbol
            ?? "figure.run"

        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("DAILY SIGNALS", symbol: "waveform.path.ecg")
            HStack(spacing: 10) {
                DailySignalCard(
                    title: "Protein",
                    value: "\(Int(protein))/\(Int(profile?.proteinGoalGrams ?? 0))g",
                    symbol: "fork.knife", color: .green
                )
                DailySignalCard(
                    title: "Weight",
                    value: latestWeight.map {
                        let unit = profile?.weightUnit ?? .kilograms
                        return "\(unit.displayValue(kilograms: $0.kilograms).formatted(.number.precision(.fractionLength(1))))\(unit.rawValue)"
                    } ?? "—",
                    symbol: "scalemass.fill", color: .blue
                )
                DailySignalCard(
                    title: sportName, value: "\(sportMinutes) min",
                    symbol: sportSymbol, color: .orange
                )
            }
        }
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

    private var overviewGrid: some View {
        let profile = selection.profile
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("PLANS", symbol: "rectangle.3.group.fill")
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
                            detail: snapshot.detail,
                            progress: snapshot.progress,
                            action: { selectedOverviewPlan = plan }
                        )
                        .containerRelativeFrame(.horizontal, count: 3, span: 1, spacing: 8)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .frame(height: 146)
            .accessibilityLabel("Plans, horizontal list")
            .accessibilityHint("Swipe left or right to see more Plans")

            Button {
                showingAddPlan = true
            } label: {
                Label("Add another Plan later", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

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
            return TodayPlanSnapshot(
                value: "\(planSummary.done)/\(planSummary.total)",
                detail: planSummary.total == 0 ? "No Tasks today" : "\(planSummary.remaining) remaining",
                progress: taskMetric.targetValue != nil ? taskMetric.progress : nil
            )
        }
    }

    @ViewBuilder
    private var dueResults: some View {
        if !viewModel.dueResultMeasures.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionLabel("RESULT CHECK-INS", symbol: "scope")
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
                sectionLabel("TODAY'S TASKS", symbol: "checklist")
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
                    sectionLabel("NEXT TASK", symbol: "arrow.forward.circle.fill")
                    itemRow(nextItem)
                }
                if !viewModel.restOfDayItems.isEmpty {
                    sectionLabel("REST OF DAY", symbol: "calendar.day.timeline.left")
                        .padding(.top, 6)
                    ForEach(viewModel.restOfDayItems) { item in itemRow(item) }
                }
                if !viewModel.overdueItems.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        sectionLabel("OVERDUE", symbol: "clock.badge.exclamationmark.fill")
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
                            sectionLabel("COMPLETED & DECIDED", symbol: "checkmark.circle.fill")
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
            onDone: { feedbackTrigger += 1; recordingItem = item },
            onSkip: { feedbackTrigger += 1; viewModel.skip(item) },
            onUndoSkip: { feedbackTrigger += 1; viewModel.undoSkip(item) },
            onDetails: { selectedTask = item.activity },
            isOverdue: PlanningService.isOverdue(item, now: currentTime)
        )
    }

    private func sectionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.bold))
            .tracking(0.7)
            .foregroundStyle(.secondary)
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

private struct TodayProgressHero: View {
    let summary: CompletionSummary

    private var percent: Int { Int((summary.percentComplete * 100).rounded()) }

    var body: some View {
        HStack(spacing: LifeOSSpacing.md) {
            ZStack {
                SignatureProgressRing(
                    fraction: summary.percentComplete,
                    gradient: ImprovementPillar.physical.gradient,
                    lineWidth: 8,
                    diameter: 88
                )
                GlacierProgressMark(fraction: summary.percentComplete)
                VStack(spacing: 0) {
                    Text("\(percent)%")
                        .font(.title3.weight(.bold).monospacedDigit())
                    Text("done").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 88, height: 88)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Daily plan \(percent) percent complete")

            VStack(alignment: .leading, spacing: 9) {
                Text("Daily plan").font(.title3.weight(.bold))
                Text(summary.total == 0
                     ? "Build your day with one meaningful Task."
                     : "\(summary.done) of \(summary.total) planned Tasks complete")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    SummaryPill(value: summary.done, label: "done", color: .green)
                    SummaryPill(value: summary.remaining, label: "left", color: .blue)
                    if summary.skipped > 0 {
                        SummaryPill(value: summary.skipped, label: "skipped", color: .secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .lifeOSGlassCard(tint: summary.remaining == 0 && summary.total > 0 ? .green : .blue,
                         cornerRadius: 26)
    }
}

/// A quiet glacier watermark makes daily progress recognisably LifeOS while
/// leaving the schedule and numeric completion value as the primary content.
private struct GlacierProgressMark: View {
    let fraction: Double

    private var safeFraction: Double {
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }

    var body: some View {
        ZStack {
            Image(systemName: "mountain.2.fill")
                .foregroundStyle(Color.primary.opacity(0.045))
            Image(systemName: "mountain.2.fill")
                .foregroundStyle(
                    LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom)
                )
                .mask(alignment: .bottom) {
                    Rectangle().frame(height: 42 * safeFraction)
                }
                .opacity(0.18)
        }
        .font(.system(size: 38, weight: .light))
        .accessibilityHidden(true)
    }
}

private struct SummaryPill: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        Text("\(value) \(label)")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.10), in: Capsule())
    }
}

private struct DailySignalCard: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.10), in: Circle())
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
    }
}

private struct TodayPlanSnapshot {
    let value: String
    let detail: String
    let progress: Double?
}

private struct TodayOverviewTile: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    let detail: String
    let progress: Double?
    let action: () -> Void

    private var safeProgress: Double? {
        guard let progress, progress.isFinite else { return nil }
        return min(max(progress, 0), 1)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.11), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(value)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let safeProgress {
                    ProgressView(value: safeProgress)
                        .tint(tint)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 122, alignment: .leading)
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 0.75)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value), \(detail)")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Button(action: onDetails) {
                HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 5) {
                    Image(systemName: item.activity?.category?.symbol ?? "circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(categoryColor)
                        .frame(width: 42, height: 42)
                        .background(categoryColor.opacity(0.11), in: Circle())
                    Text(item.plannedStart?.formatted(date: .omitted, time: .shortened) ?? "Any time")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(isOverdue ? .orange : .secondary)
                        .lineLimit(1)
                }
                .frame(width: 64)

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.activity?.name ?? "Task")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        if let category = item.activity?.category {
                            Text(category.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        StatusBadge(status: item.status, isOverdue: isOverdue)
                    }
                    if let duration = item.activity?.estimatedDurationMinutes, duration > 0 {
                        Label("\(duration) min", systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .frame(minHeight: 44)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows all Task details")

            actionButtons
        }
        .lifeOSGlassCard(tint: categoryColor, cornerRadius: 22)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.card.\(taskIdentifier)")
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch item.status {
        case .planned:
            HStack(spacing: 8) {
                Button("Start", action: onStart)
                    .buttonStyle(LifeOSInlineButtonStyle(tint: .blue))
                    .accessibilityHint("Marks this Task in progress")
                Button("Done", action: onDone)
                    .buttonStyle(LifeOSInlineButtonStyle(tint: .green, filled: true))
                    .accessibilityHint("Opens the result and notes form")
                    .accessibilityIdentifier("today.done.\(taskIdentifier)")
                Button("Skip", action: onSkip)
                    .buttonStyle(LifeOSInlineButtonStyle(tint: .primary))
                    .accessibilityHint("Marks this Task skipped")
                    .accessibilityIdentifier("today.skip.\(taskIdentifier)")
            }
        case .inProgress:
            HStack(spacing: 8) {
                Button("Finish", action: onDone)
                    .buttonStyle(LifeOSInlineButtonStyle(tint: .green, filled: true))
                    .accessibilityHint("Opens the result and notes form")
                    .accessibilityIdentifier("today.done.\(taskIdentifier)")
                Button("Skip", action: onSkip)
                    .buttonStyle(LifeOSInlineButtonStyle(tint: .primary))
                    .accessibilityHint("Marks this Task skipped")
                    .accessibilityIdentifier("today.skip.\(taskIdentifier)")
            }
        case .done:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(completionText).font(.caption).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
        case .skipped:
            Button("Undo Skip", action: onUndoSkip)
                .buttonStyle(LifeOSInlineButtonStyle(tint: .blue))
                .accessibilityHint("Returns this occurrence to the active Home plan")
                .accessibilityIdentifier("today.undoSkip.\(taskIdentifier)")
        case .rescheduled, .unplanned:
            EmptyView()
        }
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

    private var color: Color {
        if isOverdue { return .orange }
        switch status {
        case .done: return .green
        case .inProgress: return .blue
        case .skipped: return .secondary
        case .rescheduled: return .orange
        case .unplanned: return .purple
        case .planned: return .secondary
        }
    }

    var body: some View {
        Text(isOverdue ? "Overdue" : status.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.10), in: Capsule())
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Profile.self, SavedCategoryTemplate.self, AppCategory.self, Goal.self, GoalAreaContribution.self, ResultMeasure.self, ResultEntry.self, Activity.self, CalendarItem.self, ActivitySession.self, FoodEntry.self, WeightEntry.self, SportEntry.self], inMemory: true)
}
