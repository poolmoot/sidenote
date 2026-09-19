import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?

    /// Explicit entry point: without a main nib, `NSApplicationMain` would never create the delegate.
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment()
        NSApp.mainMenu = MainMenu.make(target: self, settingsAction: #selector(showSettings(_:)))
        environment.start()
        self.environment = environment
    }

    @objc private func showSettings(_ sender: Any?) {
        environment?.showSettings()
    }
}
