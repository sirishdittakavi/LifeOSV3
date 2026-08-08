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
    @State private var selection = SelectedProfile()
    @State private var persistenceIssues = PersistenceIssueCenter.shared
    @Query(sort: \Profile.name) private var profiles: [Profile]
    @AppStorage("LifeOS.onboarding.v1.completed") private var onboardingCompleted = false
    @State private var showingOnboarding = false

    var body: some View {
        TabView {
            TodayTimelineView(selection: selection)
                .tabItem { Label("Today", systemImage: "calendar") }

            ImprovementCategoriesView(selection: selection)
                .tabItem { Label("Areas", systemImage: "square.grid.2x2") }

            ImprovementDashboardView(selection: selection)
                .tabItem { Label("Goals", systemImage: "scope") }

            WeeklyScheduleView(selection: selection)
                .tabItem { Label("Schedule", systemImage: "calendar.day.timeline.left") }
        }
        .alert("Couldn’t Save", isPresented: Binding(
            get: { persistenceIssues.message != nil },
            set: { if !$0 { persistenceIssues.message = nil } }
        )) {
            Button("OK") { persistenceIssues.message = nil }
        } message: {
            Text(persistenceIssues.message ?? "Please try again.")
        }
        .onAppear { presentOnboardingIfNeeded() }
        .onChange(of: profiles.count) { presentOnboardingIfNeeded() }
        .fullScreenCover(isPresented: $showingOnboarding) {
            if let profile = selection.profile ?? profiles.first(where: \.isActive) {
                LifeOSOnboardingView(profile: profile) {
                    onboardingCompleted = true
                    showingOnboarding = false
                }
                .interactiveDismissDisabled()
            }
        }
    }

    private func presentOnboardingIfNeeded() {
        guard !onboardingCompleted,
              let profile = profiles.first(where: \.isActive) else { return }
        if selection.profile == nil { selection.profile = profile }
        showingOnboarding = true
    }
}

private struct OnboardingPlan: Identifiable, Hashable {
    let id: String
    var areaName: String
    var symbol: String
    var color: String
    var pillar: ImprovementPillar
    var goalName: String
    var taskName: String
    var weekdays: [Int]
    var startMinutes: Int
    var duration: Int

    static let suggestions: [OnboardingPlan] = [
        .init(id: "career", areaName: "Career", symbol: "briefcase.fill", color: "purple", pillar: .learning, goalName: "Move my career forward", taskName: "Focused career work", weekdays: [2, 3, 4, 5, 6], startMinutes: 9 * 60, duration: 45),
        .init(id: "health", areaName: "Health", symbol: "heart.fill", color: "red", pillar: .physical, goalName: "Build better health", taskName: "Health routine", weekdays: [2, 4, 6], startMinutes: 7 * 60, duration: 30),
        .init(id: "nutrition", areaName: "Nutrition", symbol: "fork.knife", color: "green", pillar: .nutrition, goalName: "Improve my nutrition", taskName: "Plan and log meals", weekdays: [1, 2, 3, 4, 5, 6, 7], startMinutes: 18 * 60, duration: 10),
        .init(id: "sports", areaName: "Sports", symbol: "figure.run", color: "orange", pillar: .sport, goalName: "Improve my performance", taskName: "Training session", weekdays: [2, 4, 6], startMinutes: 17 * 60, duration: 60),
        .init(id: "family", areaName: "Family", symbol: "figure.2.and.child.holdinghands", color: "pink", pillar: .life, goalName: "Be more present with family", taskName: "Family time", weekdays: [1, 7], startMinutes: 17 * 60, duration: 60),
        .init(id: "growth", areaName: "Personal Growth", symbol: "leaf.fill", color: "teal", pillar: .life, goalName: "Keep growing", taskName: "Personal growth practice", weekdays: [2, 3, 4, 5, 6], startMinutes: 20 * 60, duration: 20),
        .init(id: "routine", areaName: "Daily Routine", symbol: "checklist", color: "blue", pillar: .life, goalName: "Build a reliable routine", taskName: "Daily reset", weekdays: [1, 2, 3, 4, 5, 6, 7], startMinutes: 20 * 60, duration: 15)
    ]
}

private struct LifeOSOnboardingView: View {
    let profile: Profile
    let onComplete: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Query private var categories: [AppCategory]
    @Query private var activities: [Activity]
    @Query private var goals: [Goal]
    @State private var step = 0
    @State private var selectedIDs: Set<String> = []
    @State private var customPlans: [OnboardingPlan] = []
    @State private var customAreaName = ""
    @State private var customGoalName = ""
    @State private var customTaskName = ""
    @State private var startTime = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now
    @State private var saveFailed = false

    private var selectedPlans: [OnboardingPlan] {
        OnboardingPlan.suggestions.filter { selectedIDs.contains($0.id) } + customPlans
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 3)
                    .tint(.cyan)
                    .padding(.horizontal, LifeOSSpacing.lg)
                Group {
                    if step == 0 { areaSelection }
                    else if step == 1 { planSelection }
                    else { scheduleSelection }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                if step > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { withAnimation { step -= 1 } }
                    }
                }
            }
            .alert("Couldn’t Create LifeOS", isPresented: $saveFailed) {
                Button("Try Again") { createLifeOS() }
            } message: {
                Text("Your choices are still here. Please try saving them again.")
            }
        }
    }

    private var areaSelection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeOSSpacing.lg) {
                onboardingHeading("What do you want to move forward?", "Choose as many life areas as you want. You can change everything later.")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(OnboardingPlan.suggestions) { plan in
                        let selected = selectedIDs.contains(plan.id)
                        Button {
                            if selected { selectedIDs.remove(plan.id) } else { selectedIDs.insert(plan.id) }
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                Image(systemName: plan.symbol).font(.title2)
                                Text(plan.areaName).font(.headline).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .padding(16).frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
                            .background(selected ? ColorToken.color(for: plan.color) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain)
                    }
                }
                addCustomArea
            }.padding(LifeOSSpacing.lg)
        }
    }

    private var addCustomArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Add your own", systemImage: "plus.circle.fill").font(.headline)
            HStack {
                TextField("Life area", text: $customAreaName)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let name = customAreaName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    customPlans.append(.init(id: UUID().uuidString, areaName: name, symbol: "sparkles", color: "blue", pillar: .life, goalName: "Move \(name) forward", taskName: "Work on \(name)", weekdays: [2, 3, 4, 5, 6], startMinutes: 18 * 60, duration: 30))
                    customAreaName = ""
                }.disabled(customAreaName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ForEach(customPlans) { plan in
                HStack { Label(plan.areaName, systemImage: "checkmark.circle.fill"); Spacer(); Button("Remove") { customPlans.removeAll { $0.id == plan.id } }.font(.caption) }
            }
        }.padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var planSelection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeOSSpacing.lg) {
                onboardingHeading("Your starting plan", "LifeOS has generated one Goal and one Task for each area. These are ordinary items—you can edit or replace them anytime.")
                ForEach(selectedPlans) { plan in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(plan.areaName, systemImage: plan.symbol).font(.headline)
                        Label(plan.goalName, systemImage: "scope").foregroundStyle(.secondary)
                        Label(plan.taskName, systemImage: "checkmark.square").foregroundStyle(.secondary)
                    }.lifeOSGlassCard(tint: ColorToken.color(for: plan.color))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label("Add your own Goal or Task", systemImage: "plus.circle.fill").font(.headline)
                    TextField("Goal (optional)", text: $customGoalName).textFieldStyle(.roundedBorder)
                    TextField("Task (optional)", text: $customTaskName).textFieldStyle(.roundedBorder)
                    Text("Your own items use the same Goal and Task system as LifeOS suggestions.").font(.caption).foregroundStyle(.secondary)
                }.padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }.padding(LifeOSSpacing.lg)
        }
    }

    private var scheduleSelection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LifeOSSpacing.lg) {
                onboardingHeading("When should LifeOS begin?", "Your Tasks will appear on Today automatically. Fine-tune individual days and times in Schedule.")
                DatePicker("Preferred start time", selection: $startTime, displayedComponents: .hourAndMinute)
                    .padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 12) {
                    Label("Your LifeOS is ready", systemImage: "snowflake").font(.title3.bold()).foregroundStyle(.cyan)
                    Text("\(selectedPlans.count) areas · \(selectedPlans.count + (customGoalName.isEmpty ? 0 : 1)) goals · \(selectedPlans.count + (customTaskName.isEmpty ? 0 : 1)) recurring Tasks")
                        .foregroundStyle(.secondary)
                    Label("Add your own schedule anytime", systemImage: "plus.circle").font(.subheadline.weight(.semibold))
                }.lifeOSGlassCard(tint: .cyan)
            }.padding(LifeOSSpacing.lg)
        }
    }

    private func onboardingHeading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        Button(step == 2 ? "Create My LifeOS" : "Continue") {
            if step < 2 { withAnimation { step += 1 } } else { createLifeOS() }
        }
        .buttonStyle(LifeOSPrimaryButtonStyle())
        .disabled(step == 0 && selectedPlans.isEmpty)
        .padding(LifeOSSpacing.lg)
        .background(.ultraThinMaterial)
    }

    private func createLifeOS() {
        let hour = Calendar.current.component(.hour, from: startTime)
        let minute = Calendar.current.component(.minute, from: startTime)
        var createdCategories: [AppCategory] = []
        var createdActivities: [Activity] = []
        var createdGoals: [Goal] = []
        var createdContributions: [GoalAreaContribution] = []

        removeUntouchedStarterContentIfNeeded()
        for plan in selectedPlans {
            let category = AppCategory(profile: profile, name: plan.areaName, symbol: plan.symbol, colorToken: plan.color, pillar: plan.pillar, trackingKind: plan.id == "nutrition" ? .nutrition : (plan.id == "sports" ? .sport : .tasks), purpose: "Move \(plan.areaName) forward through consistent action.", weeklyTargetSessions: plan.weekdays.count, weeklyTargetMinutes: plan.duration * plan.weekdays.count)
            let goal = Goal(profile: profile, name: plan.goalName, purpose: "Supported by \(plan.areaName).")
            let task = Activity(profile: profile, category: category, name: plan.taskName, source: .template, targetValue: Double(plan.duration), targetUnit: "min", repeatType: .selectedWeekdays, weekdays: plan.weekdays, plannedStartMinutes: hour * 60 + minute, estimatedDurationMinutes: plan.duration)
            let contribution = GoalAreaContribution(goal: goal, category: category, statement: "Consistent \(plan.areaName) work supports this Goal.", weeklyTargetSessions: plan.weekdays.count, weeklyTargetMinutes: plan.duration * plan.weekdays.count)
            modelContext.insert(category)
            modelContext.insert(goal)
            modelContext.insert(task)
            modelContext.insert(contribution)
            createdCategories.append(category); createdActivities.append(task); createdGoals.append(goal)
            createdContributions.append(contribution)
        }
        if let category = createdCategories.first {
            let goalText = customGoalName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !goalText.isEmpty {
                let goal = Goal(profile: profile, name: goalText)
                let contribution = GoalAreaContribution(goal: goal, category: category)
                modelContext.insert(goal); modelContext.insert(contribution)
                createdGoals.append(goal); createdContributions.append(contribution)
            }
            let taskText = customTaskName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !taskText.isEmpty {
                let task = Activity(profile: profile, category: category, name: taskText, plannedStartMinutes: hour * 60 + minute, estimatedDurationMinutes: 30)
                modelContext.insert(task); createdActivities.append(task)
            }
        }
        guard modelContext.saveOrReport() else {
            discard(createdContributions, createdActivities, createdGoals, createdCategories)
            saveFailed = true; return
        }
        let newItems = PlanningService.generateMissingCalendarItems(profile: profile, date: .now, activities: activities + createdActivities, existingItems: [])
        newItems.forEach(modelContext.insert)
        guard modelContext.saveOrReport() else {
            newItems.forEach(modelContext.delete)
            discard(createdContributions, createdActivities, createdGoals, createdCategories)
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
