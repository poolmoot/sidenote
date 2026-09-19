import SwiftUI

/// Colours for the notch surface. The notch is always dark, whatever the system appearance.
public enum Palette {
    public static let notch = Color.black
    public static let primaryText = Color.white
    public static let secondaryText = Color.white.opacity(0.6)
    public static let tileFill = Color.white.opacity(0.08)
    public static let tileHover = Color.white.opacity(0.16)
    public static let dropHighlight = Color.accentColor
}
