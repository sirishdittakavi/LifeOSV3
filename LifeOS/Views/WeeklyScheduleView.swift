import SwiftUI
import SwiftData

struct WeeklyScheduleView: View {
    @Bindable var selection: SelectedProfile
    @Environment(\.modelContext) private var modelContext
    @Query private var activities: [Activity]
    @Query private var allItems: [CalendarItem]
    @Query private var categories: [AppCategory]

    @State private var weekOffset = 0
    @State private var dayRange: WeekDayRange = .workWeek
    @State private var showingAddTask = false
    @State private var selectedItem: CalendarItem?

    private let calendar = Calendar.current
    private let timeGutterWidth: CGFloat = 62
    private let dayColumnWidth: CGFloat = 138
    private let dayHeaderHeight: CGFloat = 54
    private let hourHeight: CGFloat = 76

    private var weekStart: Date {
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        let currentMonday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        return calendar.date(byAdding: .weekOfYear, value: weekOffset, to: currentMonday) ?? currentMonday
    }

    private var visibleDates: [Date] {
        (0..<dayRange.dayCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: weekStart)
        }
    }

    private var visibleItems: [CalendarItem] {
        guard let profile = selection.profile else { return [] }
        return allItems.filter { item in
            item.profile?.id == profile.id && visibleDates.contains { calendar.isSameDay($0, as: item.date) }
        }
    }

    private var startMinute: Int {
        let earliest = visibleItems.compactMap(\.plannedStart).map {
            calendar.component(.hour, from: $0) * 60 + calendar.component(.minute, from: $0)
        }.min() ?? 6 * 60
        return max(0, (earliest / 60) * 60)
    }

    private var endMinute: Int {
        let latest = visibleItems.compactMap { item -> Int? in
            guard let end = item.plannedEnd ?? item.plannedStart else { return nil }
            return calendar.component(.hour, from: end) * 60 + calendar.component(.minute, from: end)
        }.max() ?? 21 * 60
        let rounded = ((latest + 59) / 60) * 60
        return min(24 * 60, max(rounded, startMinute + 6 * 60))
    }

    private var timelineHeight: CGFloat {
        CGFloat(endMinute - startMinute) / 60 * hourHeight
    }

    private var legendCategories: [AppCategory] {
        var seen: Set<UUID> = []
        return visibleItems.compactMap { $0.activity?.category }.filter { seen.insert($0.id).inserted }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                weekControls

                Picker("Days", selection: $dayRange) {
                    ForEach(WeekDayRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if visibleItems.isEmpty {
                    ContentUnavailableView(
                        "Nothing Scheduled This Week",
                        systemImage: "calendar.badge.plus",
                        description: Text("Add a task with a start time and repeat schedule.")
                    )
                } else {
                    scheduleGrid
                    categoryLegend
                }
            }
            .navigationTitle("Weekly Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfilePicker(selection: selection) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddTask = true } label: { Image(systemName: "plus") }
                        .disabled(selection.profile == nil)
                }
            }
            .onAppear { generateVisibleWeek() }
            .onChange(of: selection.profile?.id) { generateVisibleWeek() }
            .onChange(of: weekOffset) { generateVisibleWeek() }
            .onChange(of: dayRange) { generateVisibleWeek() }
            .sheet(isPresented: $showingAddTask) {
                if let profile = selection.profile { AddActivityView(profile: profile) }
            }
            .sheet(item: $selectedItem) { item in
                WeekItemDetailView(item: item)
            }
        }
    }

    private var weekControls: some View {
        HStack(spacing: 12) {
            Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
            Spacer()
            VStack(spacing: 2) {
                Text(weekRangeTitle).font(.headline)
                if weekOffset != 0 {
                    Button("Return to this week") { weekOffset = 0 }
                        .font(.caption)
                }
            }
            Spacer()
            Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal)
    }

    private var weekRangeTitle: String {
        guard let last = visibleDates.last else { return "This Week" }
        return "\(weekStart.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var scheduleGrid: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 0) {
                timeRuler
                ForEach(visibleDates, id: \.self) { date in
                    dayColumn(date)
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator).opacity(0.45)))
            .padding(.horizontal)
        }
    }

    private var timeRuler: some View {
        VStack(spacing: 0) {
            Text("TIME")
                .font(.caption).bold().foregroundStyle(.secondary)
                .frame(width: timeGutterWidth, height: dayHeaderHeight)
                .background(Color(.secondarySystemBackground))
            ZStack(alignment: .topTrailing) {
                ForEach(hourMarks, id: \.self) { minute in
                    Text(timeLabel(minute))
                        .font(.caption2).bold()
                        .foregroundStyle(.secondary)
                        .frame(width: timeGutterWidth - 8, alignment: .trailing)
                        .offset(y: yOffset(for: minute) - 7)
                }
            }
            .frame(width: timeGutterWidth, height: timelineHeight, alignment: .top)
            .background(Color(.secondarySystemBackground).opacity(0.72))
        }
    }

    private func dayColumn(_ date: Date) -> some View {
        let items = visibleItems.filter { calendar.isSameDay($0.date, as: date) }
        return VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.caption).bold()
                Text(date.formatted(.dateTime.day()))
                    .font(.title3).bold()
            }
            .foregroundStyle(calendar.isDateInToday(date) ? .white : .primary)
            .frame(width: dayColumnWidth, height: dayHeaderHeight)
            .background(calendar.isDateInToday(date) ? Color.blue : Color(.secondarySystemBackground))

            ZStack(alignment: .topLeading) {
                ForEach(halfHourMarks, id: \.self) { minute in
                    Rectangle()
                        .fill(Color(.separator).opacity(minute % 60 == 0 ? 0.35 : 0.16))
                        .frame(width: dayColumnWidth, height: 0.5)
                        .offset(y: yOffset(for: minute))
                }

                if calendar.isDateInToday(date) {
                    let nowMinute = calendar.component(.hour, from: .now) * 60 + calendar.component(.minute, from: .now)
                    if nowMinute >= startMinute && nowMinute <= endMinute {
                        HStack(spacing: 3) {
                            Circle().fill(.red).frame(width: 7, height: 7)
                            Rectangle().fill(.red).frame(height: 1.5)
                        }
                        .offset(x: 1, y: yOffset(for: nowMinute) - 3)
                        .zIndex(4)
                    }
                }

                ForEach(items) { item in
                    weekEvent(item)
                }
            }
            .frame(width: dayColumnWidth, height: timelineHeight, alignment: .topLeading)
            .overlay(alignment: .leading) { Divider() }
        }
    }

    private func weekEvent(_ item: CalendarItem) -> some View {
        let start = item.plannedStart ?? item.date
        let minute = calendar.component(.hour, from: start) * 60 + calendar.component(.minute, from: start)
        let duration = max(15, item.activity?.estimatedDurationMinutes ?? 30)
        let height = max(30, CGFloat(duration) / 60 * hourHeight)
        let color = ColorToken.color(for: item.activity?.category?.colorToken ?? "gray")

        return Button {
            selectedItem = item
        } label: {
            HStack(spacing: 5) {
                Rectangle().fill(color).frame(width: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.activity?.name ?? "Task")
                        .font(.caption).bold().lineLimit(2)
                    if height >= 48 {
                        Text(start.formatted(date: .omitted, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                        if let category = item.activity?.category, height >= 66 {
                            Text(category.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 1)
                if item.status == .done {
                    Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.trailing, 5)
        .frame(width: dayColumnWidth - 8, height: height, alignment: .leading)
        .background(color.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.32)))
        .offset(x: 4, y: yOffset(for: minute))
    }

    private var categoryLegend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(legendCategories) { category in
                    Label(category.name, systemImage: category.symbol)
                        .font(.caption).bold()
                        .foregroundStyle(ColorToken.color(for: category.colorToken))
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(ColorToken.color(for: category.colorToken).opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 6)
    }

    private var hourMarks: [Int] {
        Array(stride(from: startMinute, through: endMinute, by: 60))
    }

    private var halfHourMarks: [Int] {
        Array(stride(from: startMinute, through: endMinute, by: 30))
    }

    private func yOffset(for minute: Int) -> CGFloat {
        CGFloat(minute - startMinute) / 60 * hourHeight
    }

    private func timeLabel(_ minute: Int) -> String {
        let day = calendar.startOfDay(for: .now)
        let date = calendar.date(byAdding: .minute, value: minute, to: day) ?? day
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func generateVisibleWeek() {
        guard let profile = selection.profile else { return }
        var inserted = false
        for date in visibleDates {
            let newItems = PlanningService.generateMissingCalendarItems(
                profile: profile, date: date, activities: activities, existingItems: allItems
            )
            for item in newItems {
                modelContext.insert(item)
                inserted = true
            }
        }
        if inserted { try? modelContext.save() }
    }
}

private struct WeekItemDetailView: View {
    @Bindable var item: CalendarItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var recording = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(item.activity?.name ?? "Task").font(.title2).bold()
                    if let category = item.activity?.category {
                        Label(category.name, systemImage: category.symbol)
                            .foregroundStyle(ColorToken.color(for: category.colorToken))
                    }
                }
                Section("Schedule") {
                    LabeledContent("Date", value: item.date.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Starts", value: item.plannedStart?.formatted(date: .omitted, time: .shortened) ?? "Not set")
                    LabeledContent("Duration", value: "\(item.activity?.estimatedDurationMinutes ?? 0) min")
                    LabeledContent("Status", value: item.status.rawValue)
                }
                Section("Actions") {
                    if item.status != .done {
                        Button { recording = true } label: {
                            Label("Record as Done", systemImage: "checkmark.circle.fill")
                        }
                        Button(role: .destructive) {
                            item.status = .skipped
                            try? modelContext.save()
                            dismiss()
                        } label: {
                            Label("Skip This Occurrence", systemImage: "forward.end")
                        }
                    } else {
                        Label("Completed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Schedule Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } }
            }
            .sheet(isPresented: $recording) { RecordActualView(item: item) }
        }
    }
}

private enum WeekDayRange: String, CaseIterable, Identifiable {
    case workWeek = "Mon–Fri"
    case fullWeek = "7 Days"

    var id: String { rawValue }
    var dayCount: Int { self == .workWeek ? 5 : 7 }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Profile.self, SavedCategoryTemplate.self, AppCategory.self, Activity.self, CalendarItem.self, ActivitySession.self, FoodEntry.self, WeightEntry.self, BaseballEntry.self], inMemory: true)
}
