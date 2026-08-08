import Foundation

struct ImprovementTaskTemplate: Identifiable {
    let id = UUID()
    let name: String
    let repeatType: RepeatType
    let weekdays: [Int]
    let startMinutes: Int
    let durationMinutes: Int
    let targetValue: Double?
    let targetUnit: String?

    let occurrencesPerDay: Int
    let occurrencesPerWeek: Int
    let repeatIntervalMinutes: Int

    init(
        name: String, repeatType: RepeatType, weekdays: [Int],
        startMinutes: Int, durationMinutes: Int,
        targetValue: Double?, targetUnit: String?,
        occurrencesPerDay: Int = 1, occurrencesPerWeek: Int = 1,
        repeatIntervalMinutes: Int = 60
    ) {
        self.name = name
        self.repeatType = repeatType
        self.weekdays = weekdays
        self.startMinutes = startMinutes
        self.durationMinutes = durationMinutes
        self.targetValue = targetValue
        self.targetUnit = targetUnit
        self.occurrencesPerDay = occurrencesPerDay
        self.occurrencesPerWeek = occurrencesPerWeek
        self.repeatIntervalMinutes = repeatIntervalMinutes
    }
}

struct ImprovementCategoryTemplate: Identifiable {
    let id: String
    let name: String
    let pillar: ImprovementPillar
    let trackingKind: AreaTrackingKind
    let symbol: String
    let colorToken: String
    let purpose: String
    let weeklySessions: Int
    let weeklyMinutes: Int
    let relatedNames: [String]
    let tasks: [ImprovementTaskTemplate]
}

struct GoalStarterTemplate: Identifiable {
    let id: String
    let name: String
    let purpose: String
    let symbol: String
    let colorToken: String
    let measureName: String
    let valueType: ResultValueType
    let unit: String
    let direction: ResultDirection
    let baseline: Double?
    let target: Double?
    let targetMinimum: Double?
    let targetMaximum: Double?
    let cadence: ResultCheckInCadence
    let suggestedAreaNames: [String]
    let needsPersonalValues: Bool
}

enum GoalStarterTemplates {
    static let all: [GoalStarterTemplate] = [
        GoalStarterTemplate(
            id: "school-result", name: "Improve a School Result",
            purpose: "Connect regular study with objective assessment results.",
            symbol: "graduationcap.fill", colorToken: "indigo",
            measureName: "Mock-test or exam score", valueType: .number,
            unit: "%", direction: .increase, baseline: 60, target: 75,
            targetMinimum: nil, targetMaximum: nil, cadence: .monthly,
            suggestedAreaNames: ["School", "Learning", "Education"],
            needsPersonalValues: false
        ),
        GoalStarterTemplate(
            id: "sport-performance", name: "Improve Sport Performance",
            purpose: "Compare consistent training with a repeatable performance assessment.",
            symbol: "figure.run", colorToken: "orange",
            measureName: "Coach or performance assessment", valueType: .rating,
            unit: "", direction: .increase, baseline: 3, target: 4,
            targetMinimum: nil, targetMaximum: nil, cadence: .monthly,
            suggestedAreaNames: ["Sport", "Baseball", "Cricket", "Training", "Mobility", "Strength"],
            needsPersonalValues: false
        ),
        GoalStarterTemplate(
            id: "energy-recovery", name: "Improve Energy and Recovery",
            purpose: "Compare nutrition and recovery habits with a consistent readiness rating.",
            symbol: "heart.text.square.fill", colorToken: "green",
            measureName: "Energy and readiness rating", valueType: .rating,
            unit: "", direction: .increase, baseline: 3, target: 4,
            targetMinimum: nil, targetMaximum: nil, cadence: .weekly,
            suggestedAreaNames: ["Nutrition", "Recovery", "Movement", "Health"],
            needsPersonalValues: false
        ),
        GoalStarterTemplate(
            id: "weight-range", name: "Reach a Personal Weight Range",
            purpose: "Follow the longer-term body-weight trend alongside nutrition, movement and recovery.",
            symbol: "scalemass.fill", colorToken: "blue",
            measureName: "Body weight", valueType: .number,
            unit: "kg", direction: .targetRange, baseline: nil, target: nil,
            targetMinimum: nil, targetMaximum: nil, cadence: .monthly,
            suggestedAreaNames: ["Nutrition", "Weight", "Movement", "Strength", "Recovery"],
            needsPersonalValues: true
        ),
        GoalStarterTemplate(
            id: "project", name: "Complete a Meaningful Project",
            purpose: "Use focused actions to reach a clear, verifiable milestone.",
            symbol: "flag.checkered", colorToken: "purple",
            measureName: "Project milestone", valueType: .milestone,
            unit: "", direction: .increase, baseline: nil, target: nil,
            targetMinimum: nil, targetMaximum: nil, cadence: .onDemand,
            suggestedAreaNames: ["Learning", "Software", "Career", "School"],
            needsPersonalValues: false
        )
    ]
}

enum ImprovementTemplates {
    static let all: [ImprovementCategoryTemplate] = [
        ImprovementCategoryTemplate(
            id: "baseball", name: "Baseball", pillar: .sport, trackingKind: .sport,
            symbol: "figure.baseball", colorToken: "orange",
            purpose: "Improve baseball skill through planned practice, athlete feedback and recovery.",
            weeklySessions: 5, weeklyMinutes: 240,
            relatedNames: ["Mobility", "Speed", "Strength", "Nutrition", "Recovery"],
            tasks: [
                task("Hitting Practice", .selectedWeekdays, [2, 3, 5], 18 * 60, 60, 100, "swings"),
                task("Throwing Practice", .selectedWeekdays, [4, 7], 18 * 60, 45, 60, "throws")
            ]
        ),
        ImprovementCategoryTemplate(
            id: "software", name: "Software Development", pillar: .learning, trackingKind: .tasks,
            symbol: "chevron.left.forwardslash.chevron.right", colorToken: "purple",
            purpose: "Improve engineering ability through deliberate practice and shipped work.",
            weeklySessions: 5, weeklyMinutes: 225,
            relatedNames: ["Career", "Learning"],
            tasks: [
                task("Coding Practice", .selectedWeekdays, [2, 3, 4, 5, 6], 20 * 60, 45, 45, "min"),
                task("Weekly Project Milestone", .selectedWeekdays, [7], 10 * 60, 90, nil, nil)
            ]
        ),
        ImprovementCategoryTemplate(
            id: "school", name: "School", pillar: .learning, trackingKind: .tasks,
            symbol: "book.fill", colorToken: "indigo",
            purpose: "Build a sustainable study plan and compare it with assessment results.",
            weeklySessions: 5, weeklyMinutes: 225,
            relatedNames: ["Learning", "Recovery"],
            tasks: [
                task("Homework or Study", .selectedWeekdays, [2, 3, 4, 5, 6], 17 * 60, 45, 45, "min"),
                task("Weekly Review", .selectedWeekdays, [1], 17 * 60, 30, nil, nil)
            ]
        ),
        ImprovementCategoryTemplate(
            id: "mobility", name: "Mobility", pillar: .physical, trackingKind: .tasks,
            symbol: "figure.flexibility", colorToken: "teal",
            purpose: "Build usable range of motion and movement quality.",
            weeklySessions: 5, weeklyMinutes: 75,
            relatedNames: ["Baseball", "Speed", "Strength", "Recovery"],
            tasks: [task("Mobility Routine", .selectedWeekdays, [2, 3, 4, 5, 6], 7 * 60 + 30, 15, 15, "min")]
        ),
        ImprovementCategoryTemplate(
            id: "speed", name: "Speed", pillar: .physical, trackingKind: .tasks,
            symbol: "figure.run", colorToken: "blue",
            purpose: "Improve acceleration and running mechanics progressively.",
            weeklySessions: 3, weeklyMinutes: 90,
            relatedNames: ["Baseball", "Mobility", "Strength", "Recovery"],
            tasks: [task("Sprint Technique", .selectedWeekdays, [2, 4, 6], 16 * 60 + 30, 30, 30, "min")]
        ),
        ImprovementCategoryTemplate(
            id: "strength", name: "Strength", pillar: .physical, trackingKind: .tasks,
            symbol: "dumbbell.fill", colorToken: "red",
            purpose: "Develop strength with progressive, coach-appropriate training.",
            weeklySessions: 3, weeklyMinutes: 150,
            relatedNames: ["Baseball", "Speed", "Mobility", "Recovery"],
            tasks: [task("Strength Session", .selectedWeekdays, [2, 4, 6], 17 * 60, 50, 50, "min")]
        ),
        ImprovementCategoryTemplate(
            id: "nutrition", name: "Nutrition", pillar: .nutrition, trackingKind: .nutrition,
            symbol: "fork.knife", colorToken: "green",
            purpose: "Fuel health, growth and performance against user-approved targets.",
            weeklySessions: 7, weeklyMinutes: 0,
            relatedNames: ["Weight Improvement", "Body Development", "Baseball", "Recovery"],
            tasks: [
                task("Plan and Log Meals", .daily, [], 18 * 60, 10, nil, nil),
                ImprovementTaskTemplate(
                    name: "Hydration Check", repeatType: .timesPerDay, weekdays: [],
                    startMinutes: 8 * 60, durationMinutes: 2,
                    targetValue: nil, targetUnit: nil,
                    occurrencesPerDay: 4, repeatIntervalMinutes: 180
                )
            ]
        ),
        ImprovementCategoryTemplate(
            id: "weight", name: "Weight Improvement", pillar: .physical, trackingKind: .bodyWeight,
            symbol: "scalemass.fill", colorToken: "blue",
            purpose: "Track body trend without reacting to daily fluctuations.",
            weeklySessions: 3, weeklyMinutes: 0,
            relatedNames: ["Nutrition", "Strength", "Recovery"],
            tasks: [
                task("Weekly Weigh-in", .selectedWeekdays, [2], 7 * 60, 5, nil, nil)
            ]
        ),
        ImprovementCategoryTemplate(
            id: "recovery", name: "Recovery", pillar: .physical, trackingKind: .tasks,
            symbol: "bed.double.fill", colorToken: "indigo",
            purpose: "Protect adaptation with sleep, light movement and honest soreness feedback.",
            weeklySessions: 7, weeklyMinutes: 70,
            relatedNames: ["Baseball", "Mobility", "Strength", "Speed"],
            tasks: [task("Recovery Check-in", .daily, [], 20 * 60 + 30, 10, 10, "min")]
        )
    ]

    private static func task(
        _ name: String, _ repeatType: RepeatType, _ weekdays: [Int],
        _ startMinutes: Int, _ durationMinutes: Int,
        _ targetValue: Double?, _ targetUnit: String?
    ) -> ImprovementTaskTemplate {
        ImprovementTaskTemplate(
            name: name, repeatType: repeatType, weekdays: weekdays,
            startMinutes: startMinutes, durationMinutes: durationMinutes,
            targetValue: targetValue, targetUnit: targetUnit
        )
    }
}

extension SavedCategoryTemplate {
    var improvementTemplate: ImprovementCategoryTemplate {
        ImprovementCategoryTemplate(
            id: "saved-\(id.uuidString)",
            name: name,
            pillar: pillar,
            trackingKind: trackingKind,
            symbol: symbol,
            colorToken: colorToken,
            purpose: purpose,
            weeklySessions: weeklySessions,
            weeklyMinutes: weeklyMinutes,
            relatedNames: [],
            tasks: taskBlueprints.map { blueprint in
                ImprovementTaskTemplate(
                    name: blueprint.name,
                    repeatType: RepeatType(rawValue: blueprint.repeatTypeRaw) ?? .daily,
                    weekdays: blueprint.weekdays,
                    startMinutes: blueprint.startMinutes,
                    durationMinutes: blueprint.durationMinutes,
                    targetValue: blueprint.targetValue,
                    targetUnit: blueprint.targetUnit,
                    occurrencesPerDay: blueprint.occurrencesPerDay,
                    occurrencesPerWeek: blueprint.occurrencesPerWeek,
                    repeatIntervalMinutes: blueprint.repeatIntervalMinutes
                )
            }
        )
    }
}
