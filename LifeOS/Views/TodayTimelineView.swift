//
//  TodayTimelineView.swift
//  LifeOS
//
//  The execution surface for a selected Profile. Every number comes from
//  real plan and evidence records; presentation never invents progress.
//

import SwiftUI
import SwiftData

struct TodayTimelineView: View {
    @Bindable var selection: SelectedProfile
    @Environment(\.modelContext) private var modelContext

    @Query private var activities: [Activity]
    @Query private var allItems: [CalendarItem]
    @Query private var foodEntries: [FoodEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]
    @Query private var sportEntries: [SportEntry]
    @Query private var categories: [AppCategory]
    @Query private var resultMeasures: [ResultMeasure]

    @State private var showingAddActivity = false
    @State private var showingAddWhatHappened = false
    @State private var recordingItem: CalendarItem?
    @State private var resultMeasureToRecord: ResultMeasure?
    @State private var feedbackTrigger = 0

    private var todayItems: [CalendarItem] {
        guard let profile = selection.profile else { return [] }
        let calendar = Calendar.current
        return allItems
            .filter { $0.profile?.id == profile.id && calendar.isSameDay($0.date, as: .now) }
            .sorted { ($0.plannedStart ?? .distantPast) < ($1.plannedStart ?? .distantPast) }
    }

    private var summary: CompletionSummary {
        ProgressEngine.completionSummary(items: todayItems)
    }

    private var dueResultMeasures: [ResultMeasure] {
        guard let profile = selection.profile else { return [] }
        let startOfToday = Calendar.current.startOfDay(for: .now)
        return resultMeasures
            .filter { measure in
                guard measure.isActive,
                      measure.goal?.profile?.id == profile.id,
                      let nextDate = measure.nextCheckInDate else { return false }
                return Calendar.current.startOfDay(for: nextDate) <= startOfToday
            }
            .sorted { ($0.nextCheckInDate ?? .distantFuture) < ($1.nextCheckInDate ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TodayAtmosphericBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        dayHeading
                        TodayProgressHero(summary: summary)
                        dailySignals
                        dueResults
                        journey
                    }
                    .padding(.horizontal, LifeOSSpacing.lg)
                    .padding(.top, LifeOSSpacing.sm)
                    .padding(.bottom, LifeOSSpacing.xxl)
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ProfilePicker(selection: selection)
                        .frame(minHeight: 44)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        feedbackTrigger += 1
                        showingAddActivity = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Add Task")
                    .accessibilityHint("Opens the new Task form")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                addWhatHappenedButton
            }
            .sensoryFeedback(.selection, trigger: feedbackTrigger)
            .onAppear { generateTodayItemsIfNeeded() }
            .onChange(of: selection.profile?.id) { generateTodayItemsIfNeeded() }
            .sheet(isPresented: $showingAddActivity) {
                if let profile = selection.profile { AddActivityView(profile: profile) }
            }
            .sheet(isPresented: $showingAddWhatHappened) {
                if let profile = selection.profile { AddWhatHappenedView(profile: profile) }
            }
            .sheet(item: $recordingItem) { item in
                RecordActualView(item: item)
            }
            .sheet(item: $resultMeasureToRecord) { measure in
                if let profile = selection.profile {
                    AddResultEntryView(profile: profile, measure: measure)
                }
            }
        }
    }

    private var dayHeading: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.title2.weight(.bold))
                Text(summary.remaining == 0 && summary.total > 0
                     ? "Your plan is complete."
                     : "One clear Task at a time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Image(systemName: summary.remaining == 0 && summary.total > 0
                  ? "checkmark.seal.fill" : "sun.max.fill")
                .font(.title2)
                .foregroundStyle(summary.remaining == 0 && summary.total > 0 ? .green : .orange)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 4)
    }

    private var addWhatHappenedButton: some View {
        Button {
            feedbackTrigger += 1
            showingAddWhatHappened = true
        } label: {
            Label("Log What Happened", systemImage: "plus.circle.fill")
        }
        .buttonStyle(LifeOSPrimaryButtonStyle())
        .padding(.horizontal, LifeOSSpacing.lg)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .accessibilityHint("Record an unscheduled Task, meal, weight, or sport session")
    }

    private var dailySignals: some View {
        let profile = selection.profile
        let todayFood = foodEntries.filter {
            $0.profile?.id == profile?.id && Calendar.current.isDateInToday($0.date)
        }
        let protein = todayFood.reduce(0.0) { $0 + $1.proteinGrams }
        let latestWeight = weightEntries.first { $0.profile?.id == profile?.id }
        let todaySportEntries = sportEntries.filter {
            $0.profile?.id == profile?.id && Calendar.current.isDateInToday($0.date)
        }
        let sportMinutes = todaySportEntries.reduce(0) { $0 + $1.durationMinutes }
        let profileSportCategories = categories.filter {
            $0.profile?.id == profile?.id && $0.trackingKind == .sport && $0.isActive
        }
        let loggedSportNames = Set(todaySportEntries.compactMap { $0.category?.name })
        let sportName = loggedSportNames.count == 1
            ? (loggedSportNames.first ?? "Sport")
            : (loggedSportNames.isEmpty && profileSportCategories.count == 1
                ? profileSportCategories[0].name : "Sport")
        let sportSymbol = todaySportEntries.compactMap(\.category).first?.symbol
            ?? profileSportCategories.first { $0.name == sportName }?.symbol
            ?? "figure.run"

        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("DAILY SIGNALS", symbol: "waveform.path.ecg")
            HStack(spacing: 10) {
                DailySignalCard(
                    title: "Protein",
                    value: "\(Int(protein))/\(Int(profile?.proteinGoalGrams ?? 0))g",
                    symbol: "fork.knife", color: .green
                )
                DailySignalCard(
                    title: "Weight",
                    value: latestWeight.map {
                        let unit = profile?.weightUnit ?? .kilograms
                        return "\(unit.displayValue(kilograms: $0.kilograms).formatted(.number.precision(.fractionLength(1))))\(unit.rawValue)"
                    } ?? "—",
                    symbol: "scalemass.fill", color: .blue
                )
                DailySignalCard(
                    title: sportName, value: "\(sportMinutes) min",
                    symbol: sportSymbol, color: .orange
                )
            }
        }
    }

    @ViewBuilder
    private var dueResults: some View {
        if !dueResultMeasures.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionLabel("RESULT CHECK-INS", symbol: "scope")
                    Spacer()
                    Text("\(dueResultMeasures.count) due")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.orange.opacity(0.12), in: Capsule())
                }

                ForEach(dueResultMeasures.prefix(3)) { measure in
                    Button {
                        feedbackTrigger += 1
                        resultMeasureToRecord = measure
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.blue)
                                .frame(width: 36, height: 36)
                                .background(.blue.opacity(0.10), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(measure.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(measure.goal?.name ?? "Goal")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text("Enter")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.blue)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Enter \(measure.name) result for \(measure.goal?.name ?? "goal")")
                }
            }
            .lifeOSGlassCard(tint: .orange)
        }
    }

    private var journey: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("TODAY'S JOURNEY", symbol: "calendar.day.timeline.left")
                Spacer()
                Text("\(todayItems.count) \(todayItems.count == 1 ? "Task" : "Tasks")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if todayItems.isEmpty {
                ContentUnavailableView(
                    "Nothing Scheduled",
                    systemImage: "calendar.badge.plus",
                    description: Text("Add a Task or log something that happened.")
                )
                .frame(maxWidth: .infinity, minHeight: 230)
                .lifeOSGlassCard(tint: .blue)
            } else {
                ForEach(todayItems) { item in
                    CalendarItemRow(
                        item: item,
                        onStart: { feedbackTrigger += 1; start(item) },
                        onDone: { feedbackTrigger += 1; recordingItem = item },
                        onSkip: { feedbackTrigger += 1; skip(item) }
                    )
                }
            }
        }
    }

    private func sectionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.bold))
            .tracking(0.7)
            .foregroundStyle(.secondary)
    }

    private func generateTodayItemsIfNeeded() {
        guard let profile = selection.profile else { return }
        let newItems = PlanningService.generateMissingCalendarItems(
            profile: profile, date: .now, activities: activities, existingItems: allItems
        )
        guard !newItems.isEmpty else { return }
        newItems.forEach { modelContext.insert($0) }
        if !modelContext.saveOrReport() { newItems.forEach { modelContext.delete($0) } }
    }

    private func start(_ item: CalendarItem) {
        let previousStatus = item.status
        let previousStart = item.actualStart
        item.status = .inProgress
        item.actualStart = .now
        if !modelContext.saveOrReport() {
            item.status = previousStatus
            item.actualStart = previousStart
        }
    }

    private func skip(_ item: CalendarItem) {
        let previousStatus = item.status
        item.status = .skipped
        if !modelContext.saveOrReport() { item.status = previousStatus }
    }
}

private struct TodayAtmosphericBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: colorScheme == .dark
                    ? [.indigo.opacity(0.18), .clear, .blue.opacity(0.08)]
                    : [.blue.opacity(0.10), .clear, .mint.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.blue.opacity(colorScheme == .dark ? 0.10 : 0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: 160, y: -280)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct TodayProgressHero: View {
    let summary: CompletionSummary

    private var percent: Int { Int((summary.percentComplete * 100).rounded()) }

    var body: some View {
        HStack(spacing: LifeOSSpacing.md) {
            ZStack {
                SignatureProgressRing(
                    fraction: summary.percentComplete,
                    gradient: ImprovementPillar.physical.gradient,
                    lineWidth: 8,
                    diameter: 88
                )
                GlacierProgressMark(fraction: summary.percentComplete)
                VStack(spacing: 0) {
                    Text("\(percent)%")
                        .font(.title3.weight(.bold).monospacedDigit())
                    Text("done").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 88, height: 88)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Daily plan \(percent) percent complete")

            VStack(alignment: .leading, spacing: 9) {
                Text("Daily plan").font(.title3.weight(.bold))
                Text(summary.total == 0
                     ? "Build your day with one meaningful Task."
                     : "\(summary.done) of \(summary.total) planned Tasks complete")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    SummaryPill(value: summary.done, label: "done", color: .green)
                    SummaryPill(value: summary.remaining, label: "left", color: .blue)
                    if summary.skipped > 0 {
                        SummaryPill(value: summary.skipped, label: "skipped", color: .secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .lifeOSGlassCard(tint: summary.remaining == 0 && summary.total > 0 ? .green : .blue,
                         cornerRadius: 26)
    }
}

/// A quiet glacier watermark makes daily progress recognisably LifeOS while
/// leaving the schedule and numeric completion value as the primary content.
private struct GlacierProgressMark: View {
    let fraction: Double

    private var safeFraction: Double {
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }

    var body: some View {
        ZStack {
            Image(systemName: "mountain.2.fill")
                .foregroundStyle(Color.primary.opacity(0.045))
            Image(systemName: "mountain.2.fill")
                .foregroundStyle(
                    LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom)
                )
                .mask(alignment: .bottom) {
                    Rectangle().frame(height: 42 * safeFraction)
                }
                .opacity(0.18)
        }
        .font(.system(size: 38, weight: .light))
        .accessibilityHidden(true)
    }
}

private struct SummaryPill: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        Text("\(value) \(label)")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.10), in: Capsule())
    }
}

private struct DailySignalCard: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.10), in: Circle())
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
    }
}

private struct CalendarItemRow: View {
    let item: CalendarItem
    let onStart: () -> Void
    let onDone: () -> Void
    let onSkip: () -> Void

    private var categoryColor: Color {
        item.activity?.category.map { ColorToken.color(for: $0.colorToken) } ?? .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 5) {
                    Image(systemName: item.activity?.category?.symbol ?? "circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(categoryColor)
                        .frame(width: 42, height: 42)
                        .background(categoryColor.opacity(0.11), in: Circle())
                    Text(item.plannedStart?.formatted(date: .omitted, time: .shortened) ?? "Any time")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 64)

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.activity?.name ?? "Task")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        if let category = item.activity?.category {
                            Text(category.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        StatusBadge(status: item.status)
                    }
                    if let duration = item.activity?.estimatedDurationMinutes, duration > 0 {
                        Label("\(duration) min", systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }

            actionButtons
        }
        .lifeOSGlassCard(tint: categoryColor, cornerRadius: 22)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch item.status {
        case .planned:
            HStack(spacing: 8) {
                Button("Start", action: onStart)
                    .buttonStyle(LifeOSInlineButtonStyle(tint: .blue))
                    .accessibilityHint("Marks this Task in progress")
                Button("Done", action: onDone)
                    .buttonStyle(LifeOSInlineButtonStyle(tint: .green, filled: true))
                    .accessibilityHint("Opens the result and notes form")
                Button("Skip", action: onSkip)
                    .buttonStyle(LifeOSInlineButtonStyle(tint: .secondary))
                    .accessibilityHint("Marks this Task skipped")
            }
        case .inProgress:
            HStack(spacing: 8) {
                Button("Finish", action: onDone)
                    .buttonStyle(LifeOSInlineButtonStyle(tint: .green, filled: true))
                    .accessibilityHint("Opens the result and notes form")
                Button("Skip", action: onSkip)
                    .buttonStyle(LifeOSInlineButtonStyle(tint: .secondary))
                    .accessibilityHint("Marks this Task skipped")
            }
        case .done:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(completionText).font(.caption).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
        case .skipped, .rescheduled, .unplanned:
            EmptyView()
        }
    }

    private var completionText: String {
        guard let target = item.activity?.targetValue,
              let unit = item.activity?.targetUnit else { return "Completed" }
        return "Completed · target \(target.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }
}

private struct StatusBadge: View {
    let status: CalendarItemStatus

    private var color: Color {
        switch status {
        case .done: return .green
        case .inProgress: return .blue
        case .skipped: return .secondary
        case .rescheduled: return .orange
        case .unplanned: return .purple
        case .planned: return .secondary
        }
    }

    var body: some View {
        Text(status.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.10), in: Capsule())
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Profile.self, SavedCategoryTemplate.self, AppCategory.self, Goal.self, GoalAreaContribution.self, ResultMeasure.self, ResultEntry.self, Activity.self, CalendarItem.self, ActivitySession.self, FoodEntry.self, WeightEntry.self, SportEntry.self], inMemory: true)
}
