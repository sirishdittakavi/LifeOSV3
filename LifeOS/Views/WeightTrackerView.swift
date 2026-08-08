import SwiftUI
import SwiftData
import Charts

struct WeightTrackerView: View {
    @Bindable var selection: SelectedProfile
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]
    @State private var showingAddEntry = false
    @State private var showingGoals = false

    private var profileEntries: [WeightEntry] {
        guard let profile = selection.profile else { return [] }
        return entries.filter { $0.profile?.id == profile.id }
    }

    private var trendPoints: [WeightTrendPoint] {
        WeightTrendEngine.points(entries: Array(profileEntries.prefix(60)).reversed())
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WeightSummary(
                        latest: profileEntries.first,
                        currentTrendKilograms: trendPoints.last?.trendKilograms,
                        profile: selection.profile
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if !trendPoints.isEmpty, let profile = selection.profile {
                    Section("Scale and trend") {
                        WeightChart(points: trendPoints, unit: profile.weightUnit)
                            .frame(height: 230)
                        Label("The blue line is a transparent 7-entry moving average that reduces daily water and food-weight noise.",
                              systemImage: "waveform.path.ecg")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("History") {
                    if profileEntries.isEmpty {
                        ContentUnavailableView(
                            "No Weight Logged",
                            systemImage: "scalemass",
                            description: Text("Tap + to record the first measurement.")
                        )
                    } else if let profile = selection.profile {
                        ForEach(profileEntries) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                    if !entry.note.isEmpty {
                                        Text(entry.note).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(profile.weightUnit.displayValue(kilograms: entry.kilograms),
                                     format: .number.precision(.fractionLength(1)))
                                    .font(.headline)
                                Text(profile.weightUnit.rawValue).foregroundStyle(.secondary)
                            }
                        }
                        .onDelete(perform: deleteEntries)
                    }
                }
            }
            .navigationTitle("Weight")
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
                    AddWeightEntryView(profile: profile, suggestedKilograms: profileEntries.first?.kilograms ?? 70)
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
        offsets.map { profileEntries[$0] }.forEach(modelContext.delete)
        modelContext.saveOrReport()
    }
}

private struct WeightSummary: View {
    let latest: WeightEntry?
    let currentTrendKilograms: Double?
    let profile: Profile?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BODY TREND").font(.caption).bold().foregroundStyle(.secondary)
            if let latest, let profile {
                let unit = profile.weightUnit
                HStack(alignment: .firstTextBaseline) {
                    Text(unit.displayValue(kilograms: latest.kilograms),
                         format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text(unit.rawValue).font(.title3).foregroundStyle(.secondary)
                    Spacer()
                }
                HStack(spacing: 18) {
                    if let currentTrendKilograms {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TREND").font(.caption2).bold().foregroundStyle(.secondary)
                            Text("\(unit.displayValue(kilograms: currentTrendKilograms).formatted(.number.precision(.fractionLength(1)))) \(unit.rawValue)")
                                .font(.subheadline).bold().foregroundStyle(.blue)
                        }
                    }
                    if let goal = profile.weightGoalKilograms {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TO GOAL").font(.caption2).bold().foregroundStyle(.secondary)
                            Text("\(abs(unit.displayValue(kilograms: latest.kilograms - goal)).formatted(.number.precision(.fractionLength(1)))) \(unit.rawValue)")
                                .font(.subheadline).bold()
                        }
                    }
                }
                Text("Scale reading recorded \(latest.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No measurement yet").font(.title3).foregroundStyle(.secondary)
                Text("Set kg or lb and an optional goal with the target button.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

private struct WeightTrendPoint: Identifiable {
    let date: Date
    let scaleKilograms: Double
    let trendKilograms: Double
    var id: Date { date }
}

private enum WeightTrendEngine {
    static func points(entries: [WeightEntry]) -> [WeightTrendPoint] {
        let sorted = entries.sorted { $0.date < $1.date }
        return sorted.indices.map { index in
            let lowerBound = max(0, index - 6)
            let window = sorted[lowerBound...index]
            let average = window.reduce(0.0) { $0 + $1.kilograms } / Double(window.count)
            return WeightTrendPoint(
                date: sorted[index].date,
                scaleKilograms: sorted[index].kilograms,
                trendKilograms: average
            )
        }
    }
}

private struct WeightChart: View {
    let points: [WeightTrendPoint]
    let unit: WeightUnit

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Scale", unit.displayValue(kilograms: point.scaleKilograms)),
                    series: .value("Series", "Scale")
                )
                .foregroundStyle(.gray.opacity(0.35))
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Scale", unit.displayValue(kilograms: point.scaleKilograms))
                )
                .foregroundStyle(.gray.opacity(0.45))
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Trend", unit.displayValue(kilograms: point.trendKilograms)),
                    series: .value("Series", "7-entry trend")
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 3))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartYAxisLabel(unit.rawValue)
    }
}

private struct AddWeightEntryView: View {
    let profile: Profile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var displayWeight: Double
    @State private var note = ""

    init(profile: Profile, suggestedKilograms: Double) {
        self.profile = profile
        _displayWeight = State(initialValue: profile.weightUnit.displayValue(kilograms: suggestedKilograms))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Measurement") {
                    HStack {
                        TextField("Weight", value: $displayWeight, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                        Text(profile.weightUnit.rawValue).foregroundStyle(.secondary)
                    }
                    DatePicker("Date", selection: $date)
                }
                Section("Notes") { TextField("Optional", text: $note, axis: .vertical) }
            }
            .navigationTitle("Log Weight")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(displayWeight <= 0)
                }
            }
        }
    }

    private func save() {
        let entry = WeightEntry(
            profile: profile,
            date: date,
            kilograms: profile.weightUnit.kilograms(from: displayWeight),
            note: note
        )
        modelContext.insert(entry)
        if modelContext.saveOrReport() { dismiss() }
        else { modelContext.delete(entry) }
    }
}
