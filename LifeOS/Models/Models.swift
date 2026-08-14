//
//  Models.swift
//  LifeOS
//
//  Domain model per DESIGN.md Version 1 Section 5. Activity -> Calendar Item ->
//  Session. Every Calendar Item originates from an Activity (ADR-011).
//  Planned and actual values are stored separately and never overwrite
//  each other (ADR-013).
//

import Foundation
import SwiftData

// MARK: - Profile (ADR-012: each Profile owns a separate calendar)

enum ProfileKind: String, Codable, CaseIterable, Identifiable {
    case parent = "Parent"
    case child = "Child"
    case individual = "Individual"
    var id: String { rawValue }
}

enum ProfileManagementMode: String, Codable, CaseIterable, Identifiable {
    case selfManaged = "Self-managed"
    case parentManaged = "Parent-managed"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .selfManaged:
            return "This person records and manages their own plan. Their own-phone access will use Family Sync when it is added."
        case .parentManaged:
            return "A parent or guardian records and manages this profile on the current device."
        }
    }

}

enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case kilograms = "kg"
    case pounds = "lb"

    var id: String { rawValue }

    func displayValue(kilograms: Double) -> Double {
        self == .kilograms ? kilograms : kilograms * 2.204_622_621_8
    }

    func kilograms(from value: Double) -> Double {
        self == .kilograms ? value : value / 2.204_622_621_8
    }
}

@Model
final class Profile {
    var id: UUID
    var name: String
    var kindRaw: String
    var colorToken: String
    @Attribute(.externalStorage) var avatarData: Data?
    var managementModeRaw: String = ""
    var weightUnitRaw: String = WeightUnit.kilograms.rawValue
    var weightGoalKilograms: Double?
    var calorieGoal: Double = 2200
    var proteinGoalGrams: Double = 120
    var carbohydrateGoalGrams: Double = 250
    var fatGoalGrams: Double = 70
    var waterGoalMilliliters: Double = 2500
    var isActive: Bool = true

    var kind: ProfileKind {
        get { ProfileKind(rawValue: kindRaw) ?? .individual }
        set { kindRaw = newValue.rawValue }
    }

    var weightUnit: WeightUnit {
        get { WeightUnit(rawValue: weightUnitRaw) ?? .kilograms }
        set { weightUnitRaw = newValue.rawValue }
    }

    var managementMode: ProfileManagementMode {
        get {
            ProfileManagementMode(rawValue: managementModeRaw)
                ?? (kind == .child ? .parentManaged : .selfManaged)
        }
        set { managementModeRaw = newValue.rawValue }
    }

    init(name: String, kind: ProfileKind, colorToken: String) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.colorToken = colorToken
        self.avatarData = nil
        self.managementModeRaw = (kind == .child
            ? ProfileManagementMode.parentManaged
            : ProfileManagementMode.selfManaged).rawValue
        self.weightGoalKilograms = nil
    }
}

// MARK: - Reusable local templates

struct SavedTaskBlueprint: Codable {
    let name: String
    let repeatTypeRaw: String
    let weekdays: [Int]
    let occurrencesPerDay: Int
    let occurrencesPerWeek: Int
    let repeatIntervalMinutes: Int
    let startMinutes: Int
    let durationMinutes: Int
    let targetValue: Double?
    let targetUnit: String?
}

enum AreaTrackingKind: String, Codable, CaseIterable, Identifiable {
    case tasks = "Tasks only"
    case nutrition = "Food & nutrition"
    case bodyWeight = "Body weight"
    case sport = "Sport training"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .tasks: return "Track scheduled Tasks and their completion."
        case .nutrition: return "Add food, water and nutrition evidence."
        case .bodyWeight: return "Record weight in kg or lb and review the trend."
        case .sport: return "Record training duration, repetitions, effort and soreness."
        }
    }

    /// Compatibility rule for records created before Areas stored an
    /// explicit tracking capability. Runtime behavior never depends on a
    /// user-editable name after this one-time migration.
    static func legacyDefault(name: String, pillar: ImprovementPillar) -> AreaTrackingKind {
        let normalizedName = name.lowercased()
        if pillar == .sport { return .sport }
        if normalizedName.contains("nutrition") || normalizedName.contains("food") { return .nutrition }
        if normalizedName.contains("weight") || normalizedName.contains("body composition") { return .bodyWeight }
        return .tasks
    }
}

@Model
final class SavedCategoryTemplate {
    var id: UUID
    var name: String
    var pillarRaw: String
    var trackingKindRaw: String = ""
    var symbol: String
    var colorToken: String
    var purpose: String
    var weeklySessions: Int
    var weeklyMinutes: Int
    @Attribute(.externalStorage) var taskBlueprintData: Data
    var createdAt: Date

    var pillar: ImprovementPillar {
        ImprovementPillar(rawValue: pillarRaw) ?? .learning
    }

    var trackingKind: AreaTrackingKind {
        AreaTrackingKind(rawValue: trackingKindRaw) ?? .tasks
    }

    var taskBlueprints: [SavedTaskBlueprint] {
        (try? JSONDecoder().decode([SavedTaskBlueprint].self, from: taskBlueprintData)) ?? []
    }

    init(category: AppCategory, activities: [Activity]) {
        id = UUID()
        name = category.name
        pillarRaw = category.pillar.rawValue
        trackingKindRaw = category.trackingKind.rawValue
        symbol = category.symbol
        colorToken = category.colorToken
        purpose = category.purpose
        weeklySessions = category.weeklyTargetSessions
        weeklyMinutes = category.weeklyTargetMinutes
        let blueprints = activities.map {
            SavedTaskBlueprint(
                name: $0.name, repeatTypeRaw: $0.repeatTypeRaw, weekdays: $0.weekdays,
                occurrencesPerDay: $0.occurrencesPerDay,
                occurrencesPerWeek: $0.occurrencesPerWeek,
                repeatIntervalMinutes: $0.repeatIntervalMinutes,
                startMinutes: $0.plannedStartMinutes,
                durationMinutes: $0.estimatedDurationMinutes,
                targetValue: $0.targetValue, targetUnit: $0.targetUnit
            )
        }
        taskBlueprintData = (try? JSONEncoder().encode(blueprints)) ?? Data()
        createdAt = .now
    }
}

// MARK: - Category

enum ImprovementPillar: String, Codable, CaseIterable, Identifiable {
    case physical = "Physical Development"
    case sport = "Sport Development"
    case nutrition = "Health & Nutrition"
    case learning = "Learning & Career"
    case life = "Life & Relationships"

    var id: String { rawValue }
}

@Model
final class AppCategory {
    var id: UUID
    var profile: Profile?
    var name: String
    var symbol: String
    var colorToken: String
    var pillarRaw: String = ImprovementPillar.learning.rawValue
    var trackingKindRaw: String = ""
    var purpose: String = ""
    var weeklyTargetSessions: Int = 3
    var weeklyTargetMinutes: Int = 120
    var parentCategoryIDString: String? = nil
    var relatedCategoryIDStrings: [String] = []
    var reminderEnabled: Bool = false
    var reminderHour: Int = 18
    var reminderMinute: Int = 0
    var isActive: Bool = true

    var pillar: ImprovementPillar {
        get { ImprovementPillar(rawValue: pillarRaw) ?? .learning }
        set { pillarRaw = newValue.rawValue }
    }

    var trackingKind: AreaTrackingKind {
        get { AreaTrackingKind(rawValue: trackingKindRaw) ?? .tasks }
        set { trackingKindRaw = newValue.rawValue }
    }

    var relatedCategoryIDs: [UUID] {
        get { relatedCategoryIDStrings.compactMap(UUID.init(uuidString:)) }
        set { relatedCategoryIDStrings = newValue.map(\.uuidString) }
    }

    var parentCategoryID: UUID? {
        get { parentCategoryIDString.flatMap(UUID.init(uuidString:)) }
        set { parentCategoryIDString = newValue?.uuidString }
    }

    var shouldScheduleReminders: Bool {
        isActive && reminderEnabled && (profile?.isActive ?? true)
    }

    init(profile: Profile? = nil, name: String, symbol: String, colorToken: String,
         pillar: ImprovementPillar = .learning, trackingKind: AreaTrackingKind = .tasks,
         purpose: String = "",
         weeklyTargetSessions: Int = 3, weeklyTargetMinutes: Int = 120) {
        self.id = UUID()
        self.profile = profile
        self.name = name
        self.symbol = symbol
        self.colorToken = colorToken
        self.pillarRaw = pillar.rawValue
        self.trackingKindRaw = trackingKind.rawValue
        self.purpose = purpose
        self.weeklyTargetSessions = weeklyTargetSessions
        self.weeklyTargetMinutes = weeklyTargetMinutes
        self.parentCategoryIDString = nil
    }
}

// MARK: - Goals and measurable results

/// Areas organise life; Goals describe the real-world change a person wants.
/// A Goal may be supported by several Areas through GoalAreaContribution.
@Model
final class Goal {
    var id: UUID
    var profile: Profile?
    var name: String
    var purpose: String
    var targetDate: Date?
    var createdAt: Date
    var isActive: Bool

    init(profile: Profile?, name: String, purpose: String = "", targetDate: Date? = nil) {
        self.id = UUID()
        self.profile = profile
        self.name = name
        self.purpose = purpose
        self.targetDate = targetDate
        self.createdAt = .now
        self.isActive = true
    }
}

/// Explains how one Area supports a Goal. Weekly values measure plan adherence,
/// not whether the Goal's outcome has been achieved.
@Model
final class GoalAreaContribution {
    var id: UUID
    var goal: Goal?
    var category: AppCategory?
    var statement: String
    var weeklyTargetSessions: Int
    var weeklyTargetMinutes: Int
    var isActive: Bool

    init(
        goal: Goal?, category: AppCategory?, statement: String = "",
        weeklyTargetSessions: Int = 0, weeklyTargetMinutes: Int = 0
    ) {
        self.id = UUID()
        self.goal = goal
        self.category = category
        self.statement = statement
        self.weeklyTargetSessions = weeklyTargetSessions
        self.weeklyTargetMinutes = weeklyTargetMinutes
        self.isActive = true
    }
}

enum ResultValueType: String, Codable, CaseIterable, Identifiable {
    case number = "Number"
    case rating = "Rating"
    case milestone = "Milestone"
    case text = "Written Assessment"

    var id: String { rawValue }
}

enum ResultDirection: String, Codable, CaseIterable, Identifiable {
    case increase = "Increase"
    case decrease = "Decrease"
    case targetRange = "Reach a Range"
    case maintainRange = "Stay in a Range"

    var id: String { rawValue }
}

enum ResultMeasureRole: String, Codable, CaseIterable, Identifiable {
    case primary = "Primary Result"
    case supporting = "Supporting Result"

    var id: String { rawValue }
}

enum ResultCheckInCadence: String, Codable, CaseIterable, Identifiable {
    case weekly = "Weekly"
    case monthly = "Monthly"
    case quarterly = "Every 3 Months"
    case onDemand = "When Available"

    var id: String { rawValue }

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .weekly: return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date)
        case .quarterly: return calendar.date(byAdding: .month, value: 3, to: date)
        case .onDemand: return nil
        }
    }
}

/// Defines how success is measured. Values are typed so charts never attempt
/// to turn arbitrary notes into misleading numbers.
@Model
final class ResultMeasure {
    var id: UUID
    var goal: Goal?
    var name: String
    var roleRaw: String
    var valueTypeRaw: String
    var unit: String
    var directionRaw: String
    var baselineValue: Double?
    var targetValue: Double?
    var targetMinimum: Double?
    var targetMaximum: Double?
    var ratingLabels: [String]
    var cadenceRaw: String
    var nextCheckInDate: Date?
    var reminderEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int
    var isActive: Bool
    /// Optional link to a MeasurementDefinition so this Result's progress can be
    /// derived from summed MeasurementEntry values instead of manual check-ins.
    /// Generic across any Activity type (Baseball, Guitar, Coding, ...).
    var linkedMeasurementDefinitionID: UUID?
    /// Optional link to a Nutrition macro/water metric (NutritionEngine.Metric),
    /// mirroring linkedMeasurementDefinitionID's role but reading Nutrition-native
    /// data (MealEntry/WaterEntry) instead of MeasurementEntry — Nutrition is
    /// deliberately not Activity-scoped (NUTRITION_MODULE_DESIGN_V1.md decision 1),
    /// so this is a sibling link, not a reuse of the Activity-measurement one.
    var linkedNutritionMetricRaw: String?
    /// Optional link to a BodyMetricDefinition (e.g. Weight) so this Result's
    /// progress can be derived from BodyMetricEntry history instead of manual
    /// check-ins. Mutually exclusive with the other two links in practice —
    /// UI only ever sets one — but not enforced at the model level, matching
    /// how linkedMeasurementDefinitionID is handled today.
    var linkedBodyMetricDefinitionID: UUID?

    var linkedNutritionMetric: NutritionEngine.Metric? {
        get { linkedNutritionMetricRaw.flatMap { NutritionEngine.Metric(rawValue: $0) } }
        set { linkedNutritionMetricRaw = newValue?.rawValue }
    }

    var role: ResultMeasureRole {
        get { ResultMeasureRole(rawValue: roleRaw) ?? .primary }
        set { roleRaw = newValue.rawValue }
    }

    var valueType: ResultValueType {
        get { ResultValueType(rawValue: valueTypeRaw) ?? .number }
        set { valueTypeRaw = newValue.rawValue }
    }

    var direction: ResultDirection {
        get { ResultDirection(rawValue: directionRaw) ?? .increase }
        set { directionRaw = newValue.rawValue }
    }

    var cadence: ResultCheckInCadence {
        get { ResultCheckInCadence(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }

    var shouldScheduleReminder: Bool {
        isActive && reminderEnabled && cadence != .onDemand &&
            nextCheckInDate != nil && (goal?.isActive ?? true) &&
            (goal?.profile?.isActive ?? true)
    }

    init(
        goal: Goal?, name: String, role: ResultMeasureRole = .primary,
        valueType: ResultValueType = .number, unit: String = "",
        direction: ResultDirection = .increase, baselineValue: Double? = nil,
        targetValue: Double? = nil, targetMinimum: Double? = nil,
        targetMaximum: Double? = nil, ratingLabels: [String] = [],
        cadence: ResultCheckInCadence = .monthly, nextCheckInDate: Date? = nil,
        reminderEnabled: Bool = false, reminderHour: Int = 18, reminderMinute: Int = 0,
        linkedMeasurementDefinitionID: UUID? = nil,
        linkedNutritionMetric: NutritionEngine.Metric? = nil,
        linkedBodyMetricDefinitionID: UUID? = nil
    ) {
        self.id = UUID()
        self.goal = goal
        self.name = name
        self.roleRaw = role.rawValue
        self.valueTypeRaw = valueType.rawValue
        self.unit = unit
        self.directionRaw = direction.rawValue
        self.baselineValue = baselineValue
        self.targetValue = targetValue
        self.targetMinimum = targetMinimum
        self.targetMaximum = targetMaximum
        self.ratingLabels = ratingLabels
        self.cadenceRaw = cadence.rawValue
        self.nextCheckInDate = nextCheckInDate
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.isActive = true
        self.linkedMeasurementDefinitionID = linkedMeasurementDefinitionID
        self.linkedNutritionMetricRaw = linkedNutritionMetric?.rawValue
        self.linkedBodyMetricDefinitionID = linkedBodyMetricDefinitionID
    }
}

enum ResultMeasureValidation {
    static func isValidTarget(
        valueType: ResultValueType,
        direction: ResultDirection,
        baseline: Double?,
        target: Double?,
        minimum: Double?,
        maximum: Double?
    ) -> Bool {
        guard valueType == .number || valueType == .rating else { return true }
        guard let baseline, baseline.isFinite else { return false }

        if valueType == .rating {
            let validRating = { (value: Double) in (1...5).contains(value) }
            guard validRating(baseline) else { return false }
            switch direction {
            case .increase, .decrease:
                guard let target, target.isFinite, validRating(target) else { return false }
            case .targetRange, .maintainRange:
                guard let minimum, let maximum, minimum.isFinite, maximum.isFinite,
                      validRating(minimum), validRating(maximum) else { return false }
            }
        }

        switch direction {
        case .increase:
            guard let target, target.isFinite else { return false }
            return target > baseline
        case .decrease:
            guard let target, target.isFinite else { return false }
            return target < baseline
        case .targetRange, .maintainRange:
            guard let minimum, let maximum, minimum.isFinite, maximum.isFinite else { return false }
            return maximum > minimum
        }
    }

    static func isValidEntry(
        valueType: ResultValueType,
        numericValue: Double?,
        textValue: String
    ) -> Bool {
        switch valueType {
        case .number:
            return numericValue?.isFinite == true
        case .rating:
            guard let numericValue else { return false }
            return numericValue.isFinite && (1...5).contains(numericValue)
        case .milestone:
            return numericValue == 0 || numericValue == 1
        case .text:
            return !textValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// A dated observation supplied by the profile, parent, coach or imported source.
@Model
final class ResultEntry {
    var id: UUID
    var profile: Profile?
    var measure: ResultMeasure?
    var date: Date
    var numericValue: Double?
    var textValue: String
    var sourceLabel: String
    var note: String

    init(
        profile: Profile?, measure: ResultMeasure?, date: Date = .now,
        numericValue: Double? = nil, textValue: String = "",
        sourceLabel: String = "Manual", note: String = ""
    ) {
        self.id = UUID()
        self.profile = profile
        self.measure = measure
        self.date = date
        self.numericValue = numericValue
        self.textValue = textValue
        self.sourceLabel = sourceLabel
        self.note = note
    }
}

// MARK: - Activity (ADR-016: category mandatory, tags optional)

enum ActivitySource: String, Codable, CaseIterable, Identifiable {
    case manual, template, aiSuggestion, imported
    var id: String { rawValue }
}

enum RepeatType: String, Codable, CaseIterable, Identifiable {
    case once = "Once"
    case daily = "Every Day"
    case selectedWeekdays = "Selected Weekdays"
    case timesPerDay = "Multiple Times per Day"
    case timesPerWeek = "Times per Week"
    var id: String { rawValue }
}

@Model
final class Activity {
    var id: UUID
    var profile: Profile?
    var category: AppCategory?
    var name: String
    var sourceRaw: String
    var tags: [String]

    // Tracking definition — optional: some activities (e.g. "Office Work")
    // have no quantitative target and are tracked by completion status only.
    var targetValue: Double?
    var targetUnit: String?

    // Schedule rule (DESIGN.md Section 8) — flattened onto Activity rather
    // than a separate model, matching the Version 1 scope.
    var repeatTypeRaw: String
    var weekdays: [Int]              // Calendar weekday numbers: Sun=1...Sat=7
    var occurrencesPerDay: Int = 1
    var occurrencesPerWeek: Int = 1
    var repeatIntervalMinutes: Int = 60
    var plannedStartMinutes: Int     // minutes since midnight
    var estimatedDurationMinutes: Int
    var startDate: Date
    var endDate: Date?
    var isActive: Bool

    var source: ActivitySource {
        get { ActivitySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
    var repeatType: RepeatType {
        get { RepeatType(rawValue: repeatTypeRaw) ?? .daily }
        set { repeatTypeRaw = newValue.rawValue }
    }

    init(profile: Profile?, category: AppCategory?, name: String, source: ActivitySource = .manual,
         tags: [String] = [], targetValue: Double? = nil, targetUnit: String? = nil,
         repeatType: RepeatType = .daily, weekdays: [Int] = [],
         occurrencesPerDay: Int = 1, occurrencesPerWeek: Int = 1,
         repeatIntervalMinutes: Int = 60, plannedStartMinutes: Int,
         estimatedDurationMinutes: Int, startDate: Date = .now, endDate: Date? = nil) {
        self.id = UUID()
        self.profile = profile
        self.category = category
        self.name = name
        self.sourceRaw = source.rawValue
        self.tags = tags
        self.targetValue = targetValue
        self.targetUnit = targetUnit
        self.repeatTypeRaw = repeatType.rawValue
        self.weekdays = weekdays
        self.occurrencesPerDay = occurrencesPerDay
        self.occurrencesPerWeek = occurrencesPerWeek
        self.repeatIntervalMinutes = repeatIntervalMinutes
        self.plannedStartMinutes = plannedStartMinutes
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = true
    }
}

// MARK: - Calendar Item (ADR-011: always references an Activity)

enum CalendarItemStatus: String, Codable, CaseIterable, Identifiable {
    case planned = "Planned"
    case inProgress = "In Progress"
    case done = "Done"
    case skipped = "Skipped"
    case rescheduled = "Rescheduled"
    case unplanned = "Unplanned"
    var id: String { rawValue }
}

enum CalendarItemSource: String, Codable {
    case schedule, manual
}

@Model
final class CalendarItem {
    var id: UUID
    var profile: Profile?
    var activity: Activity?
    var date: Date               // day this item belongs to (start-of-day)
    var plannedStart: Date?
    var plannedEnd: Date?
    var actualStart: Date?
    var actualEnd: Date?
    var statusRaw: String
    var sourceRaw: String
    var note: String

    var status: CalendarItemStatus {
        get { CalendarItemStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }
    var source: CalendarItemSource {
        get { CalendarItemSource(rawValue: sourceRaw) ?? .schedule }
        set { sourceRaw = newValue.rawValue }
    }

    init(profile: Profile?, activity: Activity?, date: Date, plannedStart: Date? = nil, plannedEnd: Date? = nil,
         status: CalendarItemStatus = .planned, source: CalendarItemSource = .schedule, note: String = "") {
        self.id = UUID()
        self.profile = profile
        self.activity = activity
        self.date = date
        self.plannedStart = plannedStart
        self.plannedEnd = plannedEnd
        self.actualStart = nil
        self.actualEnd = nil
        self.statusRaw = status.rawValue
        self.sourceRaw = source.rawValue
        self.note = note
    }
}

// MARK: - Session (what actually happened)

@Model
final class ActivitySession {
    var id: UUID
    var activity: Activity?
    var calendarItem: CalendarItem?
    var date: Date                   // day this session counts toward, for daily rollups
    var startedAt: Date?
    var endedAt: Date?
    var actualActiveSeconds: Int
    var recordedValue: Double        // the number that counts toward targetValue (Section 10a)
    var note: String

    init(activity: Activity?, calendarItem: CalendarItem?, date: Date = .now, startedAt: Date? = nil,
         endedAt: Date? = nil, actualActiveSeconds: Int = 0, recordedValue: Double = 0, note: String = "") {
        self.id = UUID()
        self.activity = activity
        self.calendarItem = calendarItem
        self.date = date
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.actualActiveSeconds = actualActiveSeconds
        self.recordedValue = recordedValue
        self.note = note
    }
}

// MARK: - Measurement (V2 foundation — Refactor.md Phase 1)
//
// Reusable definition (MeasurementDefinition) vs. actual record
// (MeasurementEntry), per DESIGN.md's Core Domain Rule and
// DOMAIN_MODEL_V2_PROPOSAL.md §2.7/§2.8. Not yet wired into any
// Repository, Engine, or View — Activity.targetValue/targetUnit and
// ActivitySession.recordedValue remain the active, unmodified V1 path.
// These two models are inert additions until a later phase.

enum MeasurementType: String, Codable, CaseIterable, Identifiable {
    case count, duration, distance, percentage, rating, text, custom
    var id: String { rawValue }
}

/// A user-configurable "thing to track" attached to an Activity. One
/// Activity may have several — e.g. Ground Balls, Fly Balls, Catches,
/// Reaction Time, and Throw Accuracy all on one Fielding Practice Activity.
@Model
final class MeasurementDefinition {
    var id: UUID
    var activity: Activity?
    var name: String
    var typeRaw: String
    var unit: String?
    var targetValue: Double?
    var isOptional: Bool
    var sortOrder: Int
    var isActive: Bool

    var type: MeasurementType {
        get { MeasurementType(rawValue: typeRaw) ?? .count }
        set { typeRaw = newValue.rawValue }
    }

    init(activity: Activity?, name: String, type: MeasurementType, unit: String? = nil,
         targetValue: Double? = nil, isOptional: Bool = false, sortOrder: Int = 0, isActive: Bool = true) {
        self.id = UUID()
        self.activity = activity
        self.name = name
        self.typeRaw = type.rawValue
        self.unit = unit
        self.targetValue = targetValue
        self.isOptional = isOptional
        self.sortOrder = sortOrder
        self.isActive = isActive
    }
}

/// The actual recorded value for one MeasurementDefinition within one
/// ActivitySession. `measurementDefinition` is a soft, optional link —
/// `nameSnapshot`/`typeSnapshot`/`unitSnapshot` are copied at creation time
/// so this entry stays fully interpretable even if its MeasurementDefinition
/// is later renamed, retargeted, or deleted. This is what lets historical
/// sessions keep their original measurement meaning even if the Activity
/// changes later (DOMAIN_MODEL_V2_PROPOSAL.md §2.8).
@Model
final class MeasurementEntry {
    var id: UUID
    var activitySession: ActivitySession?
    var measurementDefinition: MeasurementDefinition?
    var nameSnapshot: String
    var typeSnapshot: String
    var unitSnapshot: String
    var numericValue: Double?
    var textValue: String?
    var recordedAt: Date

    init(activitySession: ActivitySession?, measurementDefinition: MeasurementDefinition?,
         nameSnapshot: String, typeSnapshot: MeasurementType, unitSnapshot: String = "",
         numericValue: Double? = nil, textValue: String? = nil, recordedAt: Date = .now) {
        self.id = UUID()
        self.activitySession = activitySession
        self.measurementDefinition = measurementDefinition
        self.nameSnapshot = nameSnapshot
        self.typeSnapshot = typeSnapshot.rawValue
        self.unitSnapshot = unitSnapshot
        self.numericValue = numericValue
        self.textValue = textValue
        self.recordedAt = recordedAt
    }
}

// MARK: - Relationship (V2 foundation — Refactor.md Phase 1)
//
// Data model only, per this phase's scope. Permissions, sharing, and
// notifications are explicitly not implemented here — `permissionsRaw`
// stores the intended grant set as data, but nothing in the codebase reads
// or enforces it yet. Replaces the hardcoded parent/child role eventually
// (DOMAIN_MODEL_V2_PROPOSAL.md §2.2); Profile.kind/managementMode are
// unmodified and still govern all existing behavior.

enum RelationshipStatus: String, Codable, CaseIterable, Identifiable {
    case pending, active, revoked
    var id: String { rawValue }
}

@Model
final class Relationship {
    var id: UUID
    var subjectProfileID: UUID
    var actorProfileID: UUID
    var relationshipType: String
    var permissionsRaw: [String]
    var statusRaw: String
    var createdAt: Date
    var respondedAt: Date?

    var status: RelationshipStatus {
        get { RelationshipStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(subjectProfileID: UUID, actorProfileID: UUID, relationshipType: String,
         permissionsRaw: [String] = [], status: RelationshipStatus = .pending,
         createdAt: Date = .now, respondedAt: Date? = nil) {
        self.id = UUID()
        self.subjectProfileID = subjectProfileID
        self.actorProfileID = actorProfileID
        self.relationshipType = relationshipType
        self.permissionsRaw = permissionsRaw
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.respondedAt = respondedAt
    }
}

// MARK: - Nutrition

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snack = "Snack"
    case drink = "Drink"

    var id: String { rawValue }
}

@Model
final class FoodEntry {
    static let mealPlanSource = "Meal Plan"
    var id: UUID
    var profile: Profile?
    var date: Date
    var mealTypeRaw: String
    var name: String
    var calories: Double
    var proteinGrams: Double
    var carbohydrateGrams: Double
    var fatGrams: Double
    var waterMilliliters: Double
    var note: String
    var barcode: String?
    var nutritionSource: String
    @Attribute(.externalStorage) var photoData: Data?
    var servings: Double = 1

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    /// Weekly meal plans reuse the nutrition record shape but remain excluded
    /// from actual intake totals. A planned meal becomes evidence only when a
    /// separate actual FoodEntry is logged.
    var isMealPlanItem: Bool { nutritionSource == Self.mealPlanSource }

    init(profile: Profile?, date: Date = .now, mealType: MealType, name: String,
         calories: Double = 0, proteinGrams: Double = 0, carbohydrateGrams: Double = 0,
         fatGrams: Double = 0, waterMilliliters: Double = 0, note: String = "",
         barcode: String? = nil, nutritionSource: String = "Manual", photoData: Data? = nil,
         servings: Double = 1) {
        self.id = UUID()
        self.profile = profile
        self.date = date
        self.mealTypeRaw = mealType.rawValue
        self.name = name
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.fatGrams = fatGrams
        self.waterMilliliters = waterMilliliters
        self.note = note
        self.barcode = barcode
        self.nutritionSource = nutritionSource
        self.photoData = photoData
        self.servings = servings
    }
}

// MARK: - Body measurements

@Model
final class WeightEntry {
    var id: UUID
    var profile: Profile?
    var date: Date
    var kilograms: Double
    var note: String

    init(profile: Profile?, date: Date = .now, kilograms: Double, note: String = "") {
        self.id = UUID()
        self.profile = profile
        self.date = date
        self.kilograms = kilograms
        self.note = note
    }
}

// MARK: - Sport training

@Model
final class SportEntry {
    var id: UUID
    var profile: Profile?
    var category: AppCategory?
    var date: Date
    var sessionName: String
    var repetitions: Int
    var durationMinutes: Int
    var note: String
    var perceivedEffort: Int
    var soreness: Int

    init(profile: Profile?, category: AppCategory, date: Date = .now,
         sessionName: String, repetitions: Int = 0, durationMinutes: Int = 0,
         note: String = "", perceivedEffort: Int = 5, soreness: Int = 0) {
        self.id = UUID()
        self.profile = profile
        self.category = category
        self.date = date
        self.sessionName = sessionName
        self.repetitions = repetitions
        self.durationMinutes = durationMinutes
        self.note = note
        self.perceivedEffort = perceivedEffort
        self.soreness = soreness
    }
}

extension Calendar {
    func isSameDay(_ date: Date, as reference: Date) -> Bool {
        isDate(date, inSameDayAs: reference)
    }
}
