//
//  RootTabView.swift
//  LifeOS
//
//  Improvement dashboard first: period confidence, today's timeline,
//  category map, and detailed progress share one selected profile.
//

import SwiftUI
import SwiftData
import Observation

/// Holds which profile is currently active, shared across tabs.
@Observable
final class SelectedProfile {
    static let lastProfileKey = "LifeOS.lastSelectedProfileID"

    var profile: Profile? {
        didSet {
            if let id = profile?.id.uuidString {
                UserDefaults.standard.set(id, forKey: Self.lastProfileKey)
            }
        }
    }
}

struct RootTabView: View {
    @State private var selection = SelectedProfile()

    var body: some View {
        TabView {
            ImprovementDashboardView(selection: selection)
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent") }

            TodayTimelineView(selection: selection)
                .tabItem { Label("Today", systemImage: "calendar") }

            WeeklyScheduleView(selection: selection)
                .tabItem { Label("Week", systemImage: "calendar.day.timeline.left") }

            ImprovementCategoriesView(selection: selection)
                .tabItem { Label("Categories", systemImage: "square.grid.2x2.fill") }

            DailyProgressView(selection: selection)
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Profile.self, SavedCategoryTemplate.self, AppCategory.self, Activity.self, CalendarItem.self, ActivitySession.self, FoodEntry.self, WeightEntry.self, BaseballEntry.self], inMemory: true)
}
