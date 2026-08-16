//
//  RootTabView.swift
//  LifeOS
//
//  Improvement dashboard first: period confidence, today's timeline,
//  category map, and detailed progress share one selected profile.
//

import SwiftUI
import SwiftData
import Observation

#if DEBUG
/// Reads `-onboarding-screenshot-step N` from launch arguments (argv), used
/// only to deterministically drive onboarding to a given step for manual
/// screenshot capture. Argv, not a SIMCTL_CHILD_ env var, because argv is
/// what `-ui-testing` already proves reaches the process reliably here.
private func debugOnboardingScreenshotStep() -> Int? {
    let args = ProcessInfo.processInfo.arguments
    guard let flagIndex = args.firstIndex(of: "-onboarding-screenshot-step"),
          flagIndex + 1 < args.count else { return nil }
    return Int(args[flagIndex + 1])
}

/// When set alongside `-onboarding-screenshot-step 2`, drives the seeded
/// plan step straight through Create — the same `createLifeOS()` call the
/// Create button invokes — so the resulting Today screen can be captured
/// without simulator tap automation.
private func debugOnboardingAutoCreateRequested() -> Bool {
    ProcessInfo.processInfo.arguments.contains("-onboarding-screenshot-autocreate")
}

/// Reads `-screenshot-scene <name>` from launch arguments, used only to
/// deterministically navigate straight to a given screen/sheet for manual
/// screenshot capture, without simulator tap automation. Never compiled
/// into Release/TestFlight.
func debugScreenshotScene() -> String? {
    let args = ProcessInfo.processInfo.arguments
    guard let flagIndex = args.firstIndex(of: "-screenshot-scene"),
          flagIndex + 1 < args.count else { return nil }
    return args[flagIndex + 1]
}

private enum DebugScreenshotSheet: String, Identifiable {
    case addTask, addTaskCreated, nutrition, taskDetail, taskDetailReschedule, taskDetailAfterSkip, addGoal
    var id: String { rawValue }
}
#endif

/// Holds which profile is currently active, shared across tabs.
@Observable
final class SelectedProfile {
    static let lastProfileKey = "LifeOS.lastSelectedProfileID"

    var profile: Profile? {
        didSet {
            if let id = profile?.id.uuidString {
                UserDefaults.standard.set(id, forKey: Self.lastProfileKey)
            }
        }
    }
}

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = SelectedProfile()
    @State private var persistenceIssues = PersistenceIssueCenter.shared
    @Query(sort: \Profile.name) private var profiles: [Profile]
    @Query private var categories: [AppCategory]
    @Query private var activities: [Activity]
    @AppStorage("LifeOS.onboarding.v1.completed") private var onboardingCompleted = false
    @State private var showingOnboarding = false
    @State private var selectedTab = 0
    @ObservedObject private var notificationRouter = NotificationRouter.shared
    #if DEBUG
    @State private var debugSheet: DebugScreenshotSheet?
    #endif

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayTimelineView(selection: selection)
                .tabItem { Label("Today", systemImage: "calendar") }
                .tag(0)
                .accessibilityIdentifier("tab.today")

            ImprovementCategoriesView(selection: selection)
                .tabItem { Label("Plans", systemImage: "list.bullet.clipboard") }
                .tag(1)
                .accessibilityIdentifier("tab.plans")

            ImprovementDashboardView(selection: selection)
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(2)
                .accessibilityIdentifier("tab.progress")

            WeeklyScheduleView(selection: selection)
                .tabItem { Label("Schedule", systemImage: "calendar.day.timeline.left") }
                .tag(3)
        }
        .tint(.lifeOSAccent)
        .alert("Couldn’t Save", isPresented: Binding(
            get: { persistenceIssues.message != nil },
            set: { if !$0 { persistenceIssues.message = nil } }
        )) {
            Button("OK") { persistenceIssues.message = nil }
        } message: {
            Text(persistenceIssues.message ?? "Please try again.")
        }
        .onAppear {
            presentOnboardingIfNeeded()
            refreshReminders()
            #if DEBUG
            applyDebugScreenshotSceneIfNeeded()
            #endif
        }
        .onChange(of: profiles.count) { presentOnboardingIfNeeded() }
        #if DEBUG
        .sheet(item: $debugSheet) { sheet in
            if let profile = selection.profile ?? profiles.first(where: \.isActive) {
                switch sheet {
                case .addTask: AddActivityView(profile: profile)
                case .addTaskCreated: AddActivityView(profile: profile, debugAutoCreate: true)
                case .nutrition: NutritionDashboardView(selection: selection)
                case .taskDetail:
                    if let activity = activities.first(where: { $0.profile?.id == profile.id && $0.isActive }) {
                        TaskDetailView(activity: activity)
                    }
                case .taskDetailReschedule:
                    if let activity = activities.first(where: { $0.profile?.id == profile.id && $0.isActive }) {
                        TaskDetailView(activity: activity, debugAutoAction: .reschedule)
                    }
                case .taskDetailAfterSkip:
                    if let activity = activities.first(where: { $0.profile?.id == profile.id && $0.isActive }) {
                        TaskDetailView(activity: activity, debugAutoAction: .skip)
                    }
                case .addGoal: AddGoalView(profile: profile)
                }
            }
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshReminders() }
        }
        .onChange(of: notificationRouter.pendingDeepLink) { _, deepLink in
            handleDeepLink(deepLink)
        }
        .onAppear { handleDeepLink(notificationRouter.pendingDeepLink) }
        .sheet(isPresented: $showingOnboarding) {
            if let profile = selection.profile ?? profiles.first(where: \.isActive) {
                LifeOSOnboardingView(profile: profile) {
                    // Re-affirm the profile onboarding just set up as the
                    // active selection. Without this, ProfilePicker's own
                    // onAppear fallback (alphabetically-first active profile,
                    // when selection.profile is still nil at that point) can
                    // race with this sheet and win, silently landing the
                    // user on a different profile than the one they just
                    // configured.
                    selection.profile = profile
                    onboardingCompleted = true
                    showingOnboarding = false
                    #if DEBUG
                    if debugOnboardingAutoCreateRequested() { selectedTab = 1 }
                    #endif
                }
                .interactiveDismissDisabled()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
        }
    }

    /// Tapping a notification must always land the user on the profile and
    /// screen it was actually for — never whichever profile happened to be
    /// selected before the app was backgrounded. The payload's profileID is
    /// the only source of truth here, matched by ID against the real
    /// Profile list, never by name.
    private func handleDeepLink(_ deepLink: NotificationRouter.DeepLink?) {
        guard let deepLink else { return }
        if let matchedProfile = profiles.first(where: { $0.id == deepLink.profileID }) {
            selection.profile = matchedProfile
        }
        selectedTab = 0
        notificationRouter.pendingDeepLink = nil
    }

    private func presentOnboardingIfNeeded() {
        #if DEBUG
        // Deterministic screenshot capture for review: force onboarding to
        // present regardless of the persisted "completed" flag so each
        // launch reliably lands on the step named by the launch argument,
        // without needing UI-automation taps. Never compiled into
        // Release/TestFlight. Uses an argv flag (like "-ui-testing" above)
        // rather than a SIMCTL_CHILD_ env var, which does not reliably reach
        // the process on every simctl/Xcode combination.
        if debugOnboardingScreenshotStep() != nil,
           let profile = profiles.first(where: \.isActive) {
            if selection.profile == nil { selection.profile = profile }
            showingOnboarding = true
            return
        }
        #endif
        guard !onboardingCompleted,
              let profile = profiles.first(where: \.isActive) else { return }
        if selection.profile == nil { selection.profile = profile }
        showingOnboarding = true
    }

    #if DEBUG
    /// Deterministic navigation for manual screenshot capture — see
    /// debugScreenshotScene(). Never compiled into Release/TestFlight.
    private func applyDebugScreenshotSceneIfNeeded() {
        guard let scene = debugScreenshotScene() else { return }
        if selection.profile == nil { selection.profile = profiles.first(where: \.isActive) }
        switch scene {
        case "today", "today-completed", "today-undo": selectedTab = 0
        case "plans": selectedTab = 1
        case "progress": selectedTab = 2
        case "schedule": selectedTab = 3
        case "add-task": selectedTab = 0; debugSheet = .addTask
        case "add-task-created": selectedTab = 0; debugSheet = .addTaskCreated
        case "nutrition": selectedTab = 0; debugSheet = .nutrition
        case "task-detail": selectedTab = 0; debugSheet = .taskDetail
        case "task-detail-reschedule": selectedTab = 0; debugSheet = .taskDetailReschedule
        case "task-detail-after-skip": selectedTab = 0; debugSheet = .taskDetailAfterSkip
        case "add-goal": debugSheet = .addGoal
        default: break
        }
    }
    #endif

    private func refreshReminders() {
        guard !categories.isEmpty else { return }
        Task {
            for category in categories {
                let ids = CategoryHierarchy.idsIncludingDescendants(of: category, in: categories)
                let areaActivities = activities.filter { activity in
                    activity.category.map { ids.contains($0.id) } == true
                }
                await ReminderService.updateReminders(for: category, activities: areaActivities, center: RealNotificationCenter.shared)
            }
        }
    }
}

/// A single editable suggested Task in the onboarding starter plan. Purely
/// draft state -- nothing is persisted until the user reaches "Create".
private struct DraftOnboardingTask: Identifiable {
    let id = UUID()
    var name: String
    var weekdays: Set<Int>
    var startTime: Date
    var durationMinutes: Int
}

private struct LifeOSOnboardingView: View {
    let profile: Profile
    let onComplete: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Query private var categories: [AppCategory]
    @Query private var activities: [Activity]
    @Query private var goals: [Goal]
    @State private var step = 0
    @State private var saveFailed = false

    // Step 0 -- the improvement, in the user's own words.
    @State private var improvementText = ""

    // Step 1 -- the outcome that tells them it improved.
    @State private var outcomeName = ""
    @State private var valueType: ResultValueType = .number
    @State private var unit = ""
    @State private var direction: ResultDirection = .increase
    @State private var target = 0.0
    @State private var rangeMinimum = 0.0
    @State private var rangeMaximum = 0.0
    @State private var hasTargetDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now

    // Step 2 -- a gentle, fully-editable starter plan.
    @State private var areaName = ""
    @State private var draftTasks: [DraftOnboardingTask] = []
    @State private var didSeedDrafts = false
    @State private var wantsNutrition = false

    // Single-letter labels so all 7 chips fit one row without wrapping;
    // full names are exposed separately via accessibilityLabel below.
    private static let weekdayLetters = ["S", "M", "T", "W", "T", "F", "S"]
    private static let weekdayFullNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    init(profile: Profile, onComplete: @escaping () -> Void) {
        self.profile = profile
        self.onComplete = onComplete
        #if DEBUG
        // Screenshot-only seeding, gated by a launch argument never set
        // outside a manual capture run — see presentOnboardingIfNeeded() and
        // debugOnboardingScreenshotStep(). Fills in realistic values so all
        // three steps screenshot in a coherent, reviewable state instead of
        // blank placeholders.
        if let seededStep = debugOnboardingScreenshotStep() {
            let seededTime = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now
            _step = State(initialValue: seededStep)
            _improvementText = State(initialValue: "Get stronger")
            _outcomeName = State(initialValue: "Bench press")
            _unit = State(initialValue: "kg")
            _target = State(initialValue: 80)
            _areaName = State(initialValue: "Strength Training")
            _draftTasks = State(initialValue: [
                DraftOnboardingTask(name: "Bench press practice", weekdays: [2, 4, 6], startTime: seededTime, durationMinutes: 30)
            ])
            _didSeedDrafts = State(initialValue: true)
        }
        #endif
    }

    private var trimmedImprovement: String { improvementText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedOutcome: String { outcomeName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedAreaName: String { areaName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canContinueStep0: Bool { !trimmedImprovement.isEmpty }
    private var canContinueStep1: Bool {
        !trimmedOutcome.isEmpty && (valueType == .milestone || valueType == .text || validNumericTarget)
    }
    private var validNumericTarget: Bool {
        ResultMeasureValidation.isValidTarget(
            valueType: valueType, direction: direction,
            baseline: 0, target: target,
            minimum: rangeMinimum, maximum: rangeMaximum
        )
    }
    private var canCreate: Bool {
        !trimmedAreaName.isEmpty && !draftTasks.isEmpty
            && draftTasks.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.weekdays.isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 3)
                    .tint(.lifeOSAccent)
                    .padding(.horizontal, LifeOSSpacing.lg)
                    .padding(.top, LifeOSSpacing.sm)

                ScrollView {
                    VStack(alignment: .leading, spacing: LifeOSSpacing.lg) {
                        Group {
                            if step == 0 { improvementSetup }
                            else if step == 1 { outcomeSetup }
                            else { planSetup }
                        }
                    }
                    .padding(LifeOSSpacing.lg)
                }

                footer
            }
            .background(Color.lifeOSCanvas)
            .onChange(of: step) { _, newStep in
                if newStep == 2 { seedDraftsIfNeeded() }
            }
            #if DEBUG
            .task {
                guard step == 2, debugOnboardingAutoCreateRequested() else { return }
                try? await Task.sleep(nanoseconds: 500_000_000)
                createLifeOS()
            }
            #endif
            .alert("Couldn't Create LifeOS", isPresented: $saveFailed) {
                Button("Try Again") { createLifeOS() }
            } message: {
                Text("Your choices are still here. Please try saving them again.")
            }
        }
    }

    private var improvementSetup: some View {
        VStack(alignment: .leading, spacing: LifeOSSpacing.lg) {
            Text("What would you like to improve?")
                .font(.lifeOSScreenTitle)
            Text("Use your own words -- there's nothing to pick from a list.")
                .font(.lifeOSBody)
                .foregroundStyle(.secondary)
            LOCard {
                TextField("For example, get stronger, learn guitar, sleep better", text: $improvementText, axis: .vertical)
                    .font(.title3.weight(.medium))
            }
        }
    }

    private var outcomeSetup: some View {
        VStack(alignment: .leading, spacing: LifeOSSpacing.lg) {
            Text("How will you know?")
                .font(.lifeOSScreenTitle)
            Text("This is the outcome you'll observe. Tasks show your effort separately.")
                .font(.lifeOSBody)
                .foregroundStyle(.secondary)
            LOCard {
                VStack(alignment: .leading, spacing: LifeOSSpacing.md) {
                    TextField("Outcome, such as bench press", text: $outcomeName)
                        .onAppear { if outcomeName.isEmpty { outcomeName = trimmedImprovement } }
                    Picker("Result type", selection: $valueType) {
                        ForEach(ResultValueType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if valueType == .number || valueType == .rating {
                        TextField("Unit, such as %, kg, mph or seconds", text: $unit)
                        Picker("Desired result", selection: $direction) {
                            ForEach(ResultDirection.allCases) { Text($0.rawValue).tag($0) }
                        }
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
            Text("A gentle starting plan")
                .font(.lifeOSScreenTitle)
            Text("Ordinary Tasks and a Plan you can edit or remove anytime.")
                .font(.lifeOSBody)
                .foregroundStyle(.secondary)
            LOCard {
                TextField("Plan name", text: $areaName)
                    .font(.title3.weight(.medium))
            }
            ForEach($draftTasks) { $task in
                LOCard {
                    VStack(alignment: .leading, spacing: LifeOSSpacing.sm) {
                        HStack {
                            TextField("Task name", text: $task.name)
                                .font(.lifeOSCardTitle)
                            Spacer()
                            Button {
                                draftTasks.removeAll { $0.id == task.id }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: LifeOSSpacing.xs) {
                            ForEach(1...7, id: \.self) { weekday in
                                LOChip(
                                    title: Self.weekdayLetters[weekday - 1],
                                    isSelected: task.weekdays.contains(weekday)
                                ) {
                                    if task.weekdays.contains(weekday) { task.weekdays.remove(weekday) }
                                    else { task.weekdays.insert(weekday) }
                                }
                                .accessibilityLabel(Self.weekdayFullNames[weekday - 1])
                            }
                        }
                        HStack {
                            DatePicker("Time", selection: $task.startTime, displayedComponents: .hourAndMinute)
                            Stepper("\(task.durationMinutes) min", value: $task.durationMinutes, in: 5...180, step: 5)
                        }
                        .font(.lifeOSSecondary)
                    }
                }
            }
            Button {
                draftTasks.append(DraftOnboardingTask(name: "", weekdays: [2, 3, 4, 5, 6], startTime: defaultStartTime, durationMinutes: 30))
            } label: {
                Label("Add another Task", systemImage: "plus.circle.fill")
            }
            .buttonStyle(LifeOSTonalButtonStyle())
            Toggle(isOn: $wantsNutrition) {
                Label("Also track nutrition", systemImage: "fork.knife")
            }
            .toggleStyle(.switch)
            .tint(.lifeOSAccent)
            .padding(LifeOSSpacing.md)
            .lifeOSElevated(cornerRadius: LifeOSRadius.sm, tint: .lifeOSAccent)
            if wantsNutrition {
                Text("You can set your own daily targets anytime from Plans -- nothing is created for you yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var defaultStartTime: Date {
        Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now
    }

    private func seedDraftsIfNeeded() {
        guard !didSeedDrafts else { return }
        didSeedDrafts = true
        if areaName.isEmpty { areaName = trimmedImprovement }
        if draftTasks.isEmpty {
            draftTasks = [DraftOnboardingTask(name: "Work on \(trimmedImprovement)", weekdays: [2, 3, 4, 5, 6], startTime: defaultStartTime, durationMinutes: 30)]
        }
    }

    private var footer: some View {
        HStack(spacing: LifeOSSpacing.sm) {
            if step > 0 {
                Button("Back") { withAnimation(.lifeOSTap) { step -= 1 } }
                    .buttonStyle(LifeOSInlineButtonStyle(tint: .lifeOSAccent, emphasis: .raised))
            }
            LOPrimaryButton(
                title: step == 2 ? "Create" : "Continue",
                symbol: step == 2 ? "checkmark" : "arrow.right",
                isDisabled: step == 0 ? !canContinueStep0 : step == 1 ? !canContinueStep1 : !canCreate
            ) {
                if step < 2 { withAnimation(.lifeOSTap) { step += 1 } } else { createLifeOS() }
            }
        }
        .padding(LifeOSSpacing.lg)
        .background(.ultraThinMaterial)
    }

    private func createLifeOS() {
        removeUntouchedStarterContentIfNeeded()

        let totalWeeklySessions = draftTasks.reduce(0) { $0 + $1.weekdays.count }
        let totalWeeklyMinutes = draftTasks.reduce(0) { $0 + $1.weekdays.count * $1.durationMinutes }
        let category = AppCategory(
            profile: profile, name: trimmedAreaName, symbol: "sparkles", colorToken: "blue",
            pillar: .life, trackingKind: .tasks,
            purpose: "Move \(trimmedAreaName) forward through consistent action.",
            weeklyTargetSessions: totalWeeklySessions,
            weeklyTargetMinutes: totalWeeklyMinutes
        )
        let goal = Goal(profile: profile, name: trimmedImprovement, targetDate: hasTargetDate ? targetDate : nil)
        let measure = ResultMeasure(
            goal: goal, name: trimmedOutcome, role: .primary, valueType: valueType,
            unit: unit.trimmingCharacters(in: .whitespacesAndNewlines), direction: direction,
            targetValue: (valueType == .number || valueType == .rating) && (direction == .increase || direction == .decrease) ? target : nil,
            targetMinimum: (valueType == .number || valueType == .rating) && (direction == .targetRange || direction == .maintainRange) ? rangeMinimum : nil,
            targetMaximum: (valueType == .number || valueType == .rating) && (direction == .targetRange || direction == .maintainRange) ? rangeMaximum : nil
        )
        let contribution = GoalAreaContribution(
            goal: goal, category: category, statement: "\(trimmedAreaName) supports \(trimmedImprovement).",
            weeklyTargetSessions: category.weeklyTargetSessions, weeklyTargetMinutes: category.weeklyTargetMinutes
        )
        modelContext.insert(category)
        modelContext.insert(goal)
        modelContext.insert(measure)
        modelContext.insert(contribution)

        var createdActivities: [Activity] = []
        for task in draftTasks {
            let hour = Calendar.current.component(.hour, from: task.startTime)
            let minute = Calendar.current.component(.minute, from: task.startTime)
            let activity = Activity(
                profile: profile, category: category, name: task.name.trimmingCharacters(in: .whitespacesAndNewlines),
                source: .template, repeatType: .selectedWeekdays, weekdays: Array(task.weekdays).sorted(),
                plannedStartMinutes: hour * 60 + minute, estimatedDurationMinutes: task.durationMinutes
            )
            modelContext.insert(activity)
            createdActivities.append(activity)
        }

        guard modelContext.saveOrReport() else {
            discard([contribution], createdActivities, [goal], [category])
            modelContext.delete(measure)
            saveFailed = true
            return
        }
        let newItems: [CalendarItem]
        do {
            newItems = try PlanningService.insertMissingCalendarItems(
                profile: profile, date: .now, activities: activities + createdActivities,
                context: modelContext
            )
        } catch {
            PersistenceIssueCenter.shared.report(error)
            discard([contribution], createdActivities, [goal], [category])
            modelContext.delete(measure)
            saveFailed = true
            return
        }
        guard modelContext.saveOrReport() else {
            newItems.forEach(modelContext.delete)
            discard([contribution], createdActivities, [goal], [category])
            modelContext.delete(measure)
            _ = modelContext.saveOrReport()
            saveFailed = true
            return
        }
        onComplete()
    }

    private func discard(
        _ contributions: [GoalAreaContribution],
        _ activities: [Activity],
        _ goals: [Goal],
        _ categories: [AppCategory]
    ) {
        contributions.forEach(modelContext.delete)
        activities.forEach(modelContext.delete)
        goals.forEach(modelContext.delete)
        categories.forEach(modelContext.delete)
    }

    private func removeUntouchedStarterContentIfNeeded() {
        let starterNames: Set<String> = ["Movement", "Learning", "Nutrition", "Recovery"]
        let profileCategories = categories.filter { $0.profile?.id == profile.id }
        guard goals.allSatisfy({ $0.profile?.id != profile.id }),
              Set(profileCategories.map(\.name)).isSubset(of: starterNames) else { return }
        activities.filter { $0.profile?.id == profile.id }.forEach(modelContext.delete)
        profileCategories.forEach(modelContext.delete)
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Profile.self, SavedCategoryTemplate.self, AppCategory.self, Goal.self, GoalAreaContribution.self, ResultMeasure.self, ResultEntry.self, Activity.self, CalendarItem.self, ActivitySession.self, FoodEntry.self, WeightEntry.self, SportEntry.self], inMemory: true)
}
