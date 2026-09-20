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
    /// `CFBundleVersion` — the build number shown on Settings › About, distinct from the
    /// user-facing `version` (`CFBundleShortVersionString`).
    public let build: String
    /// Settings › About's "View on GitHub" link, read from the `GitHubRepositoryURL` Info.plist
    /// key (`project.yml`'s `INFOPLIST_KEY_GitHubRepositoryURL`) — not a Swift literal, so this
    /// isn't "the app name in Swift" (`AGENTS.md` rule 3 is about the product name specifically).
    /// `nil` when the key is missing or isn't a valid URL (e.g. a test `infoDictionary`), in which
    /// case Settings simply omits the link rather than pointing at a guessed address.
    public let repositoryURL: URL?

    public init(infoDictionary: [String: Any]) {
        func value(_ key: String) -> String? {
            guard let string = infoDictionary[key] as? String, !string.isEmpty else { return nil }
            return string
        }
        name = value("CFBundleDisplayName") ?? value("CFBundleName") ?? "App"
        bundleIdentifier = value("CFBundleIdentifier") ?? "local.app"
        version = value("CFBundleShortVersionString") ?? "0.0.0"
        build = value("CFBundleVersion") ?? "0"
        repositoryURL = value("GitHubRepositoryURL").flatMap(URL.init(string:))
    }

    public static let current = AppIdentity(infoDictionary: Bundle.main.infoDictionary ?? [:])

    public func logger(_ category: String) -> Logger {
        Logger(subsystem: bundleIdentifier, category: category)
    }
}
