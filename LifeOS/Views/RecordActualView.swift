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

    @State private var recordedValue: Double
    @State private var actualDurationMinutes: Int
    @State private var note: String = ""
    @State private var pendingSession: ActivitySession?

    init(item: CalendarItem) {
        self.item = item
        _recordedValue = State(initialValue: (item.activity?.targetValue ?? 0))
        _actualDurationMinutes = State(initialValue: max(item.activity?.estimatedDurationMinutes ?? 1, 1))
        _pendingSession = State(initialValue: nil)
    }

    private var hasTarget: Bool { item.activity?.targetValue != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(item.activity?.name ?? "Activity").font(.headline)
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
        }
        item.note = note

        if modelContext.saveOrReport() { dismiss() }
    }
}

#Preview {
    let profile = Profile(name: "Sirish", kind: .parent, colorToken: "blue")
    let category = AppCategory(name: "Baseball", symbol: "figure.baseball", colorToken: "orange")
    let activity = Activity(profile: profile, category: category, name: "Hitting Practice",
                             targetValue: 100, targetUnit: "swings", plannedStartMinutes: 18*60, estimatedDurationMinutes: 60)
    let item = CalendarItem(profile: profile, activity: activity, date: .now)
    RecordActualView(item: item)
        .modelContainer(for: [Profile.self, SavedCategoryTemplate.self, AppCategory.self, Goal.self, GoalAreaContribution.self, ResultMeasure.self, ResultEntry.self, Activity.self, CalendarItem.self, ActivitySession.self, FoodEntry.self, WeightEntry.self, SportEntry.self], inMemory: true)
}
