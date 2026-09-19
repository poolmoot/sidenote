import CoreGraphics
import NotchWidgetAPI

/// The size of the notch shape. `depth` runs in from the screen edge; `length` runs along it and
/// includes both concave flares.
public struct NotchShapeSize: Equatable, Sendable {
    public var depth: CGFloat
    public var length: CGFloat

    public init(depth: CGFloat, length: CGFloat) {
        self.depth = depth
        self.length = length
    }
}

/// Every fixed dimension of the notch, in points.
public struct NotchMetrics: Equatable, Sendable {
    public var foldedDepth: CGFloat = 6
    public var foldedBodyLength: CGFloat = 72
    public var foldedCornerRadius: CGFloat = 3
    public var tilesDepth: CGFloat = 64
    public var tileExtent: CGFloat = 52
    public var gearExtent: CGFloat = 36
    public var contentPadding: CGFloat = 10
    public var cornerRadius: CGFloat = 18
    /// Radius of the concave shoulders where the shape meets the bezel.
    public var flare: CGFloat = 12
    /// Extra depth, beyond the shape, that still counts as hovering it.
    public var hoverMargin: CGFloat = 6
    /// The same, for the folded pill. Much tighter: the pill is meant to react when the pointer
    /// reaches the screen edge, not when it merely passes nearby.
    public var foldedHoverMargin: CGFloat = 2
    public var defaultExpandedSize = CGSize(width: 320, height: 420)

    public init() {}

    public static let standard = NotchMetrics()

    public func shapeSize(for state: NotchState, tileCount: Int, expandedSizes: [WidgetID: CGSize]) -> NotchShapeSize {
        switch state {
        case .folded:
            return NotchShapeSize(depth: foldedDepth, length: foldedBodyLength + 2 * flare)
        case .tiles:
            let body = 2 * contentPadding + CGFloat(tileCount) * tileExtent + gearExtent
            return NotchShapeSize(depth: tilesDepth, length: body + 2 * flare)
        case .expanded(let id, _):
            let size = expandedSizes[id] ?? defaultExpandedSize
            return NotchShapeSize(depth: size.width, length: size.height + 2 * flare)
        }
    }

    public func cornerRadius(for state: NotchState) -> CGFloat {
        state == .folded ? foldedCornerRadius : cornerRadius
    }

    /// The panel is as deep as the deepest shape any state can take, plus the hover margin.
    public func panelDepth(expandedSizes: [CGSize]) -> CGFloat {
        let deepest = expandedSizes.map(\.width).max() ?? defaultExpandedSize.width
        return max(tilesDepth, deepest) + hoverMargin
    }

    /// Where a state's content goes: the shape minus its flares and padding. Never negative.
    public func contentRect(in shapeRect: CGRect) -> CGRect {
        let dx = contentPadding
        let dy = flare + contentPadding
        return CGRect(
            x: shapeRect.minX + dx,
            y: shapeRect.minY + dy,
            width: max(0, shapeRect.width - 2 * dx),
            height: max(0, shapeRect.height - 2 * dy)
        )
    }
}
