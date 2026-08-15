import SwiftUI
import SwiftData

struct WeeklyScheduleView: View {
    @Bindable var selection: SelectedProfile
    @Environment(\.modelContext) private var modelContext
    @Query private var activities: [Activity]
    @Query private var allItems: [CalendarItem]

    @State private var weekOffset = 0
    @State private var selectedDate = Date.now
    @State private var showingAddTask = false
    @State private var showingDatePicker = false
    @State private var selectedItem: CalendarItem?

    private let calendar = Calendar.current

    private var currentWeekStart: Date {
        monday(containing: .now)
    }

    private var weekStart: Date {
        calendar.date(byAdding: .weekOfYear, value: weekOffset, to: currentWeekStart) ?? currentWeekStart
    }

    private var visibleDates: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var visibleItems: [CalendarItem] {
        guard let profile = selection.profile else { return [] }
        return allItems.filter { item in
            item.profile?.id == profile.id
                && visibleDates.contains { calendar.isSameDay($0, as: item.date) }
        }
    }

    private var selectedDayItems: [CalendarItem] {
        visibleItems
            .filter { calendar.isSameDay($0.date, as: selectedDate) }
            .sorted { ($0.plannedStart ?? $0.date) < ($1.plannedStart ?? $1.date) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                calendarHeader
                weekStrip

                if selectedDayItems.isEmpty {
                    emptyDay
                } else {
                    dayAgenda
                }
            }
            .background(Color.lifeOSCanvas)
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfilePicker(selection: selection) }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingDatePicker = true } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Choose date")
                    Button { showingAddTask = true } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(selection.profile == nil)
                }
            }
            .onAppear {
                selectedDate = calendar.startOfDay(for: .now)
                generateVisibleWeek()
            }
            .onChange(of: selection.profile?.id) { generateVisibleWeek() }
            .onChange(of: weekOffset) { generateVisibleWeek() }
            .sheet(isPresented: $showingAddTask) {
                if let profile = selection.profile { AddActivityView(profile: profile) }
            }
            .sheet(isPresented: $showingDatePicker) {
                datePickerSheet
            }
            .sheet(item: $selectedItem) { item in
                WeekItemDetailView(item: item)
            }
        }
    }

    @ViewBuilder
    private var calendarHeader: some View {
        HStack(spacing: 10) {
            Button { moveWeek(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(LifeOSCompactButtonStyle())
            .accessibilityLabel("Previous week")

            Button { showingDatePicker = true } label: {
                VStack(spacing: 2) {
                    Text(weekRangeTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(weekOffset == 0 ? "This week" : "Tap to choose a date")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { moveWeek(1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(LifeOSCompactButtonStyle())
            .accessibilityLabel("Next week")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)

        if weekOffset != 0 {
            Button { jump(to: .now) } label: {
                Label("Return to today", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(LifeOSCompactButtonStyle(tint: .blue))
            .padding(.top, 8)
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 5) {
            ForEach(visibleDates, id: \.self) { date in
                let selected = calendar.isSameDay(date, as: selectedDate)
                let itemCount = items(on: date).count
                Button {
                    selectedDate = date
                } label: {
                    VStack(spacing: 5) {
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(.semibold))
                        Text(date.formatted(.dateTime.day()))
                            .font(.headline)
                        if itemCount > 0 {
                            Text("\(itemCount)")
                                .font(.caption2.weight(.bold))
                                .frame(minWidth: 18, minHeight: 18)
                                .background(selected ? Color.white.opacity(0.22) : Color.blue.opacity(0.12))
                                .clipShape(Capsule())
                        } else {
                            Circle().fill(Color.clear).frame(width: 18, height: 18)
                        }
                    }
                    .foregroundStyle(selected ? .white : (calendar.isDateInToday(date) ? Color.blue : Color.primary))
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .background(selected ? Color.blue : Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        if calendar.isDateInToday(date) && !selected {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.blue.opacity(0.55), lineWidth: 1.5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(itemCount) Tasks")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var dayAgenda: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                DayScheduleSummary(date: selectedDate, items: selectedDayItems)

                ForEach(DayPart.allCases) { part in
                    let partItems = selectedDayItems.filter { part.contains($0.plannedStart ?? $0.date, calendar: calendar) }
                    if !partItems.isEmpty {
                        Text(part.rawValue.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ForEach(partItems) { item in
                            Button { selectedItem = item } label: {
                                AgendaEventCard(item: item, isCurrent: isCurrent(item))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
    }

    private var emptyDay: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 42))
                .foregroundStyle(.blue)
            VStack(spacing: 6) {
                Text("No Tasks on \(selectedDate.formatted(.dateTime.weekday(.wide)))")
                    .font(.title3.weight(.semibold))
                Text("Enjoy the open space, or add something you want to work on.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button { showingAddTask = true } label: {
                Label("Add a Task", systemImage: "plus")
            }
            .buttonStyle(LifeOSPrimaryButtonStyle())
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "Choose a date",
                selection: Binding(get: { selectedDate }, set: { jump(to: $0) }),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Choose Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingDatePicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var weekRangeTitle: String {
        guard let last = visibleDates.last else { return "Schedule" }
        if calendar.component(.month, from: weekStart) == calendar.component(.month, from: last) {
            return "\(weekStart.formatted(.dateTime.month(.wide))) \(weekStart.formatted(.dateTime.day()))–\(last.formatted(.dateTime.day()))"
        }
        return "\(weekStart.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func items(on date: Date) -> [CalendarItem] {
        visibleItems.filter { calendar.isSameDay($0.date, as: date) }
    }

    private func monday(containing date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        return calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: day) ?? day
    }

    private func moveWeek(_ amount: Int) {
        weekOffset += amount
        selectedDate = calendar.date(byAdding: .weekOfYear, value: amount, to: selectedDate) ?? weekStart
    }

    private func jump(to date: Date) {
        let day = calendar.startOfDay(for: date)
        let targetWeek = monday(containing: day)
        let days = calendar.dateComponents([.day], from: currentWeekStart, to: targetWeek).day ?? 0
        weekOffset = days / 7
        selectedDate = day
    }

    private func isCurrent(_ item: CalendarItem) -> Bool {
        guard calendar.isDateInToday(item.date), let start = item.plannedStart else { return false }
        let end = item.plannedEnd
            ?? calendar.date(byAdding: .minute, value: item.activity?.estimatedDurationMinutes ?? 30, to: start)
            ?? start
        return Date.now >= start && Date.now <= end
    }

    private func generateVisibleWeek() {
        guard let profile = selection.profile else { return }
        var inserted = false
        for date in visibleDates {
            do {
                let newItems = try PlanningService.insertMissingCalendarItems(
                    profile: profile, date: date, activities: activities, context: modelContext
                )
                if !newItems.isEmpty { inserted = true }
            } catch {
                PersistenceIssueCenter.shared.report(error)
                return
            }
        }
        if inserted || modelContext.hasChanges { modelContext.saveOrReport() }
    }
}

private struct DayScheduleSummary: View {
    let date: Date
    let items: [CalendarItem]

    private var done: Int { items.filter { $0.status == .done }.count }
    private var minutes: Int { items.reduce(0) { $0 + ($1.activity?.estimatedDurationMinutes ?? 0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(date.formatted(.dateTime.weekday(.wide)))
                        .font(.lifeOSScreenTitle)
                    Text(date.formatted(.dateTime.month(.wide).day()))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(done)/\(items.count) done")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(done == items.count ? Color.lifeOSOnTrack : Color.lifeOSAccent)
            }
            ProgressView(value: items.isEmpty ? 0 : Double(done) / Double(items.count))
                .tint(done == items.count ? Color.lifeOSOnTrack : Color.lifeOSAccent)
            Text("\(items.count) Tasks · \(minutes) planned minutes")
                .font(.caption).foregroundStyle(.secondary)
        }
        .lifeOSCard()
    }
}

private struct AgendaEventCard: View {
    let item: CalendarItem
    let isCurrent: Bool

    private var categoryColor: Color {
        ColorToken.color(for: item.activity?.category?.colorToken ?? "gray")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.plannedStart?.formatted(date: .omitted, time: .shortened) ?? "Any time")
                    .font(.subheadline.weight(.bold))
                Text("\(item.activity?.estimatedDurationMinutes ?? 0) min")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 68, alignment: .leading)

            RoundedRectangle(cornerRadius: 2)
                .fill(categoryColor)
                .frame(width: 4, height: 54)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.activity?.name ?? "Task")
                        .font(.headline).foregroundStyle(.primary).lineLimit(2)
                    if isCurrent {
                        Text("NOW")
                            .font(.caption2.weight(.bold)).foregroundStyle(.red)
                    }
                }
                if let category = item.activity?.category {
                    Label(category.name, systemImage: category.symbol)
                        .font(.caption).foregroundStyle(categoryColor)
                }
            }

            Spacer(minLength: 6)
            StatusBadge(status: item.status)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .lifeOSCard(cornerRadius: 16)
    }
}

private struct StatusBadge: View {
    let status: CalendarItemStatus

    private var color: Color {
        switch status {
        case .done: return .green
        case .inProgress: return .blue
        case .skipped: return .gray
        case .rescheduled: return .orange
        case .planned, .unplanned: return .secondary
        }
    }

    var body: some View {
        Image(systemName: status == .done ? "checkmark.circle.fill" : "circle.fill")
            .font(status == .done ? Font.body : Font.system(size: 8))
            .foregroundStyle(color)
            .accessibilityLabel(status.rawValue)
    }
}

private enum DayPart: String, CaseIterable, Identifiable {
    case morning = "Morning"
    case afternoon = "Afternoon"
    case evening = "Evening"

    var id: String { rawValue }

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        switch self {
        case .morning: return hour < 12
        case .afternoon: return hour >= 12 && hour < 17
        case .evening: return hour >= 17
        }
    }
}

private struct WeekItemDetailView: View {
    @Bindable var item: CalendarItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var recording = false
    @State private var editingTask = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.activity?.name ?? "Task").font(.title2.weight(.bold))
                        if let category = item.activity?.category {
                            Label(category.name, systemImage: category.symbol)
                                .foregroundStyle(ColorToken.color(for: category.colorToken))
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Schedule") {
                    LabeledContent("Date", value: item.date.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Starts", value: item.plannedStart?.formatted(date: .omitted, time: .shortened) ?? "Any time")
                    LabeledContent("Duration", value: "\(item.activity?.estimatedDurationMinutes ?? 0) min")
                    LabeledContent("Status", value: item.status.rawValue)
                }
                if item.activity != nil {
                    Section {
                        Button { editingTask = true } label: {
                            Label("Edit Task", systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(LifeOSPrimaryButtonStyle())
                        .accessibilityHint("Edit the Task name, Plan, target, schedule, time, and duration")
                    }
                }
                Section("What happened?") {
                    if item.status != .done {
                        VStack(spacing: 10) {
                            Button { recording = true } label: {
                                Label("Record as Done", systemImage: "checkmark")
                            }
                            .buttonStyle(LifeOSPrimaryButtonStyle())

                            Button {
                                let previousStatus = item.status
                                item.status = .skipped
                                if modelContext.saveOrReport() { dismiss() }
                                else { item.status = previousStatus }
                            } label: {
                                Label("Skip This Occurrence", systemImage: "forward.end")
                            }
                            .buttonStyle(LifeOSSecondaryButtonStyle())
                        }
                        .padding(.vertical, 4)
                    } else {
                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } }
            }
            .sheet(isPresented: $recording) { RecordActualView(item: item) }
            .sheet(isPresented: $editingTask) {
                if let activity = item.activity {
                    EditTaskView(activity: activity, onActivityDeleted: { dismiss() })
                }
            }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Profile.self, SavedCategoryTemplate.self, AppCategory.self, Goal.self, GoalAreaContribution.self, ResultMeasure.self, ResultEntry.self, Activity.self, CalendarItem.self, ActivitySession.self, FoodEntry.self, WeightEntry.self, SportEntry.self], inMemory: true)
}
