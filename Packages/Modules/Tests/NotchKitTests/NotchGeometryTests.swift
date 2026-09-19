import CoreGraphics
import Testing
import NotchWidgetAPI
@testable import NotchKit

struct NotchGeometryTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let size = NotchShapeSize(depth: 64, length: 200)

    @Test func panelHugsRightEdgeFullHeight() {
        let frame = NotchGeometry.panelFrame(screenFrame: screen, edge: .right, depth: 325.5)
        #expect(frame == CGRect(x: 1186, y: 0, width: 326, height: 982))
    }

    @Test func panelHugsLeftEdgeOnSecondaryScreen() {
        let secondary = CGRect(x: -1920, y: 100, width: 1920, height: 1080)
        let frame = NotchGeometry.panelFrame(screenFrame: secondary, edge: .left, depth: 100)
        #expect(frame == CGRect(x: -1920, y: 100, width: 100, height: 1080))
    }

    @Test func shapeIsCentredOnRightEdgeByDefault() {
        let rect = NotchGeometry.shapeRect(panelSize: CGSize(width: 326, height: 982), edge: .right, size: size, alongOffset: 0)
        #expect(rect == CGRect(x: 262, y: 391, width: 64, height: 200))
    }

    @Test func shapeSitsAtZeroOnLeftEdge() {
        let rect = NotchGeometry.shapeRect(panelSize: CGSize(width: 326, height: 982), edge: .left, size: size, alongOffset: 0)
        #expect(rect.minX == 0)
    }

    @Test func positiveOffsetMovesShapeDown() {
        let rect = NotchGeometry.shapeRect(panelSize: CGSize(width: 326, height: 982), edge: .right, size: size, alongOffset: 100)
        #expect(rect.minY == 491)
    }

    @Test func shapeIsClampedOnScreen() {
        let panel = CGSize(width: 326, height: 982)
        let low = NotchGeometry.shapeRect(panelSize: panel, edge: .right, size: size, alongOffset: 10_000)
        let high = NotchGeometry.shapeRect(panelSize: panel, edge: .right, size: size, alongOffset: -10_000)
        #expect(low.maxY == 982)
        #expect(high.minY == 0)
    }

    @Test func shapeLongerThanPanelDoesNotTrap() {
        let rect = NotchGeometry.shapeRect(panelSize: CGSize(width: 326, height: 100), edge: .right, size: size, alongOffset: 0)
        #expect(rect.minY == 0)
    }

    @Test func clampedOffsetLimitsTravel() {
        #expect(NotchGeometry.clampedOffset(1_000, panelLength: 1000, length: 100) == 450)
        #expect(NotchGeometry.clampedOffset(-1_000, panelLength: 1000, length: 100) == -450)
        #expect(NotchGeometry.clampedOffset(20, panelLength: 1000, length: 100) == 20)
    }

    @Test func hotRectGrowsInwardOnly() {
        let shape = CGRect(x: 262, y: 391, width: 64, height: 200)
        #expect(NotchGeometry.hotRect(shapeRect: shape, edge: .right, margin: 6) == CGRect(x: 256, y: 391, width: 70, height: 200))
        let left = CGRect(x: 0, y: 391, width: 64, height: 200)
        #expect(NotchGeometry.hotRect(shapeRect: left, edge: .left, margin: 6) == CGRect(x: 0, y: 391, width: 70, height: 200))
    }

    @Test func preferredScreenMatchesSavedDisplay() {
        #expect(NotchGeometry.preferredScreenIndex(displayIDs: ["A", "B"], preferred: "B") == 1)
    }

    @Test func preferredScreenFallsBackToPrimary() {
        #expect(NotchGeometry.preferredScreenIndex(displayIDs: ["A", "B"], preferred: "gone") == 0)
        #expect(NotchGeometry.preferredScreenIndex(displayIDs: ["A", nil], preferred: nil) == 0)
        #expect(NotchGeometry.preferredScreenIndex(displayIDs: [], preferred: "A") == nil)
    }
}

struct NotchMetricsTests {
    let metrics = NotchMetrics.standard

    @Test func foldedSizeIncludesFlares() {
        let size = metrics.shapeSize(for: .folded, tileCount: 3, expandedSizes: [:])
        #expect(size == NotchShapeSize(depth: metrics.foldedDepth, length: metrics.foldedBodyLength + 24))
    }

    @Test func tilesLengthGrowsWithTileCount() {
        let three = metrics.shapeSize(for: .tiles, tileCount: 3, expandedSizes: [:])
        let two = metrics.shapeSize(for: .tiles, tileCount: 2, expandedSizes: [:])
        #expect(three.length - two.length == metrics.tileExtent)
        #expect(three.depth == 64)
    }

    @Test func expandedUsesWidgetSizeOrDefault() {
        let custom = metrics.shapeSize(for: .expanded(.notes, dropTarget: false), tileCount: 3,
                                       expandedSizes: [.notes: CGSize(width: 280, height: 300)])
        #expect(custom == NotchShapeSize(depth: 280, length: 324))
        let fallback = metrics.shapeSize(for: .expanded(.shelf, dropTarget: false), tileCount: 3, expandedSizes: [:])
        #expect(fallback == NotchShapeSize(depth: 320, length: 444))
    }

    @Test func panelDepthCoversDeepestStatePlusMargin() {
        #expect(metrics.panelDepth(expandedSizes: [CGSize(width: 320, height: 1), CGSize(width: 280, height: 1)]) == 326)
        #expect(metrics.panelDepth(expandedSizes: []) == 326)
    }

    @Test func contentRectNeverGoesNegative() {
        let folded = metrics.contentRect(in: CGRect(x: 0, y: 0, width: 6, height: 96))
        #expect(folded.width == 0)
        #expect(folded.height == 52)
    }

    @Test func contentRectInsetsByFlareAndPadding() {
        let rect = metrics.contentRect(in: CGRect(x: 100, y: 100, width: 64, height: 200))
        #expect(rect == CGRect(x: 110, y: 122, width: 44, height: 156))
    }
}

struct HotRectTests {
    let folded = CGRect(x: 320, y: 400, width: 6, height: 96)   // pill body 72 + 12 flare each end

    @Test func foldedHotAreaStaysAtTheEdgeAndSkipsTheFlares() {
        let hot = NotchGeometry.hotRect(shapeRect: folded, edge: .right, margin: 2, lengthInset: 12)
        #expect(hot == CGRect(x: 318, y: 412, width: 8, height: 72))
    }

    @Test func lengthInsetNeverInvertsTheRect() {
        let hot = NotchGeometry.hotRect(shapeRect: folded, edge: .right, margin: 2, lengthInset: 500)
        #expect(hot.height == 0)
        #expect(hot.minY == folded.midY)
    }

    @Test func expandedHotAreaKeepsItsFullLength() {
        let expanded = CGRect(x: 6, y: 100, width: 320, height: 444)
        let hot = NotchGeometry.hotRect(shapeRect: expanded, edge: .left, margin: 6)
        #expect(hot == CGRect(x: 6, y: 100, width: 326, height: 444))
    }
}
