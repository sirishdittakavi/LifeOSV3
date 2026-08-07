import SwiftUI
import SwiftData

enum CategoryCreationMode {
    case templates
    case custom
}

struct AddImprovementCategoryView: View {
    let profile: Profile
    let parentCategory: AppCategory?
    let startMode: CategoryCreationMode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedCategoryTemplate.createdAt, order: .reverse) private var savedTemplates: [SavedCategoryTemplate]

    init(
        profile: Profile,
        parentCategory: AppCategory? = nil,
        startMode: CategoryCreationMode = .templates
    ) {
        self.profile = profile
        self.parentCategory = parentCategory
        self.startMode = startMode
    }

    var body: some View {
        NavigationStack {
            Group {
                if startMode == .custom {
                    ConfigureImprovementCategoryView(
                        profile: profile, parentCategory: parentCategory,
                        template: nil, onCreated: { dismiss() }
                    )
                } else {
                    List {
                        Section {
                            Text(parentCategory.map {
                                "Choose an editable starting point inside \($0.name)."
                            } ?? "Templates are editable starting points. Review the targets and schedule before creating the category.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Section("Templates") {
                            ForEach(ImprovementTemplates.all) { template in
                                NavigationLink {
                                    ConfigureImprovementCategoryView(
                                        profile: profile, parentCategory: parentCategory,
                                        template: template, onCreated: { dismiss() }
                                    )
                                } label: {
                                    Label {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(template.name)
                                            Text("\(template.weeklySessions) sessions · \(template.weeklyMinutes) min/week")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        Image(systemName: template.symbol)
                                            .foregroundStyle(ColorToken.color(for: template.colorToken))
                                    }
                                }
                            }
                        }

                        if !savedTemplates.isEmpty {
                            Section("My Saved Templates") {
                                ForEach(savedTemplates) { saved in
                                    NavigationLink {
                                        ConfigureImprovementCategoryView(
                                            profile: profile, parentCategory: parentCategory,
                                            template: saved.improvementTemplate,
                                            onCreated: { dismiss() }
                                        )
                                    } label: {
                                        Label {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(saved.name)
                                                Text("\(saved.taskBlueprints.count) tasks · saved \(saved.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                        } icon: {
                                            Image(systemName: saved.symbol)
                                                .foregroundStyle(ColorToken.color(for: saved.colorToken))
                                        }
                                    }
                                    .swipeActions {
                                        Button("Delete", role: .destructive) {
                                            modelContext.delete(saved)
                                            try? modelContext.save()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Choose Template")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

private struct ConfigureImprovementCategoryView: View {
    let profile: Profile
    let parentCategory: AppCategory?
    let template: ImprovementCategoryTemplate?
    let onCreated: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Query private var allCategories: [AppCategory]

    @State private var name: String
    @State private var pillar: ImprovementPillar
    @State private var purpose: String
    @State private var sessions: Int
    @State private var minutes: Int
    @State private var reminderEnabled = false
    @State private var reminderTime = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now
    @State private var customTaskName = ""
    @State private var parentCategoryID: UUID?
    @State private var symbol: String
    @State private var colorToken: String

    init(
        profile: Profile,
        parentCategory: AppCategory?,
        template: ImprovementCategoryTemplate?,
        onCreated: @escaping () -> Void
    ) {
        self.profile = profile
        self.parentCategory = parentCategory
        self.template = template
        self.onCreated = onCreated
        _name = State(initialValue: template?.name ?? "")
        _pillar = State(initialValue: parentCategory?.pillar ?? template?.pillar ?? .physical)
        _purpose = State(initialValue: template?.purpose ?? "")
        _sessions = State(initialValue: template?.weeklySessions ?? 3)
        _minutes = State(initialValue: template?.weeklyMinutes ?? 120)
        _parentCategoryID = State(initialValue: parentCategory?.id)
        _symbol = State(initialValue: template?.symbol ?? "target")
        _colorToken = State(initialValue: template?.colorToken ?? "blue")
    }

    private var profileCategories: [AppCategory] {
        allCategories.filter { $0.profile?.id == profile.id && $0.isActive }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        Form {
            Section("Improvement area") {
                TextField("Name", text: $name)
                Picker("Pillar", selection: $pillar) {
                    ForEach(ImprovementPillar.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Why does this matter?", text: $purpose, axis: .vertical)
                Picker("Icon", selection: $symbol) {
                    ForEach(CategoryAppearanceOptions.icons) { option in
                        Label(option.name, systemImage: option.symbol).tag(option.symbol)
                    }
                }
                Picker("Colour", selection: $colorToken) {
                    ForEach(CategoryAppearanceOptions.colors, id: \.self) { token in
                        Label(token.capitalized, systemImage: "circle.fill")
                            .foregroundStyle(ColorToken.color(for: token))
                            .tag(token)
                    }
                }
            }

            Section("Placement") {
                Picker("Inside", selection: $parentCategoryID) {
                    Text("Top-level improvement area").tag(UUID?.none)
                    ForEach(profileCategories) { category in
                        Text(CategoryHierarchy.breadcrumbName(for: category, in: profileCategories))
                            .tag(UUID?.some(category.id))
                    }
                }
                Text("Use a parent when this is a program, subject, team, project, or training stream inside a broader area.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Weekly commitment") {
                Stepper("\(sessions) sessions per week", value: $sessions, in: 0...21)
                Stepper("\(minutes) minutes per week", value: $minutes, in: 0...1200, step: 15)
            }

            Section("Tasks") {
                if let template, !template.tasks.isEmpty {
                    ForEach(template.tasks) { task in
                        VStack(alignment: .leading) {
                            Text(task.name)
                            Text("\(task.durationMinutes) min · \(task.repeatType.rawValue)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    TextField("First task or habit", text: $customTaskName)
                    Text("You can add more detailed tasks after creating the category.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Reminder") {
                Toggle("Enable category reminder", isOn: $reminderEnabled)
                if reminderEnabled {
                    DatePicker("Reminder time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                }
            }

            Section {
                Button("Create and Approve Plan", action: create)
                    .frame(maxWidth: .infinity)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle(template == nil ? "Custom Category" : "Review Template")
    }

    private func create() {
        let category = AppCategory(
            profile: profile,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            symbol: symbol,
            colorToken: colorToken,
            pillar: pillar,
            purpose: purpose,
            weeklyTargetSessions: sessions,
            weeklyTargetMinutes: minutes
        )
        category.parentCategoryID = parentCategoryID
        category.reminderEnabled = reminderEnabled
        category.reminderHour = Calendar.current.component(.hour, from: reminderTime)
        category.reminderMinute = Calendar.current.component(.minute, from: reminderTime)
        contextInsert(category)

        let profileCategories = allCategories.filter { $0.profile?.id == profile.id }
        category.relatedCategoryIDs = (template?.relatedNames ?? []).compactMap { relatedName in
            profileCategories.first { $0.name.localizedCaseInsensitiveContains(relatedName) }?.id
        }

        var createdActivities: [Activity] = []
        if let template {
            template.tasks.forEach { task in
                let activity = Activity(
                    profile: profile, category: category, name: task.name, source: .template,
                    targetValue: task.targetValue, targetUnit: task.targetUnit,
                    repeatType: task.repeatType, weekdays: task.weekdays,
                    occurrencesPerDay: task.occurrencesPerDay,
                    occurrencesPerWeek: task.occurrencesPerWeek,
                    repeatIntervalMinutes: task.repeatIntervalMinutes,
                    plannedStartMinutes: task.startMinutes,
                    estimatedDurationMinutes: task.durationMinutes
                )
                contextInsert(activity)
                createdActivities.append(activity)
            }
        } else if !customTaskName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let activity = Activity(
                profile: profile, category: category,
                name: customTaskName.trimmingCharacters(in: .whitespacesAndNewlines),
                source: .manual, repeatType: .selectedWeekdays, weekdays: [2, 4, 6],
                plannedStartMinutes: category.reminderHour * 60 + category.reminderMinute,
                estimatedDurationMinutes: max(15, minutes / max(sessions, 1))
            )
            contextInsert(activity)
            createdActivities.append(activity)
        }

        try? modelContext.save()
        Task { await ReminderService.updateReminders(for: category, activities: createdActivities) }
        onCreated()
    }

    private func contextInsert<T: PersistentModel>(_ model: T) {
        modelContext.insert(model)
    }
}
