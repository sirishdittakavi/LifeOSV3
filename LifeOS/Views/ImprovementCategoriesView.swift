import SwiftUI
import SwiftData

struct ImprovementCategoriesView: View {
    @Bindable var selection: SelectedProfile
    @Query private var categories: [AppCategory]
    @Query private var activities: [Activity]
    @Query private var calendarItems: [CalendarItem]
    @Query private var foodEntries: [FoodEntry]
    @Query private var weightEntries: [WeightEntry]
    @Query private var baseballEntries: [BaseballEntry]
    @State private var addRoute: CategoryAddRoute?
    @State private var editingCategory: AppCategory?

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
                ForEach(ImprovementPillar.allCases) { pillar in
                    let roots = topLevelCategories.filter { $0.pillar == pillar }.sorted { $0.name < $1.name }
                    let tree = categoryTree(from: roots)
                    if !tree.isEmpty {
                        Section(pillar.rawValue) {
                            ForEach(tree) { item in
                                NavigationLink {
                                    ImprovementCategoryDetailView(selection: selection, category: item.category)
                                } label: {
                                    categoryRow(item.category, depth: item.depth)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        editingCategory = item.category
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                                .contextMenu {
                                    Button {
                                        editingCategory = item.category
                                    } label: {
                                        Label("Edit Category", systemImage: "pencil")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfilePicker(selection: selection) }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            addRoute = .custom
                        } label: {
                            Label("Add Custom Category", systemImage: "plus.square")
                        }
                        Button {
                            addRoute = .templates
                        } label: {
                            Label("Use a Template", systemImage: "square.grid.2x2")
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
        }
    }

    private func categoryRow(_ category: AppCategory, depth: Int) -> some View {
        let progress = selection.profile.map {
            CategoryProgressEngine.progress(
                profile: $0, category: category,
                includedCategoryIDs: CategoryHierarchy.idsIncludingDescendants(of: category, in: profileCategories),
                period: .week,
                activities: activities, calendarItems: calendarItems,
                foodEntries: foodEntries, weightEntries: weightEntries,
                baseballEntries: baseballEntries
            )
        }
        return HStack(spacing: 12) {
            if depth > 0 {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, CGFloat(min(depth, 3)) * 10)
            }
            Image(systemName: category.symbol)
                .frame(width: 34, height: 34)
                .background(ColorToken.color(for: category.colorToken).opacity(0.15))
                .foregroundStyle(ColorToken.color(for: category.colorToken))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(category.name).font(.headline)
                Text(progress?.progressText ?? "No progress data")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(progress?.status.rawValue ?? "")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func categoryTree(from roots: [AppCategory]) -> [CategoryTreeItem] {
        var items: [CategoryTreeItem] = []
        func append(_ category: AppCategory, depth: Int) {
            items.append(CategoryTreeItem(category: category, depth: depth))
            for child in CategoryHierarchy.directChildren(of: category, in: profileCategories) {
                append(child, depth: depth + 1)
            }
        }
        roots.forEach { append($0, depth: 0) }
        return items
    }
}

private enum CategoryAddRoute: String, Identifiable {
    case custom
    case templates

    var id: String { rawValue }
    var creationMode: CategoryCreationMode { self == .custom ? .custom : .templates }
}

private struct CategoryTreeItem: Identifiable {
    let category: AppCategory
    let depth: Int
    var id: UUID { category.id }
}
