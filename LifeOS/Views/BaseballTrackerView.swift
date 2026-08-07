import SwiftUI
import SwiftData

struct BaseballTrackerView: View {
    @Bindable var selection: SelectedProfile
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BaseballEntry.date, order: .reverse) private var entries: [BaseballEntry]
    @State private var showingAddEntry = false
    @State private var showingGoals = false

    private var profileEntries: [BaseballEntry] {
        guard let profile = selection.profile else { return [] }
        return entries.filter { $0.profile?.id == profile.id }
    }

    private var todayEntries: [BaseballEntry] {
        profileEntries.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var weekEntries: [BaseballEntry] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .now
        return profileEntries.filter { $0.date >= start }
    }

    private var totals: (swings: Int, hits: Int, throwCount: Int, pitches: Int, fielding: Int, minutes: Int) {
        todayEntries.reduce(into: (0, 0, 0, 0, 0, 0)) { result, entry in
            result.0 += entry.swings
            result.1 += entry.hits
            result.2 += entry.throwCount
            result.3 += entry.pitches
            result.4 += entry.fieldingRepetitions
            result.5 += entry.durationMinutes
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    BaseballSummary(totals: totals)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if let profile = selection.profile {
                    Section("7-day workload") {
                        WeeklyBaseballSummary(entries: weekEntries, goalMinutes: profile.weeklyBaseballMinutesGoal)
                    }
                }

                Section("Today's sessions") {
                    if todayEntries.isEmpty {
                        ContentUnavailableView(
                            "No Baseball Logged",
                            systemImage: "figure.baseball",
                            description: Text("Tap + to record hitting, throwing, pitching, fielding or a game.")
                        )
                    } else {
                        ForEach(todayEntries) { entry in
                            BaseballEntryRow(entry: entry)
                        }
                        .onDelete(perform: deleteEntries)
                    }
                }

                if profileEntries.count > todayEntries.count {
                    Section("Previous sessions") {
                        ForEach(profileEntries.filter { !Calendar.current.isDateInToday($0.date) }.prefix(10)) { entry in
                            BaseballEntryRow(entry: entry)
                        }
                    }
                }
            }
            .navigationTitle("Baseball")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfilePicker(selection: selection) }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingGoals = true } label: { Image(systemName: "target") }
                        .disabled(selection.profile == nil)
                    Button { showingAddEntry = true } label: { Image(systemName: "plus") }
                        .disabled(selection.profile == nil)
                }
            }
            .sheet(isPresented: $showingAddEntry) {
                if let profile = selection.profile {
                    AddBaseballEntryView(profile: profile)
                }
            }
            .sheet(isPresented: $showingGoals) {
                if let profile = selection.profile {
                    ProfileGoalsView(profile: profile)
                }
            }
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        offsets.map { todayEntries[$0] }.forEach(modelContext.delete)
        try? modelContext.save()
    }
}

private struct WeeklyBaseballSummary: View {
    let entries: [BaseballEntry]
    let goalMinutes: Int

    private var minutes: Int { entries.reduce(0) { $0 + $1.durationMinutes } }
    private var workload: Int { entries.reduce(0) { $0 + ($1.durationMinutes * $1.perceivedEffort) } }
    private var averageSoreness: Double {
        guard !entries.isEmpty else { return 0 }
        return Double(entries.reduce(0) { $0 + $1.armSoreness }) / Double(entries.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(minutes) / \(goalMinutes) min").font(.headline)
                    Text("\(entries.count) sessions").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Load \(workload)").font(.headline)
                    Text("duration × effort").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if goalMinutes > 0 {
                ProgressView(value: min(Double(minutes) / Double(goalMinutes), 1)).tint(.orange)
            }
            HStack {
                Label("Avg soreness \(averageSoreness.formatted(.number.precision(.fractionLength(1))))/10",
                      systemImage: "waveform.path.ecg")
                    .font(.caption)
                    .foregroundStyle(averageSoreness >= 5 ? .red : .secondary)
                Spacer()
                Text("Review trends with a coach").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct BaseballSummary: View {
    let totals: (swings: Int, hits: Int, throwCount: Int, pitches: Int, fielding: Int, minutes: Int)

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY'S BASEBALL").font(.caption).bold().foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 8) {
                BaseballMetric(value: totals.swings, label: "Swings")
                BaseballMetric(value: totals.hits, label: "Hits")
                BaseballMetric(value: totals.throwCount, label: "Throws")
                BaseballMetric(value: totals.pitches, label: "Pitches")
                BaseballMetric(value: totals.fielding, label: "Fielding")
                BaseballMetric(value: totals.minutes, label: "Minutes")
            }
        }
        .padding()
    }
}

private struct BaseballMetric: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text("\(value)").font(.title2).bold().foregroundStyle(.orange)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct BaseballEntryRow: View {
    let entry: BaseballEntry

    private var details: String {
        var parts: [String] = []
        if entry.swings > 0 { parts.append("\(entry.swings) swings") }
        if entry.hits > 0 { parts.append("\(entry.hits) hits") }
        if entry.throwCount > 0 { parts.append("\(entry.throwCount) throws") }
        if entry.pitches > 0 { parts.append("\(entry.pitches) pitches") }
        if entry.fieldingRepetitions > 0 { parts.append("\(entry.fieldingRepetitions) fielding") }
        if entry.durationMinutes > 0 { parts.append("\(entry.durationMinutes) min") }
        return parts.isEmpty ? "Session recorded" : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(entry.sessionType.rawValue, systemImage: "figure.baseball")
                    .font(.headline)
                Spacer()
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(details).font(.caption).foregroundStyle(.secondary)
            Text("Effort \(entry.perceivedEffort)/10 · Arm soreness \(entry.armSoreness)/10 · Load \(entry.durationMinutes * entry.perceivedEffort)")
                .font(.caption2)
                .foregroundStyle(entry.armSoreness >= 5 ? .red : .secondary)
            if !entry.note.isEmpty { Text(entry.note).font(.caption) }
        }
        .padding(.vertical, 3)
    }
}

private struct AddBaseballEntryView: View {
    let profile: Profile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date.now
    @State private var sessionType: BaseballSessionType = .hitting
    @State private var swings = 0
    @State private var hits = 0
    @State private var throwCount = 0
    @State private var pitches = 0
    @State private var fielding = 0
    @State private var minutes = 30
    @State private var perceivedEffort = 5
    @State private var armSoreness = 0
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    Picker("Type", selection: $sessionType) {
                        ForEach(BaseballSessionType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    DatePicker("Date", selection: $date)
                    Stepper("Duration: \(minutes) min", value: $minutes, in: 0...360, step: 5)
                }
                Section("Repetitions") {
                    Stepper("Swings: \(swings)", value: $swings, in: 0...1000, step: 5)
                    Stepper("Hits: \(hits)", value: $hits, in: 0...1000)
                    Stepper("Throws: \(throwCount)", value: $throwCount, in: 0...1000, step: 5)
                    Stepper("Pitches: \(pitches)", value: $pitches, in: 0...500, step: 5)
                    Stepper("Fielding reps: \(fielding)", value: $fielding, in: 0...500, step: 5)
                }
                Section("Athlete feedback") {
                    Stepper("Effort: \(perceivedEffort)/10", value: $perceivedEffort, in: 1...10)
                    Stepper("Arm soreness: \(armSoreness)/10", value: $armSoreness, in: 0...10)
                    if armSoreness >= 5 {
                        Label("Elevated soreness recorded. Tell a parent, coach, or qualified health professional before adding more throwing load.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Section("Notes") { TextField("Optional", text: $note, axis: .vertical) }
            }
            .navigationTitle("Log Baseball")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
    }

    private func save() {
        modelContext.insert(BaseballEntry(
            profile: profile, date: date, sessionType: sessionType,
            swings: swings, hits: hits, throwCount: throwCount, pitches: pitches,
            fieldingRepetitions: fielding, durationMinutes: minutes, note: note,
            perceivedEffort: perceivedEffort, armSoreness: armSoreness
        ))
        try? modelContext.save()
        dismiss()
    }
}
