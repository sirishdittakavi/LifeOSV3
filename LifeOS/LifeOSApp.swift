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
