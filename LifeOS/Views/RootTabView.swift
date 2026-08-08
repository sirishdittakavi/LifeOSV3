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
            TodayTimelineView(selection: selection)
                .tabItem { Label("Today", systemImage: "calendar") }

            ImprovementCategoriesView(selection: selection)
                .tabItem { Label("Plans", systemImage: "list.bullet.clipboard") }

            ImprovementDashboardView(selection: selection)
                .tabItem { Label("Goals", systemImage: "scope") }

            WeeklyScheduleView(selection: selection)
                .tabItem { Label("Week", systemImage: "calendar.day.timeline.left") }

            DailyProgressView(selection: selection)
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Profile.self, SavedCategoryTemplate.self, AppCategory.self, Goal.self, GoalAreaContribution.self, ResultMeasure.self, ResultEntry.self, Activity.self, CalendarItem.self, ActivitySession.self, FoodEntry.self, WeightEntry.self, SportEntry.self], inMemory: true)
}
