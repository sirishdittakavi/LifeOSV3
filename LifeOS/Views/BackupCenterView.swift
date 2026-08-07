import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupCenterView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [Profile]
    @Query private var categories: [AppCategory]
    @Query private var activities: [Activity]
    @Query private var calendarItems: [CalendarItem]
    @Query private var sessions: [ActivitySession]
    @Query private var foodEntries: [FoodEntry]
    @Query private var weightEntries: [WeightEntry]
    @Query private var baseballEntries: [BaseballEntry]
    @Query private var savedTemplates: [SavedCategoryTemplate]

    @State private var exporting = false
    @State private var importing = false
    @State private var exportDocument = LifeOSJSONDocument(data: Data())
    @State private var statusTitle = ""
    @State private var statusMessage = ""
    @State private var showingStatus = false

    var body: some View {
        List {
            Section {
                Label("Stored locally on this iPhone", systemImage: "iphone.gen3")
                Text("Normal app restarts and phone restarts keep your data. Deleting the app or losing the phone can remove local-only data, so export backups regularly.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Full Family Backup") {
                Button { prepareExport() } label: {
                    Label("Export LifeOS Backup", systemImage: "square.and.arrow.up")
                }
                Button { importing = true } label: {
                    Label("Restore or Merge Backup", systemImage: "square.and.arrow.down")
                }
                Text("The backup contains all profiles, areas, actions, calendar history, measurements, logs, photos, and reusable plans. Restore merges by stable ID instead of duplicating existing records.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Backup JSON is portable but not encrypted. Store it in a private, trusted location because it may contain family and health information.")
                    .font(.caption).foregroundStyle(.orange)
            }

            Section("Current Backup Contents") {
                countRow("Profiles", profiles.count)
                countRow("Areas", categories.count)
                countRow("Actions", activities.count)
                countRow("Calendar items", calendarItems.count)
                countRow("Recorded sessions", sessions.count)
                countRow("Food entries", foodEntries.count)
                countRow("Weight entries", weightEntries.count)
                countRow("Sport entries", baseballEntries.count)
                countRow("Saved plans", savedTemplates.count)
            }
        }
        .navigationTitle("Backup & Restore")
        .fileExporter(
            isPresented: $exporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "LifeOS-family-backup"
        ) { result in
            switch result {
            case .success:
                showStatus("Backup Exported", "Keep the JSON file in iCloud Drive or another safe location.")
            case .failure(let error):
                showStatus("Export Failed", error.localizedDescription)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            restore(result)
        }
        .alert(statusTitle, isPresented: $showingStatus) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(statusMessage)
        }
    }

    private func countRow(_ title: String, _ count: Int) -> some View {
        LabeledContent(title, value: count.formatted())
    }

    private func prepareExport() {
        let payload = LifeOSBackupService.make(
            profiles: profiles, categories: categories, activities: activities,
            calendarItems: calendarItems, sessions: sessions, foodEntries: foodEntries,
            weightEntries: weightEntries, baseballEntries: baseballEntries,
            savedTemplates: savedTemplates
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            exportDocument = LifeOSJSONDocument(data: try encoder.encode(payload))
            exporting = true
        } catch {
            showStatus("Export Failed", error.localizedDescription)
        }
    }

    private func restore(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(LifeOSBackupPayload.self, from: data)
            try LifeOSBackupService.restore(payload, into: modelContext)
            showStatus("Backup Restored", "Profiles and records were merged successfully. Existing matching records were not duplicated.")
        } catch {
            showStatus("Restore Failed", error.localizedDescription)
        }
    }

    private func showStatus(_ title: String, _ message: String) {
        statusTitle = title
        statusMessage = message
        showingStatus = true
    }
}

struct LifeOSJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
