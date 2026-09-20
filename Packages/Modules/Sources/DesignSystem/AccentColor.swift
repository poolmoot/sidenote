import SwiftUI

/// A persistable stand-in for `Color` (which isn't itself `Codable`), so `Preferences` can save
/// the user's chosen accent colour (Settings › Appearance) in `UserDefaults`.
public struct AccentColor: Equatable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var color: Color { Color(red: red, green: green, blue: blue) }

    /// Matches `Color.accentColor`'s usual system-blue default closely enough that switching this
    /// setting on and back off doesn't look like a color mismatch.
    public static let systemBlue = AccentColor(red: 0.0, green: 0.478, blue: 1.0)
}
