import SwiftUI

/// Colours for the notch surface. The notch is always dark, whatever the system appearance.
public enum Palette {
    public static let notch = Color.black
    public static let primaryText = Color.white
    public static let secondaryText = Color.white.opacity(0.6)
    public static let tileFill = Color.white.opacity(0.08)
    public static let tileHover = Color.white.opacity(0.16)
    /// The user's chosen accent colour (Settings › Appearance), applied process-wide like the rest
    /// of this palette. `AppEnvironment` sets this at launch and on every change; nothing here
    /// reads `UserDefaults` itself. `@MainActor`-isolated (rather than a plain `let`) because it's
    /// mutable shared state — every reader in this UI-only app is already on the main actor.
    @MainActor public static var accent = Color.accentColor
    @MainActor public static var dropHighlight: Color { accent }
}
