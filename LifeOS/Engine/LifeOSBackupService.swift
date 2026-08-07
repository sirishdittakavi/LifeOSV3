import Foundation
import SwiftData

struct LifeOSBackupPayload: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let profiles: [ProfileBackup]
    let categories: [CategoryBackup]
    let activities: [ActivityBackup]
    let calendarItems: [CalendarItemBackup]
    let sessions: [SessionBackup]
    let foodEntries: [FoodBackup]
    let weightEntries: [WeightBackup]
    let sportEntries: [SportBackup]
    let savedTemplates: [SavedTemplateBackup]
}

struct ProfileBackup: Codable {
    let id: UUID; let name: String; let kindRaw: String; let colorToken: String; let weightUnitRaw: String
    let avatarData: Data?; let managementModeRaw: String?
    let weightGoalKilograms: Double?; let calorieGoal: Double; let proteinGoalGrams: Double
    let carbohydrateGoalGrams: Double; let fatGoalGrams: Double; let waterGoalMilliliters: Double
    let isActive: Bool
}

struct CategoryBackup: Codable {
    let id: UUID; let profileID: UUID?; let name: String; let symbol: String; let colorToken: String
    let pillarRaw: String; let purpose: String; let weeklyTargetSessions: Int; let weeklyTargetMinutes: Int
    let parentCategoryIDString: String?; let relatedCategoryIDStrings: [String]
    let reminderEnabled: Bool; let reminderHour: Int; let reminderMinute: Int; let isActive: Bool
}

struct ActivityBackup: Codable {
    let id: UUID; let profileID: UUID?; let categoryID: UUID?; let name: String; let sourceRaw: String
    let tags: [String]; let targetValue: Double?; let targetUnit: String?; let repeatTypeRaw: String
    let weekdays: [Int]; let occurrencesPerDay: Int; let occurrencesPerWeek: Int
    let repeatIntervalMinutes: Int; let plannedStartMinutes: Int; let estimatedDurationMinutes: Int
    let startDate: Date; let endDate: Date?; let isActive: Bool
}

struct CalendarItemBackup: Codable {
    let id: UUID; let profileID: UUID?; let activityID: UUID?; let date: Date
    let plannedStart: Date?; let plannedEnd: Date?; let actualStart: Date?; let actualEnd: Date?
    let statusRaw: String; let sourceRaw: String; let note: String
}

struct SessionBackup: Codable {
    let id: UUID; let activityID: UUID?; let calendarItemID: UUID?; let date: Date
    let startedAt: Date?; let endedAt: Date?; let actualActiveSeconds: Int
    let recordedValue: Double; let note: String
}

struct FoodBackup: Codable {
    let id: UUID; let profileID: UUID?; let date: Date; let mealTypeRaw: String; let name: String
    let calories: Double; let proteinGrams: Double; let carbohydrateGrams: Double; let fatGrams: Double
    let waterMilliliters: Double; let note: String; let barcode: String?; let nutritionSource: String
    let photoData: Data?; let servings: Double
}

struct WeightBackup: Codable {
    let id: UUID; let profileID: UUID?; let date: Date; let kilograms: Double; let note: String
}

struct SportBackup: Codable {
    let id: UUID; let profileID: UUID?; let categoryID: UUID?; let date: Date
    let sessionName: String; let repetitions: Int; let durationMinutes: Int
    let note: String; let perceivedEffort: Int; let soreness: Int
}

struct SavedTemplateBackup: Codable {
    let id: UUID; let name: String; let pillarRaw: String; let symbol: String; let colorToken: String
    let purpose: String; let weeklySessions: Int; let weeklyMinutes: Int
    let taskBlueprintData: Data; let createdAt: Date
}

enum LifeOSBackupService {
    static func make(
        profiles: [Profile], categories: [AppCategory], activities: [Activity],
        calendarItems: [CalendarItem], sessions: [ActivitySession], foodEntries: [FoodEntry],
        weightEntries: [WeightEntry], sportEntries: [SportEntry],
        savedTemplates: [SavedCategoryTemplate]
    ) -> LifeOSBackupPayload {
        LifeOSBackupPayload(
            schemaVersion: 1, exportedAt: .now,
            profiles: profiles.map {
                ProfileBackup(id: $0.id, name: $0.name, kindRaw: $0.kindRaw, colorToken: $0.colorToken,
                    weightUnitRaw: $0.weightUnitRaw, avatarData: $0.avatarData,
                    managementModeRaw: $0.managementModeRaw,
                    weightGoalKilograms: $0.weightGoalKilograms,
                    calorieGoal: $0.calorieGoal, proteinGoalGrams: $0.proteinGoalGrams,
                    carbohydrateGoalGrams: $0.carbohydrateGoalGrams, fatGoalGrams: $0.fatGoalGrams,
                    waterGoalMilliliters: $0.waterGoalMilliliters,
                    isActive: $0.isActive)
            },
            categories: categories.map {
                CategoryBackup(id: $0.id, profileID: $0.profile?.id, name: $0.name, symbol: $0.symbol,
                    colorToken: $0.colorToken, pillarRaw: $0.pillarRaw, purpose: $0.purpose,
                    weeklyTargetSessions: $0.weeklyTargetSessions, weeklyTargetMinutes: $0.weeklyTargetMinutes,
                    parentCategoryIDString: $0.parentCategoryIDString,
                    relatedCategoryIDStrings: $0.relatedCategoryIDStrings,
                    reminderEnabled: $0.reminderEnabled, reminderHour: $0.reminderHour,
                    reminderMinute: $0.reminderMinute, isActive: $0.isActive)
            },
            activities: activities.map {
                ActivityBackup(id: $0.id, profileID: $0.profile?.id, categoryID: $0.category?.id,
                    name: $0.name, sourceRaw: $0.sourceRaw, tags: $0.tags, targetValue: $0.targetValue,
                    targetUnit: $0.targetUnit, repeatTypeRaw: $0.repeatTypeRaw, weekdays: $0.weekdays,
                    occurrencesPerDay: $0.occurrencesPerDay, occurrencesPerWeek: $0.occurrencesPerWeek,
                    repeatIntervalMinutes: $0.repeatIntervalMinutes, plannedStartMinutes: $0.plannedStartMinutes,
                    estimatedDurationMinutes: $0.estimatedDurationMinutes, startDate: $0.startDate,
                    endDate: $0.endDate, isActive: $0.isActive)
            },
            calendarItems: calendarItems.map {
                CalendarItemBackup(id: $0.id, profileID: $0.profile?.id, activityID: $0.activity?.id,
                    date: $0.date, plannedStart: $0.plannedStart, plannedEnd: $0.plannedEnd,
                    actualStart: $0.actualStart, actualEnd: $0.actualEnd, statusRaw: $0.statusRaw,
                    sourceRaw: $0.sourceRaw, note: $0.note)
            },
            sessions: sessions.map {
                SessionBackup(id: $0.id, activityID: $0.activity?.id, calendarItemID: $0.calendarItem?.id,
                    date: $0.date, startedAt: $0.startedAt, endedAt: $0.endedAt,
                    actualActiveSeconds: $0.actualActiveSeconds, recordedValue: $0.recordedValue, note: $0.note)
            },
            foodEntries: foodEntries.map {
                FoodBackup(id: $0.id, profileID: $0.profile?.id, date: $0.date,
                    mealTypeRaw: $0.mealTypeRaw, name: $0.name, calories: $0.calories,
                    proteinGrams: $0.proteinGrams, carbohydrateGrams: $0.carbohydrateGrams,
                    fatGrams: $0.fatGrams, waterMilliliters: $0.waterMilliliters, note: $0.note,
                    barcode: $0.barcode, nutritionSource: $0.nutritionSource,
                    photoData: $0.photoData, servings: $0.servings)
            },
            weightEntries: weightEntries.map {
                WeightBackup(id: $0.id, profileID: $0.profile?.id, date: $0.date,
                    kilograms: $0.kilograms, note: $0.note)
            },
            sportEntries: sportEntries.map {
                SportBackup(id: $0.id, profileID: $0.profile?.id, categoryID: $0.category?.id,
                    date: $0.date, sessionName: $0.sessionName, repetitions: $0.repetitions,
                    durationMinutes: $0.durationMinutes, note: $0.note,
                    perceivedEffort: $0.perceivedEffort, soreness: $0.soreness)
            },
            savedTemplates: savedTemplates.map {
                SavedTemplateBackup(id: $0.id, name: $0.name, pillarRaw: $0.pillarRaw,
                    symbol: $0.symbol, colorToken: $0.colorToken, purpose: $0.purpose,
                    weeklySessions: $0.weeklySessions, weeklyMinutes: $0.weeklyMinutes,
                    taskBlueprintData: $0.taskBlueprintData, createdAt: $0.createdAt)
            }
        )
    }

    static func restore(_ backup: LifeOSBackupPayload, into context: ModelContext) throws {
        guard backup.schemaVersion == 1 else { throw BackupError.unsupportedVersion }

        var profileMap = Dictionary(uniqueKeysWithValues:
            (try context.fetch(FetchDescriptor<Profile>())).map { ($0.id, $0) })
        for record in backup.profiles {
            let item = profileMap[record.id] ?? Profile(name: record.name,
                kind: ProfileKind(rawValue: record.kindRaw) ?? .individual, colorToken: record.colorToken)
            item.id = record.id; item.name = record.name; item.kindRaw = record.kindRaw
            item.colorToken = record.colorToken; item.weightUnitRaw = record.weightUnitRaw
            item.avatarData = record.avatarData
            if let managementModeRaw = record.managementModeRaw {
                item.managementModeRaw = managementModeRaw
            }
            item.weightGoalKilograms = record.weightGoalKilograms; item.calorieGoal = record.calorieGoal
            item.proteinGoalGrams = record.proteinGoalGrams; item.carbohydrateGoalGrams = record.carbohydrateGoalGrams
            item.fatGoalGrams = record.fatGoalGrams; item.waterGoalMilliliters = record.waterGoalMilliliters
            item.isActive = record.isActive
            if profileMap[record.id] == nil { context.insert(item); profileMap[record.id] = item }
        }

        var categoryMap = Dictionary(uniqueKeysWithValues:
            (try context.fetch(FetchDescriptor<AppCategory>())).map { ($0.id, $0) })
        for record in backup.categories {
            let item = categoryMap[record.id] ?? AppCategory(
                profile: record.profileID.flatMap { profileMap[$0] }, name: record.name,
                symbol: record.symbol, colorToken: record.colorToken)
            item.id = record.id; item.profile = record.profileID.flatMap { profileMap[$0] }
            item.name = record.name; item.symbol = record.symbol; item.colorToken = record.colorToken
            item.pillarRaw = record.pillarRaw; item.purpose = record.purpose
            item.weeklyTargetSessions = record.weeklyTargetSessions; item.weeklyTargetMinutes = record.weeklyTargetMinutes
            item.parentCategoryIDString = record.parentCategoryIDString
            item.relatedCategoryIDStrings = record.relatedCategoryIDStrings
            item.reminderEnabled = record.reminderEnabled; item.reminderHour = record.reminderHour
            item.reminderMinute = record.reminderMinute; item.isActive = record.isActive
            if categoryMap[record.id] == nil { context.insert(item); categoryMap[record.id] = item }
        }

        var activityMap = Dictionary(uniqueKeysWithValues:
            (try context.fetch(FetchDescriptor<Activity>())).map { ($0.id, $0) })
        for record in backup.activities {
            let item = activityMap[record.id] ?? Activity(
                profile: record.profileID.flatMap { profileMap[$0] },
                category: record.categoryID.flatMap { categoryMap[$0] }, name: record.name,
                plannedStartMinutes: record.plannedStartMinutes,
                estimatedDurationMinutes: record.estimatedDurationMinutes)
            item.id = record.id; item.profile = record.profileID.flatMap { profileMap[$0] }
            item.category = record.categoryID.flatMap { categoryMap[$0] }; item.name = record.name
            item.sourceRaw = record.sourceRaw; item.tags = record.tags; item.targetValue = record.targetValue
            item.targetUnit = record.targetUnit; item.repeatTypeRaw = record.repeatTypeRaw; item.weekdays = record.weekdays
            item.occurrencesPerDay = record.occurrencesPerDay; item.occurrencesPerWeek = record.occurrencesPerWeek
            item.repeatIntervalMinutes = record.repeatIntervalMinutes; item.plannedStartMinutes = record.plannedStartMinutes
            item.estimatedDurationMinutes = record.estimatedDurationMinutes; item.startDate = record.startDate
            item.endDate = record.endDate; item.isActive = record.isActive
            if activityMap[record.id] == nil { context.insert(item); activityMap[record.id] = item }
        }

        var calendarMap = Dictionary(uniqueKeysWithValues:
            (try context.fetch(FetchDescriptor<CalendarItem>())).map { ($0.id, $0) })
        for record in backup.calendarItems {
            let item = calendarMap[record.id] ?? CalendarItem(
                profile: record.profileID.flatMap { profileMap[$0] },
                activity: record.activityID.flatMap { activityMap[$0] }, date: record.date)
            item.id = record.id; item.profile = record.profileID.flatMap { profileMap[$0] }
            item.activity = record.activityID.flatMap { activityMap[$0] }; item.date = record.date
            item.plannedStart = record.plannedStart; item.plannedEnd = record.plannedEnd
            item.actualStart = record.actualStart; item.actualEnd = record.actualEnd
            item.statusRaw = record.statusRaw; item.sourceRaw = record.sourceRaw; item.note = record.note
            if calendarMap[record.id] == nil { context.insert(item); calendarMap[record.id] = item }
        }

        var sessionIDs = Set((try context.fetch(FetchDescriptor<ActivitySession>())).map(\.id))
        for record in backup.sessions where !sessionIDs.contains(record.id) {
            let item = ActivitySession(activity: record.activityID.flatMap { activityMap[$0] },
                calendarItem: record.calendarItemID.flatMap { calendarMap[$0] }, date: record.date,
                startedAt: record.startedAt, endedAt: record.endedAt,
                actualActiveSeconds: record.actualActiveSeconds, recordedValue: record.recordedValue, note: record.note)
            item.id = record.id; context.insert(item); sessionIDs.insert(record.id)
        }

        var foodIDs = Set((try context.fetch(FetchDescriptor<FoodEntry>())).map(\.id))
        for record in backup.foodEntries where !foodIDs.contains(record.id) {
            let item = FoodEntry(profile: record.profileID.flatMap { profileMap[$0] }, date: record.date,
                mealType: MealType(rawValue: record.mealTypeRaw) ?? .snack, name: record.name,
                calories: record.calories, proteinGrams: record.proteinGrams,
                carbohydrateGrams: record.carbohydrateGrams, fatGrams: record.fatGrams,
                waterMilliliters: record.waterMilliliters, note: record.note, barcode: record.barcode,
                nutritionSource: record.nutritionSource, photoData: record.photoData, servings: record.servings)
            item.id = record.id; context.insert(item); foodIDs.insert(record.id)
        }

        var weightIDs = Set((try context.fetch(FetchDescriptor<WeightEntry>())).map(\.id))
        for record in backup.weightEntries where !weightIDs.contains(record.id) {
            let item = WeightEntry(profile: record.profileID.flatMap { profileMap[$0] },
                date: record.date, kilograms: record.kilograms, note: record.note)
            item.id = record.id; context.insert(item); weightIDs.insert(record.id)
        }

        var sportIDs = Set((try context.fetch(FetchDescriptor<SportEntry>())).map(\.id))
        for record in backup.sportEntries where !sportIDs.contains(record.id) {
            guard let category = record.categoryID.flatMap({ categoryMap[$0] }) else { continue }
            let item = SportEntry(profile: record.profileID.flatMap { profileMap[$0] },
                category: category, date: record.date, sessionName: record.sessionName,
                repetitions: record.repetitions, durationMinutes: record.durationMinutes,
                note: record.note, perceivedEffort: record.perceivedEffort,
                soreness: record.soreness)
            item.id = record.id
            context.insert(item); sportIDs.insert(record.id)
        }

        var templateIDs = Set((try context.fetch(FetchDescriptor<SavedCategoryTemplate>())).map(\.id))
        for record in backup.savedTemplates where !templateIDs.contains(record.id) {
            let placeholder = AppCategory(name: record.name, symbol: record.symbol, colorToken: record.colorToken)
            let item = SavedCategoryTemplate(category: placeholder, activities: [])
            item.id = record.id; item.name = record.name; item.pillarRaw = record.pillarRaw
            item.symbol = record.symbol; item.colorToken = record.colorToken; item.purpose = record.purpose
            item.weeklySessions = record.weeklySessions; item.weeklyMinutes = record.weeklyMinutes
            item.taskBlueprintData = record.taskBlueprintData; item.createdAt = record.createdAt
            context.insert(item); templateIDs.insert(record.id)
        }
        try context.save()
    }
}

enum BackupError: LocalizedError {
    case unsupportedVersion
    var errorDescription: String? { "This backup version is not supported by this version of LifeOS." }
}
