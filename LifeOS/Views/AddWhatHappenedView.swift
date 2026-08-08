//
//  AddWhatHappenedView.swift
//  LifeOS
//
//  DESIGN.md Section 11: a one-time manual entry still creates a one-time
//  Activity plus a Calendar Item — never an unstructured event. Offers
//  "Add once" or "Save as reusable Activity" (ADR-017).
//

import SwiftUI
import SwiftData

struct AddWhatHappenedView: View {
    let profile: Profile

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AppCategory.name) private var categories: [AppCategory]

    @State private var name: String = ""
    @State private var selectedCategory: AppCategory?
    @State private var startTime: Date = .now
    @State private var endTime: Date = .now
    @State private var tagsText: String = ""
    @State private var hasValue: Bool = false
    @State private var recordedValue: Double = 0
    @State private var unit: String = ""
    @State private var saveAsReusable: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("What happened") {
                    TextField("e.g. Park Play", text: $name)
                    Picker("Plan", selection: $selectedCategory) {
                        Text("None").tag(AppCategory?.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(AppCategory?.some(category))
                        }
                    }
                    TextField("Tags, comma separated (optional)", text: $tagsText)
                }

                Section("When") {
                    DatePicker("Start", selection: $startTime)
                    DatePicker("End", selection: $endTime)
                }

                Section("Result (optional)") {
                    Toggle("Record a number", isOn: $hasValue)
                    if hasValue {
                        Stepper("\(Int(recordedValue)) \(unit)", value: $recordedValue, in: 0...1000, step: 5)
                        TextField("Unit label", text: $unit)
                    }
                }

                Section {
                    Toggle("Save as a reusable action", isOn: $saveAsReusable)
                } footer: {
                    Text(saveAsReusable
                         ? "This will be scheduled daily going forward. You can change its schedule later."
                         : "This logs today only and won't repeat.")
                }
            }
            .navigationTitle("Add What Happened")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let calendar = Calendar.current
        let minutesSinceMidnight = calendar.component(.hour, from: startTime) * 60 + calendar.component(.minute, from: startTime)
        let durationMinutes = max(1, Int(endTime.timeIntervalSince(startTime) / 60))

        let activity = Activity(
            profile: profile,
            category: selectedCategory,
            name: name,
            source: .manual,
            tags: tags,
            targetValue: hasValue ? recordedValue : nil,
            targetUnit: hasValue ? unit : nil,
            repeatType: saveAsReusable ? .daily : .once,
            plannedStartMinutes: minutesSinceMidnight,
            estimatedDurationMinutes: durationMinutes,
            startDate: .now
        )
        modelContext.insert(activity)

        let item = CalendarItem(
            profile: profile,
            activity: activity,
            date: calendar.startOfDay(for: .now),
            plannedStart: startTime,
            plannedEnd: endTime,
            status: .done,
            source: .manual
        )
        item.actualStart = startTime
        item.actualEnd = endTime
        modelContext.insert(item)

        if hasValue {
            let session = ActivitySession(
                activity: activity, calendarItem: item, date: .now,
                startedAt: startTime, endedAt: endTime, recordedValue: recordedValue
            )
            modelContext.insert(session)
        }

        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    let profile = Profile(name: "Sirish", kind: .parent, colorToken: "blue")
    AddWhatHappenedView(profile: profile)
        .modelContainer(for: [Profile.self, SavedCategoryTemplate.self, AppCategory.self, Goal.self, GoalAreaContribution.self, ResultMeasure.self, ResultEntry.self, Activity.self, CalendarItem.self, ActivitySession.self, FoodEntry.self, WeightEntry.self, SportEntry.self], inMemory: true)
}
