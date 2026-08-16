// swift-tools-version: 5.10

import PackageDescription

/// A headless test harness for LifeOS business and persistence components.
/// The iOS app still builds from LifeOS.xcodeproj; this package lets CI run
/// core tests without requiring an iPhone Simulator process.
let package = Package(
    name: "LifeOSCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LifeOS", targets: ["LifeOS"])
    ],
    targets: [
        .target(
            name: "LifeOS",
            path: "LifeOS",
            exclude: [
                "Views",
                "Assets.xcassets",
                "LifeOSApp.swift",
                "PrivacyInfo.xcprivacy",
                "Engine/NotificationRouter.swift",
                "Engine/RealNotificationCenter.swift"
            ],
            sources: [
                "Models/Models.swift",
                "Models/NutritionModels.swift",
                "Models/SeedData.swift",
                "Models/SchemaVersioning.swift",
                "Engine/CategoryHierarchy.swift",
                "Engine/CategoryProgressEngine.swift",
                "Engine/TaskOccurrenceActions.swift",
                "Engine/QuickAddValidation.swift",
                "Engine/OnboardingValidation.swift",
                "Engine/AddGoalValidation.swift",
                "Engine/LifeOSBackupService.swift",
                "Engine/ImprovementTemplates.swift",
                "Engine/PortableMetricService.swift",
                "Engine/PlanningService.swift",
                "Engine/PersistenceSupport.swift",
                "Engine/ProgressEngine.swift",
                "Engine/CalendarRepository.swift",
                "Engine/TodayViewModel.swift",
                "Engine/ProgressMetric.swift",
                "Engine/MeasurementRepository.swift",
                "Engine/RelationshipRepository.swift",
                "Engine/NutritionRepository.swift",
                "Engine/BodyTrackingRepository.swift",
                "Engine/NutritionEngine.swift",
                "Engine/NotificationScheduling.swift",
                "Engine/ReminderService.swift"
            ]
        ),
        .testTarget(
            name: "LifeOSUnitTests",
            dependencies: ["LifeOS"],
            path: "LifeOSUnitTests"
        ),
        .testTarget(
            name: "LifeOSComponentTests",
            dependencies: ["LifeOS"],
            path: "LifeOSComponentTests"
        )
    ]
)
