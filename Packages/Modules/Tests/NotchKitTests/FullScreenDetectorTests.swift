import CoreGraphics
import Testing
@testable import NotchKit

struct FullScreenDetectorTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private func window(pid: pid_t = 42, layer: Int = 0, _ bounds: CGRect) -> WindowSummary {
        WindowSummary(pid: pid, layer: layer, bounds: bounds)
    }

    @Test func windowCoveringDisplayIsFullScreen() {
        #expect(FullScreenDetector.isFullScreen(screenBounds: screen, frontmostPID: 42, windows: [window(screen)]))
    }

    @Test func windowBelowCameraNotchIsFullScreen() {
        let below = CGRect(x: 0, y: 32, width: 1512, height: 950)
        #expect(FullScreenDetector.isFullScreen(screenBounds: screen, frontmostPID: 42, windows: [window(below)], safeAreaTopInset: 32))
    }

    @Test func ordinaryWindowIsNotFullScreen() {
        let small = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(!FullScreenDetector.isFullScreen(screenBounds: screen, frontmostPID: 42, windows: [window(small)]))
    }

    @Test func otherAppsWindowDoesNotCount() {
        #expect(!FullScreenDetector.isFullScreen(screenBounds: screen, frontmostPID: 42, windows: [window(pid: 7, screen)]))
    }

    @Test func overlayLayerDoesNotCount() {
        #expect(!FullScreenDetector.isFullScreen(screenBounds: screen, frontmostPID: 42, windows: [window(layer: 25, screen)]))
    }
}
