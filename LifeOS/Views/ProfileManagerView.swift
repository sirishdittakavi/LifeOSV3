import SwiftUI
import SwiftData

struct ProfileManagerView: View {
    @Bindable var selection: SelectedProfile
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Profile.name) private var profiles: [Profile]
    @State private var showingAddProfile = false
    @State private var editingProfile: Profile?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Each person has a separate calendar, categories, goals, food, weight, sport logs, and progress. Switching profile never combines their results.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Family Profiles") {
                    ForEach(profiles.filter(\.isActive)) { profile in
                        Button {
                            selection.profile = profile
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: profile.kind == .child ? "figure.and.child.holdinghands" : "person.crop.circle.fill")
                                    .frame(width: 36, height: 36)
                                    .background(ColorToken.color(for: profile.colorToken).opacity(0.15))
                                    .foregroundStyle(ColorToken.color(for: profile.colorToken))
                                    .clipShape(Circle())
                                VStack(alignment: .leading) {
                                    Text(profile.name).font(.headline).foregroundStyle(.primary)
                                    Text(profile.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selection.profile?.id == profile.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Edit") { editingProfile = profile }.tint(.blue)
                        }
                        .contextMenu {
                            Button("Edit Profile") { editingProfile = profile }
                        }
                    }
                }

                Section {
                    Button { showingAddProfile = true } label: {
                        Label("Add Adult or Child Profile", systemImage: "person.badge.plus")
                    }
                }

                Section("Data Safety") {
                    NavigationLink {
                        BackupCenterView()
                    } label: {
                        Label("Backup & Restore", systemImage: "externaldrive.badge.icloud")
                    }
                }
            }
            .navigationTitle("Profiles")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showingAddProfile) {
                NewProfileView(selection: selection)
            }
            .sheet(item: $editingProfile) { profile in
                EditProfileView(profile: profile)
            }
        }
    }
}

private struct NewProfileView: View {
    @Bindable var selection: SelectedProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: ProfileKind = .child
    @State private var colorToken = "blue"
    @State private var starterPlan: ProfileStarterPlan = .studentAndSport

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    TextField("Name", text: $name)
                    Picker("Profile type", selection: $kind) {
                        ForEach(ProfileKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Colour", selection: $colorToken) {
                        ForEach(CategoryAppearanceOptions.colors, id: \.self) { token in
                            Text(token.capitalized).tag(token)
                        }
                    }
                }

                Section("Starting Setup") {
                    Picker("Starter plan", selection: $starterPlan) {
                        ForEach(ProfileStarterPlan.allCases) { plan in
                            Text(plan.rawValue).tag(plan)
                        }
                    }
                    Text(starterPlan.explanation)
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Everything created by a starter plan is editable or removable.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: kind) { _, newKind in
                starterPlan = newKind == .child ? .studentAndSport : .healthAndCareer
            }
        }
    }

    private func create() {
        let profile = Profile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            colorToken: colorToken
        )
        modelContext.insert(profile)
        starterPlan.install(for: profile, context: modelContext)
        try? modelContext.save()
        selection.profile = profile
        dismiss()
    }
}

private struct EditProfileView: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    TextField("Name", text: $profile.name)
                    Picker("Profile type", selection: Binding(
                        get: { profile.kind }, set: { profile.kind = $0 }
                    )) {
                        ForEach(ProfileKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Colour", selection: $profile.colorToken) {
                        ForEach(CategoryAppearanceOptions.colors, id: \.self) { token in
                            Text(token.capitalized).tag(token)
                        }
                    }
                }

                Section {
                    NavigationLink("Goals, nutrition and units") {
                        ProfileGoalsForm(profile: profile)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ProfileGoalsForm: View {
    @Bindable var profile: Profile

    var body: some View {
        Form {
            Picker("Weight unit", selection: Binding(
                get: { profile.weightUnit }, set: { profile.weightUnit = $0 }
            )) {
                ForEach(WeightUnit.allCases) { Text($0.rawValue).tag($0) }
            }
            TextField("Daily calories", value: $profile.calorieGoal, format: .number)
                .keyboardType(.decimalPad)
            TextField("Daily protein (g)", value: $profile.proteinGoalGrams, format: .number)
                .keyboardType(.decimalPad)
            TextField("Daily water (ml)", value: $profile.waterGoalMilliliters, format: .number)
                .keyboardType(.decimalPad)
        }
        .navigationTitle("Profile Goals")
    }
}

enum ProfileStarterPlan: String, CaseIterable, Identifiable {
    case blank = "Blank - choose everything"
    case balanced = "Balanced basics"
    case studentAndSport = "Student and sport"
    case healthAndCareer = "Health and career"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .blank: return "Starts with no categories or tasks."
        case .balanced: return "Adds editable movement, learning, nutrition, relationships, and recovery areas."
        case .studentAndSport: return "Adds editable school, sport training, mobility, nutrition, and recovery areas."
        case .healthAndCareer: return "Adds editable health, career, nutrition, and recovery areas."
        }
    }

    func install(for profile: Profile, context: ModelContext) {
        switch self {
        case .blank:
            return
        case .balanced:
            add(profile, "Movement", "figure.run", "blue", .physical, 4, 160,
                task: ("Move or train", [2, 4, 6, 7], 18 * 60, 40), context: context)
            add(profile, "Learning", "lightbulb.fill", "yellow", .learning, 5, 150,
                task: ("Focused learning", [2, 3, 4, 5, 6], 19 * 60, 30), context: context)
            add(profile, "Nutrition", "fork.knife", "green", .nutrition, 7, 0, task: nil, context: context)
            add(profile, "Relationships", "person.2.fill", "pink", .life, 3, 120, task: nil, context: context)
            add(profile, "Recovery", "bed.double.fill", "indigo", .physical, 7, 70,
                task: ("Recovery check-in", [1, 2, 3, 4, 5, 6, 7], 20 * 60 + 30, 10), context: context)
        case .studentAndSport:
            add(profile, "School", "book.fill", "indigo", .learning, 5, 225,
                task: ("Homework or study", [2, 3, 4, 5, 6], 17 * 60, 45), context: context)
            add(profile, "Sport Training", "figure.run", "orange", .sport, 3, 180,
                task: ("Team or skill practice", [2, 4, 6], 18 * 60, 60), context: context)
            add(profile, "Mobility", "figure.flexibility", "teal", .physical, 5, 75,
                task: ("Mobility routine", [2, 3, 4, 5, 6], 7 * 60 + 30, 15), context: context)
            add(profile, "Nutrition", "fork.knife", "green", .nutrition, 7, 0, task: nil, context: context)
            add(profile, "Recovery", "bed.double.fill", "indigo", .physical, 7, 70,
                task: ("Recovery check-in", [1, 2, 3, 4, 5, 6, 7], 20 * 60 + 30, 10), context: context)
        case .healthAndCareer:
            add(profile, "Health & Fitness", "heart.fill", "red", .physical, 4, 200,
                task: ("Exercise", [2, 3, 5, 7], 7 * 60, 50), context: context)
            add(profile, "Career", "briefcase.fill", "blue", .learning, 5, 300,
                task: ("Focused work", [2, 3, 4, 5, 6], 9 * 60, 60), context: context)
            add(profile, "Nutrition", "fork.knife", "green", .nutrition, 7, 0, task: nil, context: context)
            add(profile, "Recovery", "bed.double.fill", "indigo", .physical, 7, 70,
                task: ("Recovery check-in", [1, 2, 3, 4, 5, 6, 7], 20 * 60 + 30, 10), context: context)
        }
    }

    private func add(
        _ profile: Profile, _ name: String, _ symbol: String, _ color: String,
        _ pillar: ImprovementPillar, _ sessions: Int, _ minutes: Int,
        task: (String, [Int], Int, Int)?, context: ModelContext
    ) {
        let category = AppCategory(
            profile: profile, name: name, symbol: symbol, colorToken: color,
            pillar: pillar, purpose: "Build consistent progress through an editable starter plan.",
            weeklyTargetSessions: sessions, weeklyTargetMinutes: minutes
        )
        context.insert(category)
        if let task {
            context.insert(Activity(
                profile: profile, category: category, name: task.0, source: .template,
                repeatType: .selectedWeekdays, weekdays: task.1,
                plannedStartMinutes: task.2, estimatedDurationMinutes: task.3
            ))
        }
    }
}
