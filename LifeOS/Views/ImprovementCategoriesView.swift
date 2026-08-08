import SwiftUI
import SwiftData

struct ImprovementCategoriesView: View {
    @Bindable var selection: SelectedProfile
    @Query private var categories: [AppCategory]
    @Query private var activities: [Activity]
    @Query private var calendarItems: [CalendarItem]
    @Query private var foodEntries: [FoodEntry]
    @Query private var weightEntries: [WeightEntry]
    @Query private var sportEntries: [SportEntry]
    @State private var addRoute: CategoryAddRoute?
    @State private var editingCategory: AppCategory?
    @State private var showingAddAction = false

    private var profileCategories: [AppCategory] {
        guard let profile = selection.profile else { return [] }
        return categories.filter { $0.profile?.id == profile.id && $0.isActive }
    }

    private var topLevelCategories: [AppCategory] {
        profileCategories.filter { CategoryHierarchy.isTopLevel($0, in: profileCategories) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Areas organise what you do. Each Area contains repeatable Tasks and can support one or more Goals.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        VStack(spacing: 10) {
                            Button {
                                showingAddAction = true
                            } label: {
                                Label("Add Task", systemImage: "checkmark.circle.badge.plus")
                            }
                            .buttonStyle(LifeOSPrimaryButtonStyle())
                            .disabled(profileCategories.isEmpty)

                            Button {
                                addRoute = .custom
                            } label: {
                                Label("Add Area", systemImage: "plus.square")
                            }
                            .buttonStyle(LifeOSSecondaryButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
                }

                if topLevelCategories.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Areas Yet",
                            systemImage: "list.bullet.clipboard",
                            description: Text("Start with Baseball, School, Nutrition or another part of life you want to work on.")
                        )
                        Button("Create My First Area") { addRoute = .custom }
                            .buttonStyle(LifeOSPrimaryButtonStyle())
                    }
                }

                ForEach(ImprovementPillar.allCases) { pillar in
                    let roots = topLevelCategories.filter { $0.pillar == pillar }.sorted { $0.name < $1.name }
                    if !roots.isEmpty {
                        Section(pillar.rawValue) {
                            ForEach(roots) { category in
                                NavigationLink {
                                    ImprovementCategoryDetailView(selection: selection, category: category)
                                } label: {
                                    categoryRow(category)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        editingCategory = category
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                                .contextMenu {
                                    Button {
                                        editingCategory = category
                                    } label: {
                                        Label("Edit Area", systemImage: "pencil")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Areas")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfilePicker(selection: selection) }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingAddAction = true
                        } label: {
                            Label("Add a Task", systemImage: "checkmark.circle.badge.plus")
                        }
                        .disabled(profileCategories.isEmpty)
                        Button {
                            addRoute = .custom
                        } label: {
                            Label("Add an Area", systemImage: "plus.square")
                        }
                        Button {
                            addRoute = .templates
                        } label: {
                            Label("Start from an Area Template", systemImage: "square.grid.2x2")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(selection.profile == nil)
                }
            }
            .sheet(item: $addRoute) { route in
                if let profile = selection.profile {
                    AddImprovementCategoryView(profile: profile, startMode: route.creationMode)
                }
            }
            .sheet(item: $editingCategory) { category in
                let categoryActivities = activities.filter { $0.category?.id == category.id }
                EditImprovementCategoryView(category: category, activities: categoryActivities)
            }
            .sheet(isPresented: $showingAddAction) {
                if let profile = selection.profile {
                    AddActivityView(profile: profile)
                }
            }
        }
    }

    private func categoryRow(_ category: AppCategory) -> some View {
        let includedIDs = CategoryHierarchy.idsIncludingDescendants(of: category, in: profileCategories)
        let actionCount = activities.filter {
            $0.isActive && $0.category.map { includedIDs.contains($0.id) } == true
        }.count
        let progress = selection.profile.map {
            CategoryProgressEngine.progress(
                profile: $0, category: category,
                includedCategoryIDs: includedIDs,
                period: .week,
                activities: activities, calendarItems: calendarItems,
                foodEntries: foodEntries, weightEntries: weightEntries,
                sportEntries: sportEntries
            )
        }
        return HStack(spacing: 12) {
            Image(systemName: category.symbol)
                .frame(width: 34, height: 34)
                .background(ColorToken.color(for: category.colorToken).opacity(0.15))
                .foregroundStyle(ColorToken.color(for: category.colorToken))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(category.name).font(.headline)
                Text("\(actionCount) Task\(actionCount == 1 ? "" : "s") · \(progress?.progressText ?? "No Task plan yet")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(progress.map { "\($0.status.rawValue)" } ?? "")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

}

private enum CategoryAddRoute: String, Identifiable {
    case custom
    case templates

    var id: String { rawValue }
    var creationMode: CategoryCreationMode { self == .custom ? .custom : .templates }
}
