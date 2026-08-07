//
//  LifeOSApp.swift
//  LifeOS
//
//  Entry point. Local-first per DESIGN.md — everything persists on-device
//  via SwiftData. No network, no account required.
//

import SwiftUI
import SwiftData

@main
struct LifeOSApp: App {

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Profile.self,
            SavedCategoryTemplate.self,
            AppCategory.self,
            Activity.self,
            CalendarItem.self,
            ActivitySession.self,
            FoodEntry.self,
            WeightEntry.self,
            BaseballEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            SeedData.seedIfNeeded(context: container.mainContext)
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(sharedModelContainer)
    }
}
