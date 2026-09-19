import CoreGraphics

/// The user-controlled settings the notch needs. The app maps its preferences onto this, so
/// NotchKit never reads UserDefaults itself.
public struct NotchConfiguration: Equatable, Sendable {
    public var edge: NotchEdge
    /// `NSScreen.displayIdentifier` of the chosen display; nil means the primary display.
    public var displayID: String?
    /// How far the pill's centre sits below the middle of the edge, in points.
    public var alongOffset: CGFloat
    public var isVisible: Bool
    public var hoverDelay: Duration
    public var graceDelay: Duration

    public init(
        edge: NotchEdge = .right,
        displayID: String? = nil,
        alongOffset: CGFloat = 0,
        isVisible: Bool = true,
        hoverDelay: Duration = .milliseconds(150),
        graceDelay: Duration = .milliseconds(250)
    ) {
        self.edge = edge
        self.displayID = displayID
        self.alongOffset = alongOffset
        self.isVisible = isVisible
        self.hoverDelay = hoverDelay
        self.graceDelay = graceDelay
    }
}
