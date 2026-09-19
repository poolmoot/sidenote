import CoreGraphics

/// Pure placement maths. Panel coordinates have a top-left origin (the container view is flipped,
/// as SwiftUI is), so `y` grows down the screen.
public enum NotchGeometry {
    /// The panel: a strip `depth` wide, the full height of the screen, flush with `edge`.
    /// Rounded to whole points so no hairline of wallpaper shows between notch and bezel.
    public static func panelFrame(screenFrame: CGRect, edge: NotchEdge, depth: CGFloat) -> CGRect {
        let width = depth.rounded(.up)
        let x = edge == .right ? screenFrame.maxX - width : screenFrame.minX
        return CGRect(x: x.rounded(), y: screenFrame.minY, width: width, height: screenFrame.height)
    }

    /// Where a shape sits in the panel. `alongOffset` moves its centre down from the panel's
    /// middle; the result is clamped so the whole shape stays on screen.
    public static func shapeRect(panelSize: CGSize, edge: NotchEdge, size: NotchShapeSize, alongOffset: CGFloat) -> CGRect {
        let center = clamp(
            panelSize.height / 2 + alongOffset,
            min: size.length / 2,
            max: panelSize.height - size.length / 2
        )
        let x = edge == .right ? panelSize.width - size.depth : 0
        return CGRect(x: x, y: center - size.length / 2, width: size.depth, height: size.length)
    }

    /// Clamps an offset so a shape of `length` stays fully on a panel `panelLength` tall.
    public static func clampedOffset(_ offset: CGFloat, panelLength: CGFloat, length: CGFloat) -> CGFloat {
        let limit = max(0, (panelLength - length) / 2)
        return clamp(offset, min: -limit, max: limit)
    }

    /// The region that receives hover and drops: the shape grown inward by `margin`, and
    /// optionally shortened by `lengthInset` at each end.
    ///
    /// The folded pill shortens by its flares: those taper away from the bezel, so treating the
    /// full shape as live makes the notch open for a pointer that never reached the edge.
    public static func hotRect(
        shapeRect: CGRect,
        edge: NotchEdge,
        margin: CGFloat,
        lengthInset: CGFloat = 0
    ) -> CGRect {
        var rect = shapeRect
        rect.size.width += margin
        if edge == .right { rect.origin.x -= margin }
        let inset = min(lengthInset, rect.height / 2)
        rect.origin.y += inset
        rect.size.height -= 2 * inset
        return rect
    }

    /// Index of the screen to use: the one whose ID matches `displayID`, else the primary (index 0).
    public static func preferredScreenIndex(displayIDs: [String?], preferred displayID: String?) -> Int? {
        guard !displayIDs.isEmpty else { return nil }
        if let displayID, let index = displayIDs.firstIndex(of: displayID) {
            return index
        }
        return 0
    }

    /// A clamp that never traps, even when the range is inverted (a shape longer than the screen).
    static func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return lower }
        return Swift.min(Swift.max(value, lower), upper)
    }
}
