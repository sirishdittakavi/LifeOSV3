import SwiftUI
import SwiftData

struct ImprovementDashboardView: View {
    @Bindable var selection: SelectedProfile
    @Query private var categories: [AppCategory]
    @Query private var activities: [Activity]
    @Query private var calendarItems: [CalendarItem]
    @Query private var foodEntries: [FoodEntry]
    @Query private var weightEntries: [WeightEntry]
    @Query private var baseballEntries: [BaseballEntry]
    @State private var period: DashboardPeriod = .day
    @State private var showingAddAction = false
    @State private var showingAddArea = false
    @State private var showingStarterPlans = false

    private var allProfileCategories: [AppCategory] {
        guard let profile = selection.profile else { return [] }
        return categories.filter { $0.profile?.id == profile.id && $0.isActive }
            .sorted { $0.name < $1.name }
    }

    private var profileCategories: [AppCategory] {
        allProfileCategories.filter { CategoryHierarchy.isTopLevel($0, in: allProfileCategories) }
    }

    private var progresses: [CategoryProgress] {
        guard let profile = selection.profile else { return [] }
        return profileCategories.map {
            CategoryProgressEngine.progress(
                profile: profile, category: $0,
                includedCategoryIDs: CategoryHierarchy.idsIncludingDescendants(of: $0, in: allProfileCategories),
                period: period,
                activities: activities, calendarItems: calendarItems,
                foodEntries: foodEntries, weightEntries: weightEntries,
                baseballEntries: baseballEntries
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Picker("Period", selection: $period) {
                        ForEach(DashboardPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    DashboardCoverageSummary(progresses: progresses, period: period)

                    if progresses.isEmpty {
                        ContentUnavailableView(
                            "No Improvement Areas",
                            systemImage: "target",
                            description: Text("Start from a plan or create an area that matters to you.")
                        )
                        .padding(.top, 30)
                    } else {
                        ForEach(ImprovementPillar.allCases) { pillar in
                            let pillarProgress = progresses.filter { $0.category.pillar == pillar }
                            if !pillarProgress.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(pillar.rawValue.uppercased())
                                        .font(.caption).bold().foregroundStyle(.secondary)
                                    ForEach(pillarProgress) { progress in
                                        NavigationLink {
                                            ImprovementCategoryDetailView(
                                                selection: selection,
                                                category: progress.category
                                            )
                                        } label: {
                                            CategoryProgressCard(progress: progress)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfilePicker(selection: selection) }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingAddAction = true } label: {
                            Label("Add an Action", systemImage: "checkmark.circle.badge.plus")
                        }
                        .disabled(allProfileCategories.isEmpty)
                        Button { showingAddArea = true } label: {
                            Label("Add an Area", systemImage: "plus.square")
                        }
                        Button { showingStarterPlans = true } label: {
                            Label("Start from a Plan", systemImage: "square.grid.2x2")
                        }
                    } label: { Image(systemName: "plus") }
                        .disabled(selection.profile == nil)
                }
            }
            .sheet(isPresented: $showingAddAction) {
                if let profile = selection.profile { AddActivityView(profile: profile) }
            }
            .sheet(isPresented: $showingAddArea) {
                if let profile = selection.profile {
                    AddImprovementCategoryView(profile: profile, startMode: .custom)
                }
            }
            .sheet(isPresented: $showingStarterPlans) {
                if let profile = selection.profile { AddImprovementCategoryView(profile: profile) }
            }
        }
    }
}

private struct DashboardCoverageSummary: View {
    let progresses: [CategoryProgress]
    let period: DashboardPeriod

    private var complete: Int { progresses.filter { $0.status == .complete }.count }
    private var onTrack: Int { progresses.filter { $0.status == .onTrack }.count }
    private var attention: Int { progresses.filter { $0.status == .needsAttention || $0.status == .behind }.count }
    private var insufficient: Int { progresses.filter { $0.status == .insufficientData }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(period == .day ? "TODAY'S CONFIDENCE" : "\(period.rawValue.uppercased()) CONFIDENCE")
                .font(.caption).bold().foregroundStyle(.secondary)
            Text("\(complete + onTrack) of \(progresses.count) active areas are complete or on track")
                .font(.title3).bold()
            HStack(spacing: 8) {
                CoveragePill(value: complete, label: "complete", color: .green)
                CoveragePill(value: onTrack, label: "on track", color: .blue)
                CoveragePill(value: attention, label: "attention", color: .orange)
                if insufficient > 0 { CoveragePill(value: insufficient, label: "no data", color: .gray) }
            }
            Text("Areas are counted separately; LifeOS does not blend unrelated goals into one life score.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct CoveragePill: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        Text("\(value) \(label)")
            .font(.caption2).bold()
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct CategoryProgressCard: View {
    let progress: CategoryProgress

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color(.tertiarySystemFill), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress.primaryFraction)
                    .stroke(statusColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(progress.primaryFraction * 100))%")
                    .font(.caption2).bold()
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label(progress.category.name, systemImage: progress.category.symbol)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                Text(progress.progressText).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(progress.status.rawValue)
                        .font(.caption2).bold().foregroundStyle(statusColor)
                    Text("· \(progress.confidence.rawValue)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(progress.nextAction).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var statusColor: Color {
        switch progress.status {
        case .complete: return .green
        case .onTrack: return .blue
        case .needsAttention: return .orange
        case .behind: return .red
        case .insufficientData, .notScheduled: return .gray
        }
    }
}
