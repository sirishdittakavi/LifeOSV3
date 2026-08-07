import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct ProfileManagerView: View {
    @Bindable var selection: SelectedProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Profile.name) private var profiles: [Profile]
    @State private var showingAddProfile = false
    @State private var editingProfile: Profile?

    private var activeProfiles: [Profile] { profiles.filter(\.isActive) }
    private var hiddenProfiles: [Profile] { profiles.filter { !$0.isActive } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Each person has separate areas, actions, calendar, goals, food, weight, sport logs, and progress. Switching profile never combines their results.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Profiles") {
                    ForEach(activeProfiles) { profile in
                        HStack(spacing: 12) {
                            Button {
                                selection.profile = profile
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    ProfileAvatarView(profile: profile, size: 38)
                                    VStack(alignment: .leading) {
                                        Text(profile.name).font(.headline).foregroundStyle(.primary)
                                        Text("\(profile.kind.rawValue) · \(profile.managementMode.rawValue)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selection.profile?.id == profile.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                editingProfile = profile
                            } label: {
                                Label("Edit", systemImage: "pencil")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .frame(height: 36)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit \(profile.name) profile")
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Edit") { editingProfile = profile }.tint(.blue)
                            if activeProfiles.count > 1 {
                                Button("Hide", role: .destructive) { hide(profile) }
                            }
                        }
                        .contextMenu {
                            Button("Edit Profile") { editingProfile = profile }
                            if activeProfiles.count > 1 {
                                Button("Hide Profile", role: .destructive) { hide(profile) }
                            }
                        }
                    }
                }

                if !hiddenProfiles.isEmpty {
                    Section("Hidden Profiles") {
                        ForEach(hiddenProfiles) { profile in
                            HStack(spacing: 12) {
                                ProfileAvatarView(profile: profile, size: 34)
                                Text(profile.name)
                                Spacer()
                                Button("Restore") { restore(profile) }
                                    .buttonStyle(.bordered)
                            }
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

    private func hide(_ profile: Profile) {
        guard activeProfiles.count > 1 else { return }
        profile.isActive = false
        if selection.profile?.id == profile.id {
            selection.profile = activeProfiles.first { $0.id != profile.id }
        }
        try? modelContext.save()
    }

    private func restore(_ profile: Profile) {
        profile.isActive = true
        try? modelContext.save()
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
    @State private var managementMode: ProfileManagementMode = .parentManaged
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarData: Data?

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    HStack {
                        Spacer()
                        EditableProfileAvatar(data: avatarData, kind: kind, colorToken: colorToken, size: 88)
                        Spacer()
                    }
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(avatarData == nil ? "Add Profile Photo" : "Change Profile Photo",
                              systemImage: "photo.badge.plus")
                    }
                    if avatarData != nil {
                        Button("Remove Photo", role: .destructive) { avatarData = nil }
                    }
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

                Section("Who Manages It") {
                    Picker("Access", selection: $managementMode) {
                        ForEach(ProfileManagementMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    Text(managementMode.explanation)
                        .font(.caption).foregroundStyle(.secondary)
                    if managementMode == .selfManaged {
                        Text("For now this profile remains on this device. Secure own-phone access will arrive with Family Sync.")
                            .font(.caption).foregroundStyle(.secondary)
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
                managementMode = newKind == .child ? .parentManaged : .selfManaged
            }
            .onChange(of: selectedPhoto) { _, item in
                loadProfilePhoto(from: item) { avatarData = $0 }
            }
        }
    }

    private func create() {
        let profile = Profile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            colorToken: colorToken
        )
        profile.avatarData = avatarData
        profile.managementMode = managementMode
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
    @State private var name: String
    @State private var kind: ProfileKind
    @State private var colorToken: String
    @State private var managementMode: ProfileManagementMode
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarData: Data?

    init(profile: Profile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _kind = State(initialValue: profile.kind)
        _colorToken = State(initialValue: profile.colorToken)
        _managementMode = State(initialValue: profile.managementMode)
        _avatarData = State(initialValue: profile.avatarData)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    HStack {
                        Spacer()
                        EditableProfileAvatar(data: avatarData, kind: kind, colorToken: colorToken, size: 96)
                        Spacer()
                    }
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(avatarData == nil ? "Add Profile Photo" : "Change Profile Photo",
                              systemImage: "photo.badge.plus")
                    }
                    if avatarData != nil {
                        Button("Remove Photo", role: .destructive) { avatarData = nil }
                    }
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                    Text("Use the person's real name. Child profiles are optional and can be hidden without deleting their history.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Profile type", selection: $kind) {
                        ForEach(ProfileKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Colour", selection: $colorToken) {
                        ForEach(CategoryAppearanceOptions.colors, id: \.self) { token in
                            Text(token.capitalized).tag(token)
                        }
                    }
                }

                Section("Who Manages It") {
                    Picker("Access", selection: $managementMode) {
                        ForEach(ProfileManagementMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    Text(managementMode.explanation)
                        .font(.caption).foregroundStyle(.secondary)
                    if managementMode == .selfManaged {
                        Text("This setting records the intended access model. Live use across another phone requires the future Family Sync service.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    NavigationLink("Goals, nutrition and units") {
                        ProfileGoalsForm(profile: profile)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .onChange(of: selectedPhoto) { _, item in
                loadProfilePhoto(from: item) { avatarData = $0 }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        profile.name = trimmedName
                        profile.kind = kind
                        profile.colorToken = colorToken
                        profile.managementMode = managementMode
                        profile.avatarData = avatarData
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
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

struct ProfileAvatarView: View {
    let profile: Profile
    var size: CGFloat = 36

    var body: some View {
        EditableProfileAvatar(
            data: profile.avatarData,
            kind: profile.kind,
            colorToken: profile.colorToken,
            size: size
        )
    }
}

private struct EditableProfileAvatar: View {
    let data: Data?
    let kind: ProfileKind
    let colorToken: String
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: kind == .child ? "figure.and.child.holdinghands" : "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.22)
                    .foregroundStyle(ColorToken.color(for: colorToken))
                    .background(ColorToken.color(for: colorToken).opacity(0.15))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

private func loadProfilePhoto(
    from item: PhotosPickerItem?,
    completion: @escaping (Data?) -> Void
) {
    guard let item else { return }
    Task {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let optimized = await MainActor.run { optimizedProfilePhotoData(data) }
        await MainActor.run { completion(optimized) }
    }
}

@MainActor
private func optimizedProfilePhotoData(_ data: Data) -> Data? {
    guard let image = UIImage(data: data) else { return nil }
    let longestSide = max(image.size.width, image.size.height)
    let scale = longestSide > 600 ? 600 / longestSide : 1
    let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: targetSize)
    let resized = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
    return resized.jpegData(compressionQuality: 0.82)
}

enum ProfileStarterPlan: String, CaseIterable, Identifiable {
    case blank = "Blank - choose everything"
    case balanced = "Balanced basics"
    case studentAndSport = "Student and sport"
    case healthAndCareer = "Health and career"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .blank: return "Starts with no areas or actions."
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
