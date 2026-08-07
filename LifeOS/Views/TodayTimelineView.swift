//
//  TodayTimelineView.swift
//  LifeOS
//
//  Implements DESIGN.md Section 12 (Today Screen — Priority Mockup).
//  "The first screen should feel like a useful daily calendar, not a
//  statistics dashboard" — so this stays a chronological list with
//  direct actions, no charts here (those live in DailyProgressView).
//

import SwiftUI
import SwiftData

struct TodayTimelineView: View {
    @Bindable var selection: SelectedProfile
    @Environment(\.modelContext) private var modelContext

    @Query private var activities: [Activity]
    @Query private var allItems: [CalendarItem]
    @Query private var foodEntries: [FoodEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]
    @Query private var sportEntries: [SportEntry]
    @Query private var categories: [AppCategory]

    @State private var showingAddActivity = false
    @State private var showingAddWhatHappened = false
    @State private var recordingItem: CalendarItem?

    private var todayItems: [CalendarItem] {
        guard let profile = selection.profile else { return [] }
        let calendar = Calendar.current
        return allItems
            .filter { $0.profile?.id == profile.id && calendar.isSameDay($0.date, as: .now) }
            .sorted { ($0.plannedStart ?? .distantPast) < ($1.plannedStart ?? .distantPast) }
    }

    private var summary: CompletionSummary {
        ProgressEngine.completionSummary(items: todayItems)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                summaryBar
                dailySignals

                if todayItems.isEmpty {
                    ContentUnavailableView(
                        "Nothing Scheduled",
                        systemImage: "calendar.badge.plus",
                        description: Text("Add an action or log something that happened.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(todayItems) { item in
                            CalendarItemRow(item: item,
                                             onStart: { start(item) },
                                             onDone: { recordingItem = item },
                                             onSkip: { skip(item) })
                        }
                    }
                    .listStyle(.plain)
                }

                addWhatHappenedButton
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ProfilePicker(selection: selection)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddActivity = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                generateTodayItemsIfNeeded()
            }
            .onChange(of: selection.profile?.id) {
                generateTodayItemsIfNeeded()
            }
            .sheet(isPresented: $showingAddActivity) {
                if let profile = selection.profile {
                    AddActivityView(profile: profile)
                }
            }
            .sheet(isPresented: $showingAddWhatHappened) {
                if let profile = selection.profile {
                    AddWhatHappenedView(profile: profile)
                }
            }
            .sheet(item: $recordingItem) { item in
                RecordActualView(item: item)
            }
        }
    }

    private var header: some View {
        HStack {
            if let profile = selection.profile {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name).font(.title2).bold()
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var summaryBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("TODAY'S PLAN").font(.caption).bold().foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(summary.percentComplete * 100))%").font(.caption).bold()
            }
            ProgressView(value: summary.percentComplete).tint(.green)
            Text("\(summary.done) done · \(summary.skipped) skipped · \(summary.remaining) remaining")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var addWhatHappenedButton: some View {
        Button {
            showingAddWhatHappened = true
        } label: {
            Label("Add What Happened", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }

    private var dailySignals: some View {
        let profile = selection.profile
        let todayFood = foodEntries.filter {
            $0.profile?.id == profile?.id && Calendar.current.isDateInToday($0.date)
        }
        let protein = todayFood.reduce(0.0) { $0 + $1.proteinGrams }
        let latestWeight = weightEntries.first { $0.profile?.id == profile?.id }
        let todaySportEntries = sportEntries.filter {
            $0.profile?.id == profile?.id && Calendar.current.isDateInToday($0.date)
        }
        let sportMinutes = todaySportEntries.reduce(0) { $0 + $1.durationMinutes }
        let profileSportCategories = categories.filter {
            $0.profile?.id == profile?.id && $0.pillar == .sport && $0.isActive
        }
        let loggedSportNames = Set(todaySportEntries.compactMap { entry -> String? in
            entry.category?.name
        })
        let sportName = loggedSportNames.count == 1
            ? (loggedSportNames.first ?? "Sport")
            : (loggedSportNames.isEmpty && profileSportCategories.count == 1
                ? profileSportCategories[0].name : "Sport")
        let sportSymbol = profileSportCategories.first { $0.name == sportName }?.symbol ?? "figure.run"

        return HStack(spacing: 8) {
            DailySignalCard(
                title: "Protein",
                value: "\(Int(protein))/\(Int(profile?.proteinGoalGrams ?? 0))g",
                symbol: "fork.knife",
                color: .green
            )
            DailySignalCard(
                title: "Weight",
                value: latestWeight.map {
                    let unit = profile?.weightUnit ?? .kilograms
                    return "\(unit.displayValue(kilograms: $0.kilograms).formatted(.number.precision(.fractionLength(1))))\(unit.rawValue)"
                } ?? "—",
                symbol: "scalemass",
                color: .blue
            )
            DailySignalCard(
                title: sportName,
                value: "\(sportMinutes) min",
                symbol: sportSymbol,
                color: .orange
            )
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func generateTodayItemsIfNeeded() {
        guard let profile = selection.profile else { return }
        let newItems = PlanningService.generateMissingCalendarItems(
            profile: profile, date: .now, activities: activities, existingItems: allItems
        )
        guard !newItems.isEmpty else { return }
        newItems.forEach { modelContext.insert($0) }
        try? modelContext.save()
    }

    private func start(_ item: CalendarItem) {
        item.status = .inProgress
        item.actualStart = .now
        try? modelContext.save()
    }

    private func skip(_ item: CalendarItem) {
        item.status = .skipped
        try? modelContext.save()
    }
}

private struct DailySignalCard: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value).font(.subheadline).bold().lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Row

private struct CalendarItemRow: View {
    let item: CalendarItem
    let onStart: () -> Void
    let onDone: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(item.plannedStart?.formatted(date: .omitted, time: .shortened) ?? "--:--")
                    .font(.subheadline).bold()
                    .frame(width: 64, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.activity?.name ?? "Activity")
                        .font(.subheadline).bold()
                    HStack(spacing: 6) {
                        if let category = item.activity?.category {
                            Image(systemName: category.symbol)
                                .font(.caption2)
                                .foregroundStyle(ColorToken.color(for: category.colorToken))
                            Text(category.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("· \(item.status.rawValue)")
                            .font(.caption)
                            .foregroundStyle(statusColor)
                    }
                }
                Spacer()
            }

            actionButtons
        }
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        switch item.status {
        case .done: return .green
        case .skipped: return .secondary
        case .inProgress: return .blue
        default: return .secondary
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch item.status {
        case .planned:
            HStack(spacing: 8) {
                Button("Start", action: onStart).buttonStyle(.bordered)
                Button("Done", action: onDone).buttonStyle(.borderedProminent)
                Button("Skip", action: onSkip).buttonStyle(.bordered).tint(.secondary)
            }
            .controlSize(.small)
        case .inProgress:
            HStack(spacing: 8) {
                Button("Finish", action: onDone).buttonStyle(.borderedProminent)
                Button("Skip", action: onSkip).buttonStyle(.bordered).tint(.secondary)
            }
            .controlSize(.small)
        case .done:
            if let target = item.activity?.targetValue, let unit = item.activity?.targetUnit {
                Text("Target: \(Int(target)) \(unit)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .skipped, .rescheduled, .unplanned:
            EmptyView()
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Profile.self, SavedCategoryTemplate.self, AppCategory.self, Activity.self, CalendarItem.self, ActivitySession.self, FoodEntry.self, WeightEntry.self, SportEntry.self], inMemory: true)
}
