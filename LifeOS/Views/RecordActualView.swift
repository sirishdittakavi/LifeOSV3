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
    @State private var note: String = ""

    init(item: CalendarItem) {
        self.item = item
        _recordedValue = State(initialValue: (item.activity?.targetValue ?? 0))
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
                    Button("Save") { save() }.bold()
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
        if item.actualStart == nil { item.actualStart = .now }
        item.actualEnd = .now
        item.status = .done

        if hasTarget {
            let session = ActivitySession(
                activity: item.activity,
                calendarItem: item,
                date: item.date,
                startedAt: item.actualStart,
                endedAt: .now,
                recordedValue: recordedValue,
                note: note
            )
            modelContext.insert(session)
        } else if !note.isEmpty {
            item.note = note
        }

        try? modelContext.save()
        dismiss()
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
