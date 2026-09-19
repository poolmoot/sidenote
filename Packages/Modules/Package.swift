// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Modules",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AppInfo", targets: ["AppInfo"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "NotchWidgetAPI", targets: ["NotchWidgetAPI"]),
        .library(name: "NotchKit", targets: ["NotchKit"]),
        .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "ShelfFeature", targets: ["ShelfFeature"]),
        .library(name: "NotesFeature", targets: ["NotesFeature"]),
    ],
    targets: [
        .target(name: "AppInfo"),
        .target(name: "DesignSystem"),
        .target(name: "NotchWidgetAPI"),
        .target(name: "NotchKit", dependencies: ["NotchWidgetAPI", "DesignSystem", "AppInfo"]),
        .target(name: "SettingsFeature", dependencies: ["NotchKit", "AppInfo"]),
        .target(name: "Persistence", dependencies: ["AppInfo"]),
        .target(name: "ShelfFeature", dependencies: ["NotchWidgetAPI", "Persistence", "DesignSystem", "AppInfo"]),
        .target(name: "NotesFeature", dependencies: ["NotchWidgetAPI", "Persistence", "DesignSystem", "AppInfo"]),
        .testTarget(name: "AppInfoTests", dependencies: ["AppInfo"]),
        .testTarget(name: "NotchKitTests", dependencies: ["NotchKit", "NotchWidgetAPI"]),
        .testTarget(name: "SettingsFeatureTests", dependencies: ["SettingsFeature"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
        .testTarget(name: "ShelfFeatureTests", dependencies: ["ShelfFeature"]),
        .testTarget(name: "NotesFeatureTests", dependencies: ["NotesFeature", "Persistence"]),
    ]
)
