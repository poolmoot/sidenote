import Foundation
import os

/// Who this app is, read from its Info.plist.
///
/// The app's name is written in exactly one place — `Config/Branding.xcconfig` — and reaches
/// Swift only through here, so renaming the app never means editing code.
public struct AppIdentity: Sendable, Equatable {
    public let name: String
    public let bundleIdentifier: String
    public let version: String

    public init(infoDictionary: [String: Any]) {
        func value(_ key: String) -> String? {
            guard let string = infoDictionary[key] as? String, !string.isEmpty else { return nil }
            return string
        }
        name = value("CFBundleDisplayName") ?? value("CFBundleName") ?? "App"
        bundleIdentifier = value("CFBundleIdentifier") ?? "local.app"
        version = value("CFBundleShortVersionString") ?? "0.0.0"
    }

    public static let current = AppIdentity(infoDictionary: Bundle.main.infoDictionary ?? [:])

    public func logger(_ category: String) -> Logger {
        Logger(subsystem: bundleIdentifier, category: category)
    }
}
