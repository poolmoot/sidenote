import AppKit
import SwiftUI
import AppInfo
import SettingsFeature

/// The ordinary Settings window. The app has no Dock icon, so it activates itself to bring the
/// window in front of whatever app the user was in.
@MainActor
final class SettingsWindowController: NSObject {
    private let preferences: Preferences
    private var window: NSWindow?
    private let makeContent: () -> NSViewController

    init(preferences: Preferences, makeContent: @escaping () -> NSViewController) {
        self.preferences = preferences
        self.makeContent = makeContent
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        // Deferred from M1: while the app is `LSUIElement` (no Dock icon, no regular Cmd-Tab
        // presence), the Settings window still deserves to behave like a normal window while it's
        // open — a proper Cmd-Tab entry, standard focus handling. `windowWillClose` below returns
        // the policy to `.accessory` so a closed Settings window doesn't leave the app looking
        // "still running as a regular app", which is exactly the state `FullScreenObserver`'s
        // app-activation notification reacts to — left on, it could misread a later full-screen
        // transition in some other app as involving this one.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: makeContent())
        window.title = "\(AppIdentity.current.name) Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
