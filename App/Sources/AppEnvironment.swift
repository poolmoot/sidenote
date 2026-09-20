import AppKit
import SwiftUI
import UserNotifications
import Observation
import AppInfo
import DesignSystem
import NotchKit
import NotchWidgetAPI
import SettingsFeature
import Persistence
import ShelfFeature
import NotesFeature
import RemindersFeature

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
    private let remindersStore: RemindersStore
    private let notificationDelegate: NotificationDelegate

    init() {
        let preferences = Preferences()

        let shelfFileStore = JSONFileStore<ShelfDocument>(url: Self.makeShelfFileURL())
        let shelfStore = ShelfStore(store: shelfFileStore)
        let shelfWidget = ShelfWidget(store: shelfStore)

        let notesFileStore = JSONFileStore<NotesDocument>(
            url: Self.makeNotesFileURL(),
            logger: AppIdentity.current.logger("notes")
        )
        let notesStore = NotesStore(store: notesFileStore)
        let notesWidget = NotesWidget(store: notesStore)

        let remindersFileStore = JSONFileStore<RemindersDocument>(
            url: Self.makeRemindersFileURL(),
            logger: AppIdentity.current.logger("reminders")
        )
        let remindersStore = RemindersStore(store: remindersFileStore, scheduler: UNReminderScheduler())
        let remindersWidget = RemindersWidget(store: remindersStore)

        // Settings › Appearance's accent colour flows through `Palette` process-wide — set once
        // here, then kept in sync by `observePreferences()`.
        Palette.accent = preferences.accentColor.color

        let widgets: [any NotchWidget] = [shelfWidget, notesWidget, remindersWidget]
        let notch = NotchController(widgets: widgets, configuration: preferences.notchConfiguration)
        let settings = SettingsWindowController(preferences: preferences) {
            NSHostingController(
                rootView: SettingsView(preferences: preferences, widgets: widgets) {
                    ShelfSettingsTab(store: shelfStore)
                        .tabItem { Label("Shelf", systemImage: "tray") }
                    NotesSettingsTab(store: notesStore)
                        .tabItem { Label("Notes", systemImage: "note.text") }
                }
            )
        }
        let statusItem = StatusItemController(
            isNotchVisible: { preferences.isNotchVisible },
            onOpenSettings: { settings.show() },
            onToggleNotch: { preferences.isNotchVisible.toggle() }
        )

        notch.onOpenSettings = { settings.show() }
        notch.onAlongOffsetCommitted = { preferences.alongOffset = $0 }
        notch.contextMenuProvider = { statusItem.makeMenu() }

        // Clicking a delivered reminder's notification body opens the widget directly (spec
        // §3.5), the same way a global keyboard shortcut would.
        let notificationDelegate = NotificationDelegate(
            store: remindersStore,
            onOpenReminders: { notch.send(.shortcut(.reminders)) }
        )
        UNUserNotificationCenter.current().delegate = notificationDelegate

        self.preferences = preferences
        self.settings = settings
        self.notch = notch
        self.statusItem = statusItem
        self.shelfStore = shelfStore
        self.notesStore = notesStore
        self.remindersStore = remindersStore
        self.notificationDelegate = notificationDelegate
    }

    func start() {
        statusItem.install()
        notch.start()
        applyReminderSettings()
        observePreferences()
        observeReminderSettings()
        // Spec §4.7: reconcile against the system's actual pending notification requests once at
        // launch, rather than trusting `reminders.json` alone (a crash between saving a reminder
        // and scheduling it, or a stale request left behind, would otherwise go unnoticed).
        Task { await remindersStore.reconcile() }
    }

    func showSettings() {
        settings.show()
    }

    /// Writes any pending content synchronously. Called from `applicationWillTerminate`.
    func flush() {
        shelfStore.flush()
        notesStore.flush()
        remindersStore.flush()
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

    /// `reminders.json`'s URL, with the same temporary-directory fallback as `makeShelfFileURL()`.
    private static func makeRemindersFileURL() -> URL {
        if let url = try? AppPaths.remindersFile() {
            return url
        }
        AppIdentity.current.logger("reminders").error("Falling back to a temporary reminders file: Application Support was unavailable.")
        return FileManager.default.temporaryDirectory.appendingPathComponent("reminders.json")
    }

    /// Pushes every preference change into the notch and `Palette`. `withObservationTracking`
    /// fires once, so it re-registers itself after each change.
    private func observePreferences() {
        withObservationTracking {
            _ = preferences.notchConfiguration
            _ = preferences.accentColor
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                notch.apply(preferences.notchConfiguration)
                Palette.accent = preferences.accentColor.color
                observePreferences()
            }
        }
    }

    /// Pushes the snooze length and chip hours (Settings › Reminders) into `RemindersStore`, which
    /// can't read `Preferences` itself (feature modules never depend on `SettingsFeature`).
    private func applyReminderSettings() {
        remindersStore.snoozeInterval = TimeInterval(preferences.snoozeMinutes * 60)
        remindersStore.tonightHour = preferences.tonightHour
        remindersStore.tomorrowHour = preferences.tomorrowHour
    }

    private func observeReminderSettings() {
        withObservationTracking {
            _ = (preferences.snoozeMinutes, preferences.tonightHour, preferences.tomorrowHour)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                applyReminderSettings()
                observeReminderSettings()
            }
        }
    }
}
