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
                                "Choose an editable Area Template inside \($0.name)."
                            } ?? "Area Templates create an Area and a few editable Tasks. Nothing is locked.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Section("Starter Areas") {
                            // Only top-level templates appear here — a
                            // template that another template nests under
                            // (e.g. Baseball under Sports) is reached by
                            // navigating into its parent, not listed
                            // alongside it (Refactor.md Run 4).
                            ForEach(ImprovementTemplates.all.filter { $0.parentTemplateID == nil }) { template in
                                let children = ImprovementTemplates.all.filter { $0.parentTemplateID == template.id }
                                NavigationLink {
                                    if children.isEmpty {
                                        ConfigureImprovementCategoryView(
                                            profile: profile, parentCategory: parentCategory,
                                            template: template, onCreated: { dismiss() }
                                        )
                                    } else {
                                        TemplateDisciplineListView(
                                            profile: profile, parentCategory: parentCategory,
                                            containerTemplate: template, childTemplates: children,
                                            onCreated: { dismiss() }
                                        )
                                    }
                                } label: {
                                    Label {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(template.name)
                                            Text(children.isEmpty
                                                 ? "\(template.weeklySessions) times · \(template.weeklyMinutes) min/week"
                                                 : "\(children.count) discipline\(children.count == 1 ? "" : "s")")
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
                            Section("My Saved Areas") {
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
                                                Text("\(saved.taskBlueprints.count) Tasks · saved \(saved.createdAt.formatted(date: .abbreviated, time: .omitted))")
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
                                            modelContext.saveOrReport()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Choose an Area")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

/// Reached when a top-level template (e.g. "Sports") has children (e.g.
/// "Baseball") — Refactor.md Run 4. Lets the user either create the
/// container itself as a general Area, or drill into one of its
/// disciplines, instead of every discipline appearing as a duplicate
/// top-level "Starter Area."
private struct TemplateDisciplineListView: View {
    let profile: Profile
    let parentCategory: AppCategory?
    let containerTemplate: ImprovementCategoryTemplate
    let childTemplates: [ImprovementCategoryTemplate]
    let onCreated: () -> Void

    var body: some View {
        List {
            Section {
                Text("\(containerTemplate.name) groups related disciplines. Choose one below, or create \(containerTemplate.name) itself as a general Area.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(containerTemplate.name) {
                NavigationLink {
                    ConfigureImprovementCategoryView(
                        profile: profile, parentCategory: parentCategory,
                        template: containerTemplate, containerTemplate: nil, onCreated: onCreated
                    )
                } label: {
                    Label("Create \(containerTemplate.name) as a general Area", systemImage: containerTemplate.symbol)
                }
            }
            Section("Disciplines") {
                ForEach(childTemplates) { child in
                    NavigationLink {
                        ConfigureImprovementCategoryView(
                            profile: profile, parentCategory: parentCategory,
                            template: child, containerTemplate: containerTemplate, onCreated: onCreated
                        )
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(child.name)
                                Text("\(child.weeklySessions) times · \(child.weeklyMinutes) min/week")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: child.symbol)
                                .foregroundStyle(ColorToken.color(for: child.colorToken))
                        }
                    }
                }
            }
        }
        .navigationTitle(containerTemplate.name)
    }
}

private struct ConfigureImprovementCategoryView: View {
    let profile: Profile
    let parentCategory: AppCategory?
    let template: ImprovementCategoryTemplate?
    /// Set only when reached via TemplateDisciplineListView for a child
    /// template (e.g. Baseball) whose parent Area (Sports) may not exist
    /// for this profile yet. create() finds-or-creates it by name.
    let containerTemplate: ImprovementCategoryTemplate?
    let onCreated: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Query private var allCategories: [AppCategory]

    @State private var name: String
    @State private var pillar: ImprovementPillar
    @State private var trackingKind: AreaTrackingKind
    @State private var purpose: String
    @State private var sessions: Int
    @State private var minutes: Int
    @State private var reminderEnabled = false
    @State private var reminderTime = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now
    @State private var customTaskName = ""
    @State private var parentCategoryID: UUID?
    @State private var symbol: String
    @State private var colorToken: String

    /// The parent to nest this Area under. Either the explicit
    /// parentCategory passed in, or (for a discipline template reached via
    /// TemplateDisciplineListView) an existing Area matching the container
    /// template's name for this profile — found, not created, so this stays
    /// read-only; create() does the actual find-or-create.
    private var resolvedParentCategoryID: UUID? {
        if let parentCategoryID { return parentCategoryID }
        guard let containerTemplate else { return nil }
        return allCategories.first {
            $0.profile?.id == profile.id && $0.parentCategoryID == nil &&
            CategoryHierarchy.normalizedName($0.name) == CategoryHierarchy.normalizedName(containerTemplate.name)
        }?.id
    }

    private var duplicatePlanExists: Bool {
        let normalized = CategoryHierarchy.normalizedName(name)
        guard !normalized.isEmpty else { return false }
        return allCategories.contains {
            $0.profile?.id == profile.id && $0.parentCategoryID == resolvedParentCategoryID &&
            CategoryHierarchy.normalizedName($0.name) == normalized
        }
    }

    init(
        profile: Profile,
        parentCategory: AppCategory?,
        template: ImprovementCategoryTemplate?,
        containerTemplate: ImprovementCategoryTemplate? = nil,
        onCreated: @escaping () -> Void
    ) {
        self.profile = profile
        self.parentCategory = parentCategory
        self.template = template
        self.containerTemplate = containerTemplate
        self.onCreated = onCreated
        _name = State(initialValue: template?.name ?? "")
        _pillar = State(initialValue: parentCategory?.pillar ?? template?.pillar ?? .physical)
        _trackingKind = State(initialValue: parentCategory?.trackingKind ?? template?.trackingKind ?? .tasks)
        _purpose = State(initialValue: template?.purpose ?? "")
        _sessions = State(initialValue: template?.weeklySessions ?? 3)
        _minutes = State(initialValue: template?.weeklyMinutes ?? 120)
        _parentCategoryID = State(initialValue: parentCategory?.id)
        _symbol = State(initialValue: template?.symbol ?? "target")
        _colorToken = State(initialValue: template?.colorToken ?? "blue")
    }

    var body: some View {
        Form {
            Section("Area") {
                TextField("Area name, such as Baseball or School", text: $name)
                Picker("Group", selection: $pillar) {
                    ForEach(ImprovementPillar.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Tracking", selection: $trackingKind) {
                    ForEach(AreaTrackingKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                Text(trackingKind.explanation)
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Why does this matter?", text: $purpose, axis: .vertical)
                DisclosureGroup("Appearance (optional)") {
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
            }

            if let parentCategory {
                Section("Optional Sub-plan") {
                    LabeledContent("Inside", value: parentCategory.name)
                    Text("This focus area will appear inside \(parentCategory.name), not as another top-level area.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let containerTemplate {
                Section("Optional Sub-plan") {
                    LabeledContent("Inside", value: containerTemplate.name)
                    Text("This focus area will appear inside \(containerTemplate.name), which will be created automatically if it doesn't exist yet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Weekly activity plan") {
                Stepper("\(sessions) times per week", value: $sessions, in: 0...21)
                Stepper("\(minutes) minutes per week", value: $minutes, in: 0...1200, step: 15)
                Text("This measures whether the plan was followed. Create a Goal to measure whether the real outcome improved.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Starter Tasks") {
                if let template, !template.tasks.isEmpty {
                    ForEach(template.tasks) { task in
                        VStack(alignment: .leading) {
                            Text(task.name)
                            Text("\(task.durationMinutes) min · \(task.repeatType.rawValue)")
                                .font(.caption).foregroundStyle(.secondary)
                            if !task.measurements.isEmpty {
                                Text(task.measurements.map(\.name).joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                } else {
                    TextField("First Task (optional)", text: $customTaskName)
                    Text("Example: Baseball → Batting practice. You can add more Tasks later.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Reminder") {
                Toggle("Enable area reminder", isOn: $reminderEnabled)
                if reminderEnabled {
                    DatePicker("Reminder time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                }
            }

            Section {
                Button("Create Area", action: create)
                    .frame(maxWidth: .infinity)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || duplicatePlanExists)
                if duplicatePlanExists {
                    Text("This Plan already exists. Open it from Plans to add or edit Tasks.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle(template == nil ? "New Area" : "Review Area")
    }

    private func create() {
        guard !duplicatePlanExists else { return }

        // A discipline template (e.g. Baseball) may need its container
        // (Sports) to exist first — find it if it's already there,
        // otherwise create it now. Rolled back below if the save fails.
        var createdContainerCategory: AppCategory?
        var resolvedParentID = parentCategoryID
        if resolvedParentID == nil, let containerTemplate {
            if let existing = allCategories.first(where: {
                $0.profile?.id == profile.id && $0.parentCategoryID == nil &&
                CategoryHierarchy.normalizedName($0.name) == CategoryHierarchy.normalizedName(containerTemplate.name)
            }) {
                resolvedParentID = existing.id
            } else {
                let container = AppCategory(
                    profile: profile, name: containerTemplate.name,
                    symbol: containerTemplate.symbol, colorToken: containerTemplate.colorToken,
                    pillar: containerTemplate.pillar, trackingKind: containerTemplate.trackingKind,
                    purpose: containerTemplate.purpose,
                    weeklyTargetSessions: containerTemplate.weeklySessions,
                    weeklyTargetMinutes: containerTemplate.weeklyMinutes
                )
                contextInsert(container)
                createdContainerCategory = container
                resolvedParentID = container.id
            }
        }

        let category = AppCategory(
            profile: profile,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            symbol: symbol,
            colorToken: colorToken,
            pillar: pillar,
            trackingKind: trackingKind,
            purpose: purpose,
            weeklyTargetSessions: sessions,
            weeklyTargetMinutes: minutes
        )
        category.parentCategoryID = resolvedParentID
        category.reminderEnabled = reminderEnabled
        category.reminderHour = Calendar.current.component(.hour, from: reminderTime)
        category.reminderMinute = Calendar.current.component(.minute, from: reminderTime)
        contextInsert(category)

        let profileCategories = allCategories.filter { $0.profile?.id == profile.id }
        category.relatedCategoryIDs = (template?.relatedNames ?? []).compactMap { relatedName in
            profileCategories.first { $0.name.localizedCaseInsensitiveContains(relatedName) }?.id
        }

        var createdActivities: [Activity] = []
        var createdMeasurementDefinitions: [MeasurementDefinition] = []
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

                // Additive alongside targetValue/targetUnit above, per
                // Refactor.md Run 4 — a template task may define several
                // simultaneous measurements instead of (or alongside) the
                // one scalar target.
                for (index, blueprint) in task.measurements.enumerated() {
                    let definition = MeasurementDefinition(
                        activity: activity, name: blueprint.name, type: blueprint.type,
                        unit: blueprint.unit, targetValue: blueprint.targetValue, sortOrder: index
                    )
                    contextInsert(definition)
                    createdMeasurementDefinitions.append(definition)
                }
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

        if modelContext.saveOrReport() {
            Task { await ReminderService.updateReminders(for: category, activities: createdActivities) }
            onCreated()
        } else {
            createdMeasurementDefinitions.forEach { modelContext.delete($0) }
            createdActivities.forEach { modelContext.delete($0) }
            modelContext.delete(category)
            if let createdContainerCategory { modelContext.delete(createdContainerCategory) }
        }
    }

    private func contextInsert<T: PersistentModel>(_ model: T) {
        modelContext.insert(model)
    }
}
