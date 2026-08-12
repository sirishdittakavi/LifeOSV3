//
//  DailyProgressView.swift
//  LifeOS
//
//  Implements DESIGN.md Section 10a: target vs actual, separate from
//  completion status. Today's numbers plus a 7-day trend per activity.
//

import SwiftUI
import SwiftData

struct DailyProgressView: View {
    @Bindable var selection: SelectedProfile

    @Query private var activities: [Activity]
    @Query(sort: \ActivitySession.date) private var sessions: [ActivitySession]
    @Query private var measurementDefinitions: [MeasurementDefinition]
    @Query private var measurementEntries: [MeasurementEntry]
    @State private var selectedActivity: Activity?

    private var todayProgress: [DailyActivityProgress] {
        guard let profile = selection.profile else { return [] }
        return ProgressEngine.dailyProgress(profile: profile, date: .now, activities: activities, sessions: sessions)
    }

    /// Each measurement (e.g. Ground Balls, Catches) is shown independently —
    /// no blended score across measurements of differing units.
    private var todayMeasurementProgress: [MeasurementProgressRow] {
        guard let profile = selection.profile else { return [] }
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let todayInterval = DateInterval(start: startOfDay, duration: 86_400)
        let profileActivityIDs = Set(activities.filter { $0.profile?.id == profile.id }.map(\.id))

        return measurementDefinitions
            .filter { definition in
                guard definition.isActive, let activityID = definition.activity?.id else { return false }
                return profileActivityIDs.contains(activityID)
            }
            .sorted {
                ($0.activity?.name ?? "", $0.sortOrder) < ($1.activity?.name ?? "", $1.sortOrder)
            }
            .map { definition in
                MeasurementProgressRow(
                    id: definition.id,
                    activityName: definition.activity?.name ?? "",
                    definition: definition,
                    total: ProgressEngine.measurementTotal(for: definition, entries: measurementEntries, interval: todayInterval)
                )
            }
    }

    private var last7Days: [Date] {
        let calendar = Calendar.current
        return (0..<7).reversed().map {
            calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: .now))!
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if todayProgress.isEmpty && todayMeasurementProgress.isEmpty {
                        ContentUnavailableView(
                            "No Tracked Targets Yet",
                            systemImage: "chart.bar.xaxis",
                            description: Text("Activities with a target (minutes, swings, grams...) or measurements will show progress here.")
                        )
                        .padding(.top, 40)
                    } else {
                        // Legacy Activity.targetValue tracking and new per-measurement
                        // tracking are independent sections — neither depends on the
                        // other having data.
                        if !todayProgress.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("TODAY'S ACTION TRACKING").font(.caption).bold().foregroundStyle(.secondary)
                                Text("Target vs. actual — separate from completion status on Today.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)

                            VStack(spacing: 12) {
                                ForEach(todayProgress) { progress in
                                    Button { selectedActivity = progress.activity } label: {
                                        ProgressBarRow(progress: progress)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }

                        if !todayMeasurementProgress.isEmpty {
                            if !todayProgress.isEmpty { Divider().padding(.horizontal) }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("MEASUREMENTS").font(.caption).bold().foregroundStyle(.secondary)
                                Text("Each measurement tracked independently.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)

                            VStack(spacing: 8) {
                                ForEach(todayMeasurementProgress) { row in
                                    MeasurementProgressRowView(row: row)
                                }
                            }
                            .padding(.horizontal)
                        }

                        if !todayProgress.isEmpty {
                            Divider().padding(.horizontal)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("7-DAY TREND").font(.caption).bold().foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)

                            ForEach(todayProgress) { progress in
                                TrendRow(activity: progress.activity, days: last7Days, activities: activities, sessions: sessions)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Task Progress")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfilePicker(selection: selection) }
            }
            .sheet(item: $selectedActivity) { ActivitySessionHistoryView(activity: $0) }
        }
    }
}

private struct ActivitySessionHistoryView: View {
    let activity: Activity
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allSessions: [ActivitySession]
    @State private var editingSession: ActivitySession?

    private var sessions: [ActivitySession] {
        allSessions.filter { $0.activity?.id == activity.id }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions Logged",
                        systemImage: "list.bullet",
                        description: Text("Sessions recorded for \(activity.name) will appear here.")
                    )
                } else {
                    ForEach(sessions) { session in
                        Button { editingSession = session } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.date.formatted(date: .abbreviated, time: .shortened))
                                    if !session.note.isEmpty {
                                        Text(session.note).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(session.recordedValue.formatted(.number.precision(.fractionLength(0...2)))) \(activity.targetUnit ?? "")")
                                    .font(.headline)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                    .onDelete(perform: deleteSessions)
                }
            }
            .navigationTitle(activity.name)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editingSession) { EditActivitySessionView(session: $0) }
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        offsets.map { sessions[$0] }.forEach(modelContext.delete)
        modelContext.saveOrReport()
    }
}

private struct EditActivitySessionView: View {
    let session: ActivitySession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var recordedValue: Double
    @State private var note: String
    @State private var showingDeleteConfirmation = false

    init(session: ActivitySession) {
        self.session = session
        _date = State(initialValue: session.date)
        _recordedValue = State(initialValue: session.recordedValue)
        _note = State(initialValue: session.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    DatePicker("Date", selection: $date)
                    TextField("Recorded value", value: $recordedValue, format: .number)
                        .keyboardType(.decimalPad)
                }
                Section("Notes") { TextField("Optional", text: $note, axis: .vertical) }
                Section {
                    Button("Delete Session", role: .destructive) { showingDeleteConfirmation = true }
                }
            }
            .navigationTitle("Edit Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .confirmationDialog(
                "Delete this session?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible
            ) {
                Button("Delete Session", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Today's progress and the 7-day trend recalculate immediately. This can't be undone.")
            }
        }
    }

    private func save() {
        session.date = date
        session.recordedValue = recordedValue
        session.note = note
        if modelContext.saveOrReport() { dismiss() }
    }

    private func delete() {
        modelContext.delete(session)
        if modelContext.saveOrReport() { dismiss() }
    }
}

private struct ProgressBarRow: View {
    let progress: DailyActivityProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let category = progress.activity.category {
                    Image(systemName: category.symbol)
                        .foregroundStyle(ColorToken.color(for: category.colorToken))
                }
                Text(progress.activity.name).font(.subheadline).bold()
                Spacer()
                if let target = progress.target, let unit = progress.activity.targetUnit {
                    Text("\(Int(progress.actual)) / \(Int(target)) \(unit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: progress.cappedFraction)
                .tint(progress.activity.category.map { ColorToken.color(for: $0.colorToken) } ?? .blue)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MeasurementProgressRow: Identifiable {
    let id: UUID
    let activityName: String
    let definition: MeasurementDefinition
    let total: Double
}

private struct MeasurementProgressRowView: View {
    let row: MeasurementProgressRow

    private var fraction: Double? {
        guard let target = row.definition.targetValue, target > 0 else { return nil }
        return min(row.total / target, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(row.activityName) · \(row.definition.name)")
                    .font(.subheadline)
                Spacer()
                if let target = row.definition.targetValue {
                    Text("\(formatted(row.total)) / \(formatted(target)) \(row.definition.unit ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(formatted(row.total)) \(row.definition.unit ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let fraction {
                ProgressView(value: fraction)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}

private struct TrendRow: View {
    let activity: Activity
    let days: [Date]
    let activities: [Activity]
    let sessions: [ActivitySession]

    private func fraction(for day: Date) -> Double {
        guard let target = activity.targetValue, target > 0 else { return 0 }
        let calendar = Calendar.current
        let daySessions = sessions.filter { $0.activity?.id == activity.id && calendar.isSameDay($0.date, as: day) }
        let actual = daySessions.reduce(0.0) { $0 + $1.recordedValue }
        return min(actual / target, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(activity.name).font(.caption).bold()
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let f = fraction(for: day)
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(f >= 0.9 ? Color.green : (f >= 0.5 ? Color.orange : Color.gray.opacity(0.4)))
                            .frame(width: 20, height: max(4, f * 50))
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Profile.self, SavedCategoryTemplate.self, AppCategory.self, Goal.self, GoalAreaContribution.self, ResultMeasure.self, ResultEntry.self, Activity.self, CalendarItem.self, ActivitySession.self, FoodEntry.self, WeightEntry.self, SportEntry.self, Relationship.self, MeasurementDefinition.self, MeasurementEntry.self], inMemory: true)
}
