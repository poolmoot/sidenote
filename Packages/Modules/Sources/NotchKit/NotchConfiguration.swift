import CoreGraphics
import SwiftUI
import DesignSystem
import NotchWidgetAPI

/// The user-controlled settings the notch needs. The app maps its preferences onto this, so
/// NotchKit never reads UserDefaults itself.
public struct NotchConfiguration: Equatable, Sendable {
    public var edge: NotchEdge
    /// `NSScreen.displayIdentifier` of the chosen display; nil means the primary display.
    public var displayID: String?
    /// How far the pill's centre sits below the middle of the edge, in points.
    public var alongOffset: CGFloat
    public var isVisible: Bool
    /// Hide the folded pill while a full-screen app is in front. Off by default: the pill is meant
    /// to stay reachable in every app, and a hidden pill reads as the app not running at all.
    public var hidesInFullScreen: Bool
    public var hoverDelay: Duration
    public var graceDelay: Duration
    /// Solid black or Liquid Glass (spec §3.6, §5).
    public var style: NotchStyle
    /// S / M / L, scaling `NotchMetrics` (spec §3.6).
    public var pillSize: PillSize
    /// System / Always / Never (spec §3.6).
    public var reduceMotion: ReduceMotionSetting
    /// The enabled widgets, in the order their tiles show (spec §3.6 Widgets tab). An id with no
    /// matching widget is ignored; a widget with no entry here simply has no tile.
    public var enabledWidgetIDs: [WidgetID]
    /// The user's accent colour (spec §3.6 Appearance tab), threaded through so the notch's own
    /// chrome (tile hover/selection, the drop-target border) re-renders live when it changes —
    /// `NotchViewModel.accentColor` is `@Observable`-tracked, unlike `Palette.accent`, which is a
    /// plain static the rest of the app reads best-effort.
    public var accentColor: Color

    public init(
        edge: NotchEdge = .right,
        displayID: String? = nil,
        alongOffset: CGFloat = 0,
        isVisible: Bool = true,
        hidesInFullScreen: Bool = false,
        hoverDelay: Duration = .milliseconds(150),
        graceDelay: Duration = .milliseconds(250),
        style: NotchStyle = .solid,
        pillSize: PillSize = .medium,
        reduceMotion: ReduceMotionSetting = .system,
        enabledWidgetIDs: [WidgetID] = [],
        accentColor: Color = .accentColor
    ) {
        self.edge = edge
        self.displayID = displayID
        self.alongOffset = alongOffset
        self.isVisible = isVisible
        self.hidesInFullScreen = hidesInFullScreen
        self.hoverDelay = hoverDelay
        self.graceDelay = graceDelay
        self.style = style
        self.pillSize = pillSize
        self.reduceMotion = reduceMotion
        self.enabledWidgetIDs = enabledWidgetIDs
        self.accentColor = accentColor
    }
}
