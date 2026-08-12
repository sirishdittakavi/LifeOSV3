//
//  RecordActualView.swift
//  LifeOS
//
//  Reached from "Done"/"Finish" on a Calendar Item. Records the actual
//  value against the Activity's target (if any) as a Session, and marks
//  the item Done — the fast path DESIGN.md Section 9 calls for.
//

import SwiftUI
import SwiftData

struct RecordActualView: View {
    let item: CalendarItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allMeasurementDefinitions: [MeasurementDefinition]

    @State private var recordedValue: Double
    @State private var actualDurationMinutes: Int
    @State private var note: String = ""
    @State private var pendingSession: ActivitySession?
    /// Raw text input per measurement. Blank means the user has not recorded
    /// anything for that measurement — never prefilled with target or zero.
    @State private var measurementInputs: [UUID: String] = [:]

    init(item: CalendarItem) {
        self.item = item
        _recordedValue = State(initialValue: (item.activity?.targetValue ?? 0))
        _actualDurationMinutes = State(initialValue: max(item.activity?.estimatedDurationMinutes ?? 1, 1))
        _pendingSession = State(initialValue: nil)
    }

    private var hasTarget: Bool { item.activity?.targetValue != nil }

    private var measurementDefinitions: [MeasurementDefinition] {
        guard let activityID = item.activity?.id else { return [] }
        return allMeasurementDefinitions
            .filter { $0.activity?.id == activityID && $0.isActive }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func inputBinding(for definition: MeasurementDefinition) -> Binding<String> {
        Binding(
            get: { measurementInputs[definition.id] ?? "" },
            set: { measurementInputs[definition.id] = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(item.activity?.name ?? "Activity").font(.lifeOSCardTitle)
                    if let category = item.activity?.category {
                        Label(category.name, systemImage: category.symbol)
                            .foregroundStyle(ColorToken.color(for: category.colorToken))
                    }
                }

                Section("Time spent") {
                    TextField("Minutes", value: $actualDurationMinutes, format: .number)
                        .keyboardType(.numberPad)
                    Text("Use the actual time—not the planned estimate—so Goal progress stays honest.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if hasTarget, let unit = item.activity?.targetUnit, let target = item.activity?.targetValue {
                    Section("Actual (target: \(Int(target)) \(unit))") {
                        Stepper("\(Int(recordedValue)) \(unit)", value: $recordedValue, in: 0...(target * 3), step: stepSize(for: unit))
                    }
                } else {
                    Section {
                        Text("No quantitative target for this activity — marking it Done is enough.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !measurementDefinitions.isEmpty {
                    Section {
                        ForEach(measurementDefinitions) { definition in
                            if definition.type == .text {
                                TextField(definition.name, text: inputBinding(for: definition), axis: .vertical)
                            } else {
                                HStack {
                                    Text(definition.name)
                                    Spacer()
                                    TextField("Not recorded", text: inputBinding(for: definition))
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .frame(maxWidth: 120)
                                    if let unit = definition.unit, !unit.isEmpty {
                                        Text(unit).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Measurements")
                    } footer: {
                        Text("Leave blank to skip a measurement — nothing is recorded unless you enter a value.")
                    }
                }

                Section("Notes") {
                    TextField("Optional", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Finish")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(actualDurationMinutes < 1)
                        .accessibilityIdentifier("completion.save")
                }
            }
        }
    }

    private func stepSize(for unit: String) -> Double {
        switch unit {
        case "min": return 5
        case "g": return 5
        case "L": return 0.25
        default: return 1
        }
    }

    private func save() {
        let timing = CompletionTiming.interval(endingAt: .now, durationMinutes: actualDurationMinutes)
        item.actualStart = timing.start
        item.actualEnd = timing.end
        item.status = .done

        var insertedEntries: [MeasurementEntry] = []
        if pendingSession == nil {
            let session = ActivitySession(
                activity: item.activity,
                calendarItem: item,
                date: item.date,
                startedAt: item.actualStart,
                endedAt: item.actualEnd,
                actualActiveSeconds: actualDurationMinutes * 60,
                recordedValue: hasTarget ? recordedValue : 0,
                note: note
            )
            modelContext.insert(session)
            pendingSession = session

            for definition in measurementDefinitions {
                let raw = (measurementInputs[definition.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { continue }

                if definition.type == .text {
                    let entry = MeasurementEntry(
                        activitySession: session,
                        measurementDefinition: definition,
                        nameSnapshot: definition.name,
                        typeSnapshot: definition.type,
                        unitSnapshot: definition.unit ?? "",
                        textValue: raw
                    )
                    modelContext.insert(entry)
                    insertedEntries.append(entry)
                } else if let value = Double(raw) {
                    let entry = MeasurementEntry(
                        activitySession: session,
                        measurementDefinition: definition,
                        nameSnapshot: definition.name,
                        typeSnapshot: definition.type,
                        unitSnapshot: definition.unit ?? "",
                        numericValue: value
                    )
                    modelContext.insert(entry)
                    insertedEntries.append(entry)
                }
            }
        }
        item.note = note

        if modelContext.saveOrReport() {
            dismiss()
        } else {
            for entry in insertedEntries {
                modelContext.delete(entry)
            }
            if let session = pendingSession {
                modelContext.delete(session)
                pendingSession = nil
            }
        }
    }
}

#Preview {
    let profile = Profile(name: "Sirish", kind: .parent, colorToken: "blue")
    let category = AppCategory(name: "Baseball", symbol: "figure.baseball", colorToken: "orange")
    let activity = Activity(profile: profile, category: category, name: "Hitting Practice",
                             targetValue: 100, targetUnit: "swings", plannedStartMinutes: 18*60, estimatedDurationMinutes: 60)
    let item = CalendarItem(profile: profile, activity: activity, date: .now)
    RecordActualView(item: item)
        .modelContainer(for: [Profile.self, SavedCategoryTemplate.self, AppCategory.self, Goal.self, GoalAreaContribution.self, ResultMeasure.self, ResultEntry.self, Activity.self, CalendarItem.self, ActivitySession.self, FoodEntry.self, WeightEntry.self, SportEntry.self, Relationship.self, MeasurementDefinition.self, MeasurementEntry.self], inMemory: true)
}
