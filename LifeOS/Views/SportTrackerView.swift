import SwiftUI
import SwiftData

struct SportTrackerView: View {
    @Bindable var selection: SelectedProfile
    let category: AppCategory
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SportEntry.date, order: .reverse) private var entries: [SportEntry]
    @State private var showingAddEntry = false

    private var profileEntries: [SportEntry] {
        guard let profile = selection.profile else { return [] }
        return entries.filter {
            $0.profile?.id == profile.id && $0.category?.id == category.id
        }
    }

    private var todayEntries: [SportEntry] {
        profileEntries.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var weekEntries: [SportEntry] {
        let start = Calendar.current.date(
            byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)
        ) ?? .now
        return profileEntries.filter { $0.date >= start }
    }

    private var todayTotals: SportTotals {
        SportTotals(entries: todayEntries)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SportSummary(name: category.name, symbol: category.symbol, totals: todayTotals)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("7-day workload") {
                    WeeklySportSummary(entries: weekEntries, goalMinutes: category.weeklyTargetMinutes)
                }

                Section("Today's sessions") {
                    if todayEntries.isEmpty {
                        ContentUnavailableView(
                            "No \(category.name) Logged",
                            systemImage: category.symbol,
                            description: Text("Tap + to record practice, skills, conditioning, competition, or recovery.")
                        )
                    } else {
                        ForEach(todayEntries) { entry in
                            SportEntryRow(entry: entry, symbol: category.symbol)
                        }
                        .onDelete(perform: deleteEntries)
                    }
                }

                if profileEntries.count > todayEntries.count {
                    Section("Previous sessions") {
                        ForEach(profileEntries.filter { !Calendar.current.isDateInToday($0.date) }.prefix(10)) { entry in
                            SportEntryRow(entry: entry, symbol: category.symbol)
                        }
                    }
                }
            }
            .navigationTitle(category.name)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfilePicker(selection: selection) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddEntry = true } label: { Image(systemName: "plus") }
                        .disabled(selection.profile == nil)
                }
            }
            .sheet(isPresented: $showingAddEntry) {
                if let profile = selection.profile {
                    AddSportEntryView(profile: profile, category: category)
                }
            }
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        offsets.map { todayEntries[$0] }.forEach(modelContext.delete)
        try? modelContext.save()
    }
}

private struct SportTotals {
    let sessions: Int
    let minutes: Int
    let repetitions: Int
    let workload: Int

    init(entries: [SportEntry]) {
        sessions = entries.count
        minutes = entries.reduce(0) { $0 + $1.durationMinutes }
        repetitions = entries.reduce(0) { $0 + $1.repetitions }
        workload = entries.reduce(0) { $0 + ($1.durationMinutes * $1.perceivedEffort) }
    }
}

private struct WeeklySportSummary: View {
    let entries: [SportEntry]
    let goalMinutes: Int

    private var totals: SportTotals { SportTotals(entries: entries) }
    private var averageSoreness: Double {
        guard !entries.isEmpty else { return 0 }
        return Double(entries.reduce(0) { $0 + $1.soreness }) / Double(entries.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text(goalMinutes > 0 ? "\(totals.minutes) / \(goalMinutes) min" : "\(totals.minutes) min")
                        .font(.headline)
                    Text("\(totals.sessions) sessions").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Load \(totals.workload)").font(.headline)
                    Text("duration × effort").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if goalMinutes > 0 {
                ProgressView(value: min(Double(totals.minutes) / Double(goalMinutes), 1)).tint(.orange)
            } else {
                Text("Set weekly minutes by editing this Area.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Label(
                    "Avg soreness \(averageSoreness.formatted(.number.precision(.fractionLength(1))))/10",
                    systemImage: "waveform.path.ecg"
                )
                .font(.caption)
                .foregroundStyle(averageSoreness >= 5 ? .red : .secondary)
                Spacer()
                Text("Review trends with a coach").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SportSummary: View {
    let name: String
    let symbol: String
    let totals: SportTotals

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("TODAY'S \(name.uppercased())", systemImage: symbol)
                .font(.caption).bold().foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 8) {
                SportMetric(value: totals.sessions, label: "Sessions")
                SportMetric(value: totals.minutes, label: "Minutes")
                SportMetric(value: totals.repetitions, label: "Repetitions")
                SportMetric(value: totals.workload, label: "Training load")
            }
        }
        .padding()
    }
}

private struct SportMetric: View {
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

private struct SportEntryRow: View {
    let entry: SportEntry
    let symbol: String

    private var details: String {
        var parts: [String] = []
        if entry.repetitions > 0 { parts.append("\(entry.repetitions) reps") }
        if entry.durationMinutes > 0 { parts.append("\(entry.durationMinutes) min") }
        return parts.isEmpty ? "Session recorded" : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(entry.sessionName, systemImage: symbol).font(.headline)
                Spacer()
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(details).font(.caption).foregroundStyle(.secondary)
            Text("Effort \(entry.perceivedEffort)/10 · Soreness \(entry.soreness)/10 · Load \(entry.durationMinutes * entry.perceivedEffort)")
                .font(.caption2)
                .foregroundStyle(entry.soreness >= 5 ? .red : .secondary)
            if !entry.note.isEmpty { Text(entry.note).font(.caption) }
        }
        .padding(.vertical, 3)
    }
}

private enum SportSessionKind: String, CaseIterable, Identifiable {
    case practice = "Practice"
    case skills = "Skills / Drills"
    case conditioning = "Conditioning"
    case competition = "Game / Competition"
    case strength = "Strength"
    case recovery = "Recovery"
    case other = "Other"

    var id: String { rawValue }
}

private struct AddSportEntryView: View {
    let profile: Profile
    let category: AppCategory
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date.now
    @State private var sessionKind: SportSessionKind = .practice
    @State private var customSessionName = ""
    @State private var repetitions = 0
    @State private var minutes = 30
    @State private var perceivedEffort = 5
    @State private var soreness = 0
    @State private var note = ""

    private var sessionName: String {
        if sessionKind == .other {
            let trimmed = customSessionName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Other" : trimmed
        }
        return sessionKind.rawValue
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    Picker("Type", selection: $sessionKind) {
                        ForEach(SportSessionKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if sessionKind == .other {
                        TextField("Session name", text: $customSessionName)
                    }
                    DatePicker("Date", selection: $date)
                    Stepper("Duration: \(minutes) min", value: $minutes, in: 0...360, step: 5)
                    Stepper("Repetitions: \(repetitions)", value: $repetitions, in: 0...5000, step: 5)
                }
                Section("Athlete feedback") {
                    Stepper("Effort: \(perceivedEffort)/10", value: $perceivedEffort, in: 1...10)
                    Stepper("Soreness: \(soreness)/10", value: $soreness, in: 0...10)
                    if soreness >= 5 {
                        Label(
                            "Elevated soreness recorded. Tell a parent, coach, or qualified health professional before adding more load.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }
                Section("Notes") { TextField("Optional", text: $note, axis: .vertical) }
            }
            .navigationTitle("Log \(category.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
    }

    private func save() {
        modelContext.insert(SportEntry(
            profile: profile, category: category, date: date, sessionName: sessionName,
            repetitions: repetitions, durationMinutes: minutes, note: note,
            perceivedEffort: perceivedEffort, soreness: soreness
        ))
        try? modelContext.save()
        dismiss()
    }
}
