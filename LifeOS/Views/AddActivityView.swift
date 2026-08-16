//
//  AddActivityView.swift
//  LifeOS
//
//  Quick Add: title, Plan, and When only. Everything else (target,
//  measurements, tags, reminders, duration, advanced recurrence) is an
//  explicit "Add details" step into EditTaskView after creation, per the v3
//  execution plan Chunk 2 — a basic Task must be creatable in seconds.
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

    @State private var isRecurring = false
    @State private var selectedWeekdays: Set<Int> = []
    // Always at least an hour out, regardless of what time it is right now
    // -- a fixed "6 pm today" default silently became a past time (and thus
    // an invalid one-time Task) for the rest of every day after 6 pm.
    @State private var when: Date = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)

    @State private var createdActivity: Activity?
    @State private var showingDetails = false

    private let weekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var profileCategories: [AppCategory] {
        categories.filter { $0.profile?.id == profile.id && $0.isActive }
    }

    private var hasValidCategory: Bool {
        selectedCategory.map { ProfileScope.canAssign($0, to: profile) } == true
            || (isCreatingCategory && !newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// A one-time Task's date/time must still be in the future the moment
    /// Create is tapped, not just when this view first appeared -- the
    /// DatePicker's `in: Date.now...` range only constrains what the user
    /// can pick, it does not re-validate a value that has since aged past
    /// "now" while the sheet sat open.
    private var oneTimeWhenIsValid: Bool { isRecurring || when >= Date.now }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        hasValidCategory &&
        (!isRecurring || !selectedWeekdays.isEmpty) &&
        oneTimeWhenIsValid
    }

    #if DEBUG
    private let debugAutoCreate: Bool
    #endif

    init(profile: Profile, initialCategory: AppCategory? = nil) {
        self.profile = profile
        _selectedCategory = State(initialValue:
            initialCategory?.profile?.id == profile.id && initialCategory?.isActive == true ? initialCategory : nil
        )
        #if DEBUG
        debugAutoCreate = false
        #endif
    }

    #if DEBUG
    /// Screenshot-only: lands directly on the post-create confirmation, the
    /// same way tapping Create would, without simulator tap automation.
    init(profile: Profile, debugAutoCreate: Bool) {
        self.profile = profile
        _selectedCategory = State(initialValue: nil)
        _name = State(initialValue: "Evening reading")
        self.debugAutoCreate = debugAutoCreate
    }
    #endif

    var body: some View {
        NavigationStack {
            Group {
                if let createdActivity {
                    createdConfirmation(createdActivity)
                } else {
                    quickAddForm
                }
            }
            .navigationTitle(createdActivity == nil ? "New Task" : "Task Created")
            .navigationBarTitleDisplayMode(.large)
            #if DEBUG
            .onAppear {
                guard debugAutoCreate, createdActivity == nil else { return }
                if selectedCategory == nil { isCreatingCategory = profileCategories.isEmpty }
                if let firstCategory = profileCategories.first { selectedCategory = firstCategory }
                else { isCreatingCategory = true; newCategoryName = "Reading" }
                save()
            }
            #endif
            .toolbar {
                if createdActivity == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { save() }
                            .disabled(!canSave)
                    }
                }
            }
            .onAppear {
                if profileCategories.isEmpty {
                    isCreatingCategory = true
                }
            }
            .sheet(isPresented: $showingDetails, onDismiss: { dismiss() }) {
                if let createdActivity {
                    EditTaskView(activity: createdActivity)
                }
            }
        }
    }

    private var quickAddForm: some View {
        Form {
            Section("Task") {
                TextField("What do you want to do?", text: $name)
                Text("Examples: Batting practice, homework, walk, study Swift")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Plan") {
                if isCreatingCategory {
                    TextField("New Plan name, e.g. Speed", text: $newCategoryName)
                    Text("This creates a simple top-level Plan. You can organise it later if needed.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !profileCategories.isEmpty {
                        Button("Choose an existing Plan") { isCreatingCategory = false }
                            .font(.caption)
                    }
                } else {
                    Picker("Plan", selection: $selectedCategory) {
                        Text("Choose a Plan").tag(AppCategory?.none)
                        ForEach(profileCategories) { category in
                            Text(CategoryHierarchy.breadcrumbName(for: category, in: profileCategories))
                                .tag(AppCategory?.some(category))
                        }
                    }
                    Button {
                        isCreatingCategory = true
                        selectedCategory = nil
                    } label: {
                        Label("Create a new Plan here", systemImage: "plus.circle.fill")
                    }
                }
            }

            Section("When") {
                Toggle("Repeats", isOn: $isRecurring.animation())
                if isRecurring {
                    Text("Days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    weekdayPicker
                    DatePicker("Time", selection: $when, displayedComponents: .hourAndMinute)
                } else {
                    DatePicker("Date & time", selection: $when, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                }
            }
        }
    }

    private func createdConfirmation(_ activity: Activity) -> some View {
        VStack(spacing: LifeOSSpacing.lg) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.lifeOSOnTrack)
            Text("“\(activity.name)” is on your Plan.")
                .font(.lifeOSScreenTitle)
                .multilineTextAlignment(.center)
            Text("Add a target, measurements, tags, reminders, or fine-tune the schedule anytime — or you're already done.")
                .font(.lifeOSBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LifeOSSpacing.xl)
            Spacer()
            VStack(spacing: LifeOSSpacing.sm) {
                LOPrimaryButton(title: "Add Details", symbol: "slider.horizontal.3") {
                    showingDetails = true
                }
                Button("Done") { dismiss() }
                    .buttonStyle(LifeOSSecondaryButtonStyle())
            }
            .padding(.horizontal, LifeOSSpacing.lg)
        }
        .padding(.bottom, LifeOSSpacing.xl)
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

    private func save() {
        // Create-time validation, not just the Create button's .disabled --
        // canSave (including oneTimeWhenIsValid) must hold at the moment of
        // persistence, not merely when the button was last enabled/rendered.
        guard canSave else { return }

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
        let minutesSinceMidnight = calendar.component(.hour, from: when) * 60 + calendar.component(.minute, from: when)

        let activity = Activity(
            profile: profile,
            category: category,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .manual,
            repeatType: isRecurring ? .selectedWeekdays : .once,
            weekdays: isRecurring ? Array(selectedWeekdays) : [],
            plannedStartMinutes: minutesSinceMidnight,
            estimatedDurationMinutes: 30,
            startDate: isRecurring ? calendar.startOfDay(for: .now) : calendar.startOfDay(for: when)
        )
        modelContext.insert(activity)

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
            modelContext.delete(activity)
            if let category, isCreatingCategory { modelContext.delete(category) }
            return
        }

        if modelContext.saveOrReport() {
            refreshReminders(afterAdding: activity, to: category)
            createdActivity = activity
        } else {
            newItems.forEach { modelContext.delete($0) }
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
                await ReminderService.updateReminders(for: reminderArea, activities: reminderActivities, center: RealNotificationCenter.shared)
            }
        }
    }
}

#Preview {
    let profile = Profile(name: "Sirish", kind: .parent, colorToken: "blue")
    AddActivityView(profile: profile)
        .modelContainer(for: [Profile.self, SavedCategoryTemplate.self, AppCategory.self, Goal.self, GoalAreaContribution.self, ResultMeasure.self, ResultEntry.self, Activity.self, CalendarItem.self, ActivitySession.self, FoodEntry.self, WeightEntry.self, SportEntry.self, Relationship.self, MeasurementDefinition.self, MeasurementEntry.self], inMemory: true)
}
