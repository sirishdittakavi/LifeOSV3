//
//  LifeOSApp.swift
//  LifeOS
//
//  Local-first app entry point with an explicit Version 1 SwiftData schema.
//  A persistent-store failure opens a recovery gate before the user can log
//  anything. Temporary use requires confirmation and remains visibly marked.
//

import SwiftUI
import SwiftData
import Observation

@main
struct LifeOSApp: App {
    @State private var store = LifeOSStore()

    var body: some Scene {
        WindowGroup {
            StoreRecoveryGate(store: store)
                .modelContainer(store.container)
        }
    }
}

@MainActor
@Observable
final class LifeOSStore {
    private(set) var container: ModelContainer
    private(set) var persistentStoreFailed = false

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            do {
                let container = try LifeOSDataStore.makeContainer(inMemory: true)
                try Self.prepareUITestFixture(container)
                self.container = container
                return
            } catch {
                fatalError("LifeOS UI-test fixture failed: \(error.localizedDescription)")
            }
        }
        #endif
        do {
            let container = try LifeOSDataStore.makeContainer(inMemory: false)
            try Self.prepare(container)
            self.container = container
        } catch {
            self.container = Self.makeFallbackContainer()
            self.persistentStoreFailed = true
            Self.logStoreFailure(error)
        }
    }

    func retryPersistentStore() {
        do {
            let container = try LifeOSDataStore.makeContainer(inMemory: false)
            try Self.prepare(container)
            self.container = container
            self.persistentStoreFailed = false
        } catch {
            Self.logStoreFailure(error)
        }
    }

    private static func prepare(_ container: ModelContainer) throws {
        try SeedData.seedIfNeeded(context: container.mainContext)
    }

    #if DEBUG
    /// A small, deterministic workspace used only by XCUITest. Release and
    /// TestFlight builds do not contain this test-data path.
    private static func prepareUITestFixture(_ container: ModelContainer) throws {
        UserDefaults.standard.set(true, forKey: "LifeOS.onboarding.v1.completed")
        UserDefaults.standard.removeObject(forKey: SelectedProfile.lastProfileKey)

        let context = container.mainContext
        let profile = Profile(name: "UI Test Athlete", kind: .individual, colorToken: "blue")
        let baseball = AppCategory(
            profile: profile, name: "Baseball", symbol: "baseball.fill",
            colorToken: "orange", pillar: .sport, trackingKind: .sport,
            purpose: "Build dependable baseball skills.",
            weeklyTargetSessions: 21, weeklyTargetMinutes: 210
        )
        let nutrition = AppCategory(
            profile: profile, name: "Nutrition", symbol: "fork.knife",
            colorToken: "green", pillar: .nutrition, trackingKind: .nutrition,
            purpose: "Fuel training and recovery.",
            weeklyTargetSessions: 7, weeklyTargetMinutes: 0
        )
        context.insert(profile)
        context.insert(baseball)
        context.insert(nutrition)

        let goal = Goal(
            profile: profile, name: "Become a Complete Baseball Player",
            purpose: "Improve batting, pitching, and fielding through a balanced plan."
        )
        let contribution = GoalAreaContribution(
            goal: goal, category: baseball,
            statement: "Baseball practice supports this Goal.",
            weeklyTargetSessions: 11, weeklyTargetMinutes: 110
        )
        context.insert(goal)
        context.insert(contribution)

        let todayWeekday = Calendar.current.component(.weekday, from: .now)
        let otherWeekdays = (1...7).filter { $0 != todayWeekday }.prefix(2)
        let tasks = [
            Activity(
                profile: profile, category: baseball, name: "Hitting",
                source: .manual, targetValue: 10, targetUnit: "min",
                repeatType: .daily, weekdays: Array(1...7),
                plannedStartMinutes: 18 * 60, estimatedDurationMinutes: 10,
                startDate: Calendar.current.startOfDay(for: .now)
            ),
            Activity(
                profile: profile, category: baseball, name: "Pitching",
                source: .manual, targetValue: 10, targetUnit: "min",
                repeatType: .timesPerWeek,
                weekdays: ([todayWeekday] + Array(otherWeekdays)).sorted(),
                occurrencesPerWeek: 3,
                plannedStartMinutes: 18 * 60 + 15, estimatedDurationMinutes: 10,
                startDate: Calendar.current.startOfDay(for: .now)
            ),
            Activity(
                profile: profile, category: baseball, name: "Fielding",
                source: .manual, targetValue: 10, targetUnit: "min",
                repeatType: .timesPerWeek, weekdays: [todayWeekday],
                occurrencesPerWeek: 1,
                plannedStartMinutes: 18 * 60 + 30, estimatedDurationMinutes: 10,
                startDate: Calendar.current.startOfDay(for: .now)
            )
        ]
        tasks.forEach(context.insert)

        context.insert(Activity(
            profile: profile, category: baseball, name: "Future Conditioning",
            source: .manual, targetValue: 10, targetUnit: "min",
            repeatType: .daily, weekdays: Array(1...7),
            plannedStartMinutes: 19 * 60, estimatedDurationMinutes: 10,
            startDate: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        ))
        try context.save()
    }
    #endif

    private static func makeFallbackContainer() -> ModelContainer {
        do {
            let container = try LifeOSDataStore.makeContainer(inMemory: true)
            try prepare(container)
            return container
        } catch {
            fatalError("LifeOS model schema is invalid: \(error.localizedDescription)")
        }
    }

    private static func logStoreFailure(_ error: Error) {
        #if DEBUG
        print("LifeOS persistent store failed to load: \(error.localizedDescription)")
        #endif
    }
}

private struct StoreRecoveryGate: View {
    @Bindable var store: LifeOSStore
    @State private var temporarySessionAccepted = false
    @State private var confirmingTemporarySession = false

    var body: some View {
        Group {
            if store.persistentStoreFailed && !temporarySessionAccepted {
                recoveryView
            } else {
                RootTabView()
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if store.persistentStoreFailed {
                            temporarySessionWarning
                        }
                    }
            }
        }
        .confirmationDialog(
            "Use a Temporary Session?",
            isPresented: $confirmingTemporarySession,
            titleVisibility: .visible
        ) {
            Button("Use Temporary Session", role: .destructive) {
                temporarySessionAccepted = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anything entered in the temporary session will disappear when LifeOS closes.")
        }
        .onChange(of: store.persistentStoreFailed) { _, failed in
            if !failed { temporarySessionAccepted = false }
        }
    }

    private var recoveryView: some View {
        ContentUnavailableView {
            Label("Saved Data Couldn’t Open", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("LifeOS has not changed or deleted the saved database. Retry first. Temporary mode is available for viewing the app, but it cannot save this session permanently.")
        } actions: {
            VStack(spacing: LifeOSSpacing.md) {
                Button("Retry", action: store.retryPersistentStore)
                    .buttonStyle(.borderedProminent)
                Button("Use Temporary Session") {
                    confirmingTemporarySession = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(LifeOSSpacing.xl)
    }

    private var temporarySessionWarning: some View {
        Label("Temporary session — changes will be lost", systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, LifeOSSpacing.lg)
            .padding(.vertical, LifeOSSpacing.sm)
            .foregroundStyle(.black)
            .background(Color.yellow)
            .accessibilityHint("Close LifeOS and reopen it after resolving the saved-data problem")
    }
}
