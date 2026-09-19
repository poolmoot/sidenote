import CoreGraphics
import SwiftUI
import Testing
@testable import NotchKit

struct SideNotchShapeTests {
    let rect = CGRect(x: 10, y: 20, width: 64, height: 200)

    @Test func rightEdgeShapeFillsItsRect() {
        let path = SideNotchShape(edge: .right, flare: 12, cornerRadius: 18).path(in: rect)
        #expect(path.boundingRect.integral == rect)
    }

    @Test func rightEdgeFlareTouchesBezelNotFarSide() {
        let path = SideNotchShape(edge: .right, flare: 12, cornerRadius: 18).path(in: rect)
        // At the foot of the top flare, right against the bezel: filled.
        #expect(path.contains(CGPoint(x: rect.maxX - 1, y: rect.minY + 11)))
        // Same height on the far side: empty, because only the bezel side flares.
        #expect(!path.contains(CGPoint(x: rect.minX + 1, y: rect.minY + 11)))
        // The corner of the flare's square is carved away — that is what makes it concave.
        #expect(!path.contains(CGPoint(x: rect.maxX - 1, y: rect.minY + 1)))
        // Middle of the body: inside.
        #expect(path.contains(CGPoint(x: rect.midX, y: rect.midY)))
    }

    @Test func leftEdgeIsMirrored() {
        let path = SideNotchShape(edge: .left, flare: 12, cornerRadius: 18).path(in: rect)
        #expect(path.contains(CGPoint(x: rect.minX + 1, y: rect.minY + 11)))
        #expect(!path.contains(CGPoint(x: rect.maxX - 1, y: rect.minY + 11)))
    }

    @Test func thinFoldedPillKeepsRoundedCorners() {
        let pill = CGRect(x: 0, y: 0, width: 6, height: 96)
        let path = SideNotchShape(edge: .right, flare: 12, cornerRadius: 3).path(in: pill)
        #expect(path.boundingRect.integral == pill)
        #expect(path.contains(CGPoint(x: 3, y: 48)))
    }
}
