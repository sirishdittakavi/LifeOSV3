import Foundation

/// A data-driven measurement to attach to an ImprovementTaskTemplate's
/// created Activity — Refactor.md Run 4. Deliberately just data (name/type/
/// unit/target); nothing here is specific to any sport, instrument, or
/// domain. Turned into a real MeasurementDefinition only when the template
/// is applied (AddImprovementCategoryView.create()), alongside the
/// existing single targetValue/targetUnit, not instead of it.
struct MeasurementBlueprint {
    let name: String
    let type: MeasurementType
    let unit: String?
    let targetValue: Double?

    init(name: String, type: MeasurementType, unit: String? = nil, targetValue: Double? = nil) {
        self.name = name
        self.type = type
        self.unit = unit
        self.targetValue = targetValue
    }
}

struct ImprovementTaskTemplate: Identifiable {
    let id = UUID()
    let name: String
    let repeatType: RepeatType
    let weekdays: [Int]
    let startMinutes: Int
    let durationMinutes: Int
    let targetValue: Double?
    let targetUnit: String?
    let measurements: [MeasurementBlueprint]

    let occurrencesPerDay: Int
    let occurrencesPerWeek: Int
    let repeatIntervalMinutes: Int

    init(
        name: String, repeatType: RepeatType, weekdays: [Int],
        startMinutes: Int, durationMinutes: Int,
        targetValue: Double?, targetUnit: String?,
        measurements: [MeasurementBlueprint] = [],
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
        self.measurements = measurements
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
    /// The id of another ImprovementCategoryTemplate this one nests inside
    /// when applied — e.g. a "Baseball" discipline template under a
    /// "Sports" category template. Data-driven: any template may declare
    /// any other template's id here; nothing in the type system hardcodes
    /// which categories have disciplines or what they're called. Nil means
    /// top-level, exactly like an AppCategory with no parentCategoryID.
    let parentTemplateID: String?

    init(
        id: String, name: String, pillar: ImprovementPillar, trackingKind: AreaTrackingKind,
        symbol: String, colorToken: String, purpose: String,
        weeklySessions: Int, weeklyMinutes: Int, relatedNames: [String],
        tasks: [ImprovementTaskTemplate], parentTemplateID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.pillar = pillar
        self.trackingKind = trackingKind
        self.symbol = symbol
        self.colorToken = colorToken
        self.purpose = purpose
        self.weeklySessions = weeklySessions
        self.weeklyMinutes = weeklyMinutes
        self.relatedNames = relatedNames
        self.tasks = tasks
        self.parentTemplateID = parentTemplateID
    }
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
        ),

        // MARK: - Category -> Discipline -> Activity Template -> Measurements
        // (Refactor.md Run 4). These are illustrative data entries, not new
        // Swift types — "Sports" and "Music" are plain top-level
        // ImprovementCategoryTemplate rows exactly like every entry above;
        // "Baseball" and "Guitar" are ordinary entries that happen to set
        // parentTemplateID. Any user-created Area could do the same via the
        // existing "Inside" picker (AddImprovementCategoryView) — this only
        // demonstrates it as a starter template.

        ImprovementCategoryTemplate(
            id: "sports", name: "Sports", pillar: .sport, trackingKind: .tasks,
            symbol: "sportscourt.fill", colorToken: "orange",
            purpose: "A home for every sport or discipline you train.",
            weeklySessions: 0, weeklyMinutes: 0,
            relatedNames: [], tasks: []
        ),
        ImprovementCategoryTemplate(
            id: "baseball-discipline", name: "Baseball", pillar: .sport, trackingKind: .sport,
            symbol: "figure.baseball", colorToken: "orange",
            purpose: "Improve baseball skill through planned practice, athlete feedback and recovery.",
            weeklySessions: 5, weeklyMinutes: 240,
            relatedNames: ["Mobility", "Speed", "Strength", "Nutrition", "Recovery"],
            tasks: [
                task("Hitting Practice", .selectedWeekdays, [2, 3, 5], 18 * 60, 60, 100, "swings"),
                task("Throwing Practice", .selectedWeekdays, [4, 7], 18 * 60, 45, 60, "throws"),
                measuredTask(
                    "Fielding Practice", .selectedWeekdays, [2, 4, 6], 17 * 60, 30,
                    measurements: [
                        MeasurementBlueprint(name: "Ground Balls", type: .count, unit: "reps", targetValue: 100),
                        MeasurementBlueprint(name: "Catches", type: .count, unit: "reps", targetValue: 50),
                        MeasurementBlueprint(name: "Throws", type: .count, unit: "reps", targetValue: 30)
                    ]
                )
            ],
            parentTemplateID: "sports"
        ),

        ImprovementCategoryTemplate(
            id: "music", name: "Music", pillar: .learning, trackingKind: .tasks,
            symbol: "music.note", colorToken: "purple",
            purpose: "A home for every instrument or musical discipline you practice.",
            weeklySessions: 0, weeklyMinutes: 0,
            relatedNames: [], tasks: []
        ),
        ImprovementCategoryTemplate(
            id: "guitar", name: "Guitar", pillar: .learning, trackingKind: .tasks,
            symbol: "guitars.fill", colorToken: "purple",
            purpose: "Build guitar skill through consistent, measured practice.",
            weeklySessions: 5, weeklyMinutes: 100,
            relatedNames: ["Music"],
            tasks: [
                measuredTask(
                    "Guitar Practice", .selectedWeekdays, [2, 3, 4, 5, 6], 19 * 60, 20,
                    measurements: [
                        MeasurementBlueprint(name: "Duration", type: .duration, unit: "min"),
                        MeasurementBlueprint(name: "Songs learned", type: .count, unit: "songs")
                    ]
                )
            ],
            parentTemplateID: "music"
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

    /// Same as `task(...)`, for the common case of several simultaneous
    /// measurements instead of one target/unit pair — no single value is
    /// "the" target, so targetValue/targetUnit stay nil here.
    private static func measuredTask(
        _ name: String, _ repeatType: RepeatType, _ weekdays: [Int],
        _ startMinutes: Int, _ durationMinutes: Int,
        measurements: [MeasurementBlueprint]
    ) -> ImprovementTaskTemplate {
        ImprovementTaskTemplate(
            name: name, repeatType: repeatType, weekdays: weekdays,
            startMinutes: startMinutes, durationMinutes: durationMinutes,
            targetValue: nil, targetUnit: nil, measurements: measurements
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
