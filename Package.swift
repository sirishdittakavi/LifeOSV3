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
                "LifeOSApp.swift",
                "Models/SeedData.swift",
                "Engine/FoodCaptureService.swift",
                "Engine/ReminderService.swift"
            ],
            sources: [
                "Models/Models.swift",
                "Engine/CategoryHierarchy.swift",
                "Engine/CategoryProgressEngine.swift",
                "Engine/LifeOSBackupService.swift",
                "Engine/ImprovementTemplates.swift",
                "Engine/PortableMetricService.swift",
                "Engine/PlanningService.swift",
                "Engine/ProgressEngine.swift"
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
