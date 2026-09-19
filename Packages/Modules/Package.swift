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
    ],
    targets: [
        .target(name: "AppInfo"),
        .target(name: "DesignSystem"),
        .target(name: "NotchWidgetAPI"),
        .target(name: "NotchKit", dependencies: ["NotchWidgetAPI", "DesignSystem", "AppInfo"]),
        .target(name: "SettingsFeature", dependencies: ["NotchKit", "AppInfo"]),
        .testTarget(name: "AppInfoTests", dependencies: ["AppInfo"]),
        .testTarget(name: "NotchKitTests", dependencies: ["NotchKit", "NotchWidgetAPI"]),
        .testTarget(name: "SettingsFeatureTests", dependencies: ["SettingsFeature"]),
    ]
)
