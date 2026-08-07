//
//  DailyProgressView.swift
//  LifeOS
//
//  Implements DESIGN.md Section 10a: target vs actual, separate from
//  completion status. Today's numbers plus a 7-day trend per activity.
//

import SwiftUI
import SwiftData

struct DailyProgressView: View {
    @Bindable var selection: SelectedProfile

    @Query private var activities: [Activity]
    @Query(sort: \ActivitySession.date) private var sessions: [ActivitySession]

    private var todayProgress: [DailyActivityProgress] {
        guard let profile = selection.profile else { return [] }
        return ProgressEngine.dailyProgress(profile: profile, date: .now, activities: activities, sessions: sessions)
    }

    private var last7Days: [Date] {
        let calendar = Calendar.current
        return (0..<7).reversed().map {
            calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: .now))!
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if todayProgress.isEmpty {
                        ContentUnavailableView(
                            "No Tracked Targets Yet",
                            systemImage: "chart.bar.xaxis",
                            description: Text("Activities with a target (minutes, swings, grams...) will show progress here.")
                        )
                        .padding(.top, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TODAY'S PROGRESS").font(.caption).bold().foregroundStyle(.secondary)
                            Text("Target vs. actual — separate from completion status on Today.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)

                        VStack(spacing: 12) {
                            ForEach(todayProgress) { progress in
                                ProgressBarRow(progress: progress)
                            }
                        }
                        .padding(.horizontal)

                        Divider().padding(.horizontal)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("7-DAY TREND").font(.caption).bold().foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)

                        ForEach(todayProgress) { progress in
                            TrendRow(activity: progress.activity, days: last7Days, activities: activities, sessions: sessions)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfilePicker(selection: selection) }
            }
        }
    }
}

private struct ProgressBarRow: View {
    let progress: DailyActivityProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let category = progress.activity.category {
                    Image(systemName: category.symbol)
                        .foregroundStyle(ColorToken.color(for: category.colorToken))
                }
                Text(progress.activity.name).font(.subheadline).bold()
                Spacer()
                if let target = progress.target, let unit = progress.activity.targetUnit {
                    Text("\(Int(progress.actual)) / \(Int(target)) \(unit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: progress.cappedFraction)
                .tint(progress.activity.category.map { ColorToken.color(for: $0.colorToken) } ?? .blue)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct TrendRow: View {
    let activity: Activity
    let days: [Date]
    let activities: [Activity]
    let sessions: [ActivitySession]

    private func fraction(for day: Date) -> Double {
        guard let target = activity.targetValue, target > 0 else { return 0 }
        let calendar = Calendar.current
        let daySessions = sessions.filter { $0.activity?.id == activity.id && calendar.isSameDay($0.date, as: day) }
        let actual = daySessions.reduce(0.0) { $0 + $1.recordedValue }
        return min(actual / target, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(activity.name).font(.caption).bold()
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let f = fraction(for: day)
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(f >= 0.9 ? Color.green : (f >= 0.5 ? Color.orange : Color.gray.opacity(0.4)))
                            .frame(width: 20, height: max(4, f * 50))
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Profile.self, SavedCategoryTemplate.self, AppCategory.self, Activity.self, CalendarItem.self, ActivitySession.self, FoodEntry.self, WeightEntry.self, SportEntry.self], inMemory: true)
}
