import AppKit

/// A window as the full-screen check needs it: which process owns it, what layer it sits on, and
/// its frame in CoreGraphics screen coordinates (top-left origin, anchored to the primary display).
struct WindowSummary: Equatable, Sendable {
    let pid: pid_t
    let layer: Int
    let bounds: CGRect
}

/// Answers a single question on demand — is the frontmost app currently full screen on a given
/// display — by inspecting window geometry rather than subscribing to a full-screen notification.
enum FullScreenDetector {
    /// The pure geometry check, kept apart from `isFullScreenAppFrontmost` so it can be exercised
    /// in tests without touching WindowServer: does a normal-layer window owned by
    /// `frontmostPID` span `screenBounds`?
    static func isFullScreen(
        screenBounds: CGRect,
        frontmostPID: pid_t,
        windows: [WindowSummary],
        safeAreaTopInset: CGFloat = 0
    ) -> Bool {
        let slack: CGFloat = 4
        let ownedNormalWindows = windows.filter { $0.pid == frontmostPID && $0.layer == 0 }

        for bounds in ownedNormalWindows.map(\.bounds) {
            guard abs(bounds.minX - screenBounds.minX) <= slack,
                  abs(bounds.width - screenBounds.width) <= slack
            else { continue }

            // Edge to edge with the display: a video, a game, or simply a screen without a
            // camera notch.
            let spansFullHeight = abs(bounds.minY - screenBounds.minY) <= slack
                && abs(bounds.height - screenBounds.height) <= slack
            if spansFullHeight {
                return true
            }

            // Full screen under a camera notch, or below a menu bar that stays visible: the
            // window can't reach the very top, but it starts just under the inset and still
            // reaches all the way down.
            let topInset = max(safeAreaTopInset, 40) + slack
            let startsNearTop = bounds.minY >= screenBounds.minY - slack
                && bounds.minY <= screenBounds.minY + topInset
            let reachesBottom = abs(bounds.maxY - screenBounds.maxY) <= slack
            let fillsRestOfHeight = bounds.height >= screenBounds.height - (topInset + 10)
            if startsNearTop, reachesBottom, fillsRestOfHeight {
                return true
            }
        }
        return false
    }

    /// Reads the live window list from WindowServer and runs `isFullScreen` against it. Meant to
    /// be invoked from an event callback — a space change, an app switch — and never on a timer.
    @MainActor
    static func isFullScreenAppFrontmost(on screen: NSScreen) -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              frontmostApp.bundleIdentifier != Bundle.main.bundleIdentifier
        else { return false }

        // CGWindowList reports bounds with a top-left origin pinned to the primary display, while
        // an AppKit screen frame uses a bottom-left origin; flip against the primary display's
        // height before comparing the two.
        let primaryDisplayHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let screenBounds = CGRect(
            x: screen.frame.minX,
            y: primaryDisplayHeight - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )

        let rawWindowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        let windows: [WindowSummary] = rawWindowInfo.compactMap { entry in
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }
            return WindowSummary(pid: pid, layer: layer, bounds: bounds)
        }

        return isFullScreen(
            screenBounds: screenBounds,
            frontmostPID: frontmostApp.processIdentifier,
            windows: windows,
            safeAreaTopInset: screen.safeAreaInsets.top
        )
    }
}
