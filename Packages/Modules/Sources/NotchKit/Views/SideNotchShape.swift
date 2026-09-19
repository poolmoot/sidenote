import SwiftUI

/// The pill-shaped notch body: straight sides fused to a screen edge, with the two corners on
/// the bezel curving outward into concave "shoulders" instead of a plain rounded corner, so the
/// shape reads as a continuation of the bezel rather than a panel floating in front of it.
///
/// The geometry is authored once for the right edge, anchored at the origin, then mirrored for
/// the left edge.
struct SideNotchShape: Shape {
    var edge: NotchEdge
    var flare: CGFloat
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, cornerRadius) }
        set {
            flare = newValue.first
            cornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let origin = CGRect(origin: .zero, size: rect.size)
        let rightEdge = Self.path(huggingRightEdgeOf: origin, flare: flare, cornerRadius: cornerRadius)
        let oriented = edge == .left
            ? rightEdge.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.width, ty: 0))
            : rightEdge
        return oriented.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }

    /// Builds the outline hugging the right edge (`rect.maxX`) of `rect`. The two shoulders eat
    /// into the top-right and bottom-right corners on the way in from the edge; the straight run
    /// between them sits `flare` points in from `rect.minY` and `rect.maxY`, and its own two
    /// corners (on the far side, away from the edge) are rounded by `cornerRadius`.
    private static func path(huggingRightEdgeOf rect: CGRect, flare: CGFloat, cornerRadius: CGFloat) -> Path {
        // The rounded corner claims its radius out of half the available width first, and the
        // shoulder gets whatever width is left over. Doing it in the other order would square
        // off the corners once the pill is folded down thin.
        let radius = max(0, min(cornerRadius, rect.width / 2))
        let shoulder = max(0, min(flare, rect.height / 2, rect.width - radius))
        let innerRadius = max(0, min(radius, (rect.height - 2 * shoulder) / 2))

        let bodyTop = rect.minY + shoulder
        let bodyBottom = rect.maxY - shoulder

        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))

        if shoulder > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - shoulder, y: rect.minY),
                radius: shoulder,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: rect.minX + innerRadius, y: bodyTop))
        path.addArc(
            center: CGPoint(x: rect.minX + innerRadius, y: bodyTop + innerRadius),
            radius: innerRadius,
            startAngle: .degrees(270),
            endAngle: .degrees(180),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX, y: bodyBottom - innerRadius))
        path.addArc(
            center: CGPoint(x: rect.minX + innerRadius, y: bodyBottom - innerRadius),
            radius: innerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(90),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX - shoulder, y: bodyBottom))

        if shoulder > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - shoulder, y: rect.maxY),
                radius: shoulder,
                startAngle: .degrees(270),
                endAngle: .degrees(360),
                clockwise: false
            )
        }

        path.closeSubpath()
        return path
    }
}
