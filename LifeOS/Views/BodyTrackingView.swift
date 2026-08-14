//
//  BodyTrackingView.swift
//  LifeOS
//
//  NUTRITION_MODULE_DESIGN_V1.md Screen 06. Weight is the primary hero;
//  Height/Body Fat % (and any user-added custom metric) are secondary,
//  lower-cadence rows — the architecture stays data-driven via
//  BodyMetricDefinition/BodyMetricEntry rather than a fixed enum, per the
//  approved design. Users are never required to log daily.
//

import SwiftUI
import SwiftData

struct BodyTrackingView: View {
    @Bindable var selection: SelectedProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allDefinitions: [BodyMetricDefinition]
    @Query private var allEntries: [BodyMetricEntry]

    @State private var loggingDefinition: BodyMetricDefinition?
    @State private var showingAddMetric = false

    private var profileID: UUID? { selection.profile?.id }

    private var definitions: [BodyMetricDefinition] {
        guard let profileID else { return [] }
        return allDefinitions.filter { $0.profileID == profileID }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var weightDefinition: BodyMetricDefinition? { definitions.first { $0.name == "Weight" } }
    private var secondaryDefinitions: [BodyMetricDefinition] { definitions.filter { $0.id != weightDefinition?.id } }

    private func entries(for definition: BodyMetricDefinition) -> [BodyMetricEntry] {
        allEntries.filter { $0.bodyMetricDefinition?.id == definition.id }.sorted { $0.recordedAt > $1.recordedAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LifeOSSpacing.lg) {
                    if let weightDefinition {
                        weightCard(weightDefinition)
                    }
                    if !secondaryDefinitions.isEmpty {
                        secondaryCard
                    }
                    addCustomMetricRow
                }
                .padding(LifeOSSpacing.lg)
            }
            .navigationTitle("Body Tracking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .onAppear(perform: seedIfNeeded)
            .sheet(item: $loggingDefinition) { definition in
                AddBodyMetricEntrySheet(selection: selection, definition: definition)
            }
            .sheet(isPresented: $showingAddMetric) {
                if let profileID {
                    AddCustomMetricSheet(profileID: profileID, nextSortOrder: definitions.count)
                }
            }
        }
    }

    private func weightCard(_ definition: BodyMetricDefinition) -> some View {
        let recent = entries(for: definition)
        let latest = recent.first
        let trend = BodyTrackingEngine.trend(
            definitionID: definition.id, entries: allEntries,
            interval: DateInterval(start: Calendar.current.date(byAdding: .day, value: -42, to: .now) ?? .now, end: .now)
        )

        return VStack(alignment: .leading, spacing: LifeOSSpacing.sm) {
            LOSectionHeader(title: "Weight")
            LOCard(tint: .lifeOSFocus) {
                VStack(alignment: .leading, spacing: LifeOSSpacing.md) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let latest {
                                Text("\(latest.value, format: .number.precision(.fractionLength(1))) \(definition.unit)")
                                    .font(.lifeOSHeroMetric)
                                Text("Recorded \(latest.recordedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("No entry yet").font(.lifeOSValueEmphasis).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let trend {
                            let formattedTrend = trend.formatted(.number.precision(.fractionLength(1)))
                            let sign = trend > 0 ? "+" : ""
                            Text("\(sign)\(formattedTrend)\(definition.unit)")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background((trend <= 0 ? Color.lifeOSOnTrack : Color.lifeOSWatch).opacity(0.16), in: Capsule())
                                .foregroundStyle(trend <= 0 ? Color.lifeOSOnTrack : Color.lifeOSWatch)
                        }
                    }
                    LOPrimaryButton(title: "Save Weight", symbol: "plus") { loggingDefinition = definition }

                    if recent.count > 1 {
                        Divider()
                        ForEach(recent.prefix(5)) { entry in
                            HStack {
                                Text(entry.recordedAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(entry.value, format: .number.precision(.fractionLength(1))) \(entry.unitSnapshot)")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
            }
        }
    }

    private var secondaryCard: some View {
        VStack(alignment: .leading, spacing: LifeOSSpacing.sm) {
            LOSectionHeader(title: "Other metrics")
            LOCard {
                VStack(spacing: 0) {
                    ForEach(secondaryDefinitions) { definition in
                        let latest = entries(for: definition).first
                        Button { loggingDefinition = definition } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(definition.name).font(.lifeOSCardTitle).foregroundStyle(.primary)
                                    if let latest {
                                        Text("Last: \(latest.value, format: .number.precision(.fractionLength(1))) \(definition.unit) · \(latest.recordedAt.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("No entry yet").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, LifeOSSpacing.xs)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if definition.id != secondaryDefinitions.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var addCustomMetricRow: some View {
        Button { showingAddMetric = true } label: {
            Label("Add custom metric", systemImage: "plus.circle")
        }
    }

    private func seedIfNeeded() {
        guard let profileID else { return }
        let repository = SwiftDataBodyTrackingRepository(context: modelContext)
        repository.seedDefaultDefinitionsIfNeeded(profileID: profileID, existingDefinitions: allDefinitions)
        repository.save()
    }
}

private struct AddBodyMetricEntrySheet: View {
    @Bindable var selection: SelectedProfile
    let definition: BodyMetricDefinition
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var value: Double?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(definition.name)
                        Spacer()
                        TextField("0", value: $value, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(definition.unit).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(definition.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(value == nil)
                }
            }
        }
    }

    private func save() {
        guard let profileID = selection.profile?.id, let value else { return }
        let repository = SwiftDataBodyTrackingRepository(context: modelContext)
        let entry = BodyMetricEntry(
            profileID: profileID, bodyMetricDefinition: definition,
            nameSnapshot: definition.name, unitSnapshot: definition.unit, value: value
        )
        repository.insertEntry(entry)
        if repository.save() { dismiss() }
    }
}

private struct AddCustomMetricSheet: View {
    let profileID: UUID
    let nextSortOrder: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var unit = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Metric name, e.g. Waist", text: $name)
                TextField("Unit, e.g. cm", text: $unit)
            }
            .navigationTitle("Custom Metric")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let repository = SwiftDataBodyTrackingRepository(context: modelContext)
        let definition = BodyMetricDefinition(
            profileID: profileID, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            unit: unit.trimmingCharacters(in: .whitespacesAndNewlines), isSystemDefault: false, sortOrder: nextSortOrder
        )
        repository.insertDefinition(definition)
        if repository.save() { dismiss() }
    }
}
