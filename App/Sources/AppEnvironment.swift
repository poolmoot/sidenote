import AppKit
import Observation
import AppInfo
import NotchKit
import NotchWidgetAPI
import SettingsFeature
import Persistence
import ShelfFeature
import NotesFeature

/// The composition root: the one place that builds every object and wires modules together.
/// Modules never reach for each other directly.
@MainActor
final class AppEnvironment {
    private let preferences: Preferences
    private let notch: NotchController
    private let settings: SettingsWindowController
    private let statusItem: StatusItemController
    private let shelfStore: ShelfStore
    private let notesStore: NotesStore

    init() {
        let preferences = Preferences()
        let settings = SettingsWindowController(preferences: preferences)

        let shelfFileStore = JSONFileStore<ShelfDocument>(url: Self.makeShelfFileURL())
        let shelfStore = ShelfStore(store: shelfFileStore)
        let shelfWidget = ShelfWidget(store: shelfStore)

        let notesFileStore = JSONFileStore<NotesDocument>(
            url: Self.makeNotesFileURL(),
            logger: AppIdentity.current.logger("notes")
        )
        let notesStore = NotesStore(store: notesFileStore)
        let notesWidget = NotesWidget(store: notesStore)

        let widgets: [any NotchWidget] = [shelfWidget, notesWidget] + PlaceholderWidget.all()
        let notch = NotchController(widgets: widgets, configuration: preferences.notchConfiguration)
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
        self.shelfStore = shelfStore
        self.notesStore = notesStore
    }

    func start() {
        statusItem.install()
        notch.start()
        observePreferences()
    }

    func showSettings() {
        settings.show()
    }

    /// Writes any pending content synchronously. Called from `applicationWillTerminate`.
    func flush() {
        shelfStore.flush()
        notesStore.flush()
    }

    /// `shelf.json`'s URL, falling back to a temporary directory in the unlikely event
    /// Application Support can't be resolved or created, so the app still runs (with content
    /// that won't survive relaunch) rather than crashing at startup.
    private static func makeShelfFileURL() -> URL {
        if let url = try? AppPaths.shelfFile() {
            return url
        }
        AppIdentity.current.logger("persistence").error("Falling back to a temporary shelf file: Application Support was unavailable.")
        return FileManager.default.temporaryDirectory.appendingPathComponent("shelf.json")
    }

    /// `notes.json`'s URL, with the same temporary-directory fallback as `makeShelfFileURL()`.
    private static func makeNotesFileURL() -> URL {
        if let url = try? AppPaths.notesFile() {
            return url
        }
        AppIdentity.current.logger("notes").error("Falling back to a temporary notes file: Application Support was unavailable.")
        return FileManager.default.temporaryDirectory.appendingPathComponent("notes.json")
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
