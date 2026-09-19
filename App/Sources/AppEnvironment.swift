import AppKit
import Observation
import NotchKit
import SettingsFeature

/// The composition root: the one place that builds every object and wires modules together.
/// Modules never reach for each other directly.
@MainActor
final class AppEnvironment {
    private let preferences: Preferences
    private let notch: NotchController
    private let settings: SettingsWindowController
    private let statusItem: StatusItemController

    init() {
        let preferences = Preferences()
        let settings = SettingsWindowController(preferences: preferences)
        let notch = NotchController(widgets: PlaceholderWidget.all(), configuration: preferences.notchConfiguration)
        let statusItem = StatusItemController(
            isNotchVisible: { preferences.isNotchVisible },
            onOpenSettings: { settings.show() },
            onToggleNotch: { preferences.isNotchVisible.toggle() }
        )

        notch.onOpenSettings = { settings.show() }
        notch.onAlongOffsetCommitted = { preferences.alongOffset = $0 }
        notch.contextMenuProvider = { statusItem.makeMenu() }

        self.preferences = preferences
        self.settings = settings
        self.notch = notch
        self.statusItem = statusItem
    }

    func start() {
        statusItem.install()
        notch.start()
        observePreferences()
    }

    func showSettings() {
        settings.show()
    }

    /// Pushes every preference change into the notch. `withObservationTracking` fires once, so it
    /// re-registers itself after each change.
    private func observePreferences() {
        withObservationTracking {
            _ = preferences.notchConfiguration
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                notch.apply(preferences.notchConfiguration)
                observePreferences()
            }
        }
    }
}
