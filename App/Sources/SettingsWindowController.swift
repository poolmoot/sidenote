import AppKit
import SwiftUI
import AppInfo
import SettingsFeature

/// The ordinary Settings window. The app has no Dock icon, so it activates itself to bring the
/// window in front of whatever app the user was in.
@MainActor
final class SettingsWindowController {
    private let preferences: Preferences
    private var window: NSWindow?

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(preferences: preferences)))
        window.title = "\(AppIdentity.current.name) Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
