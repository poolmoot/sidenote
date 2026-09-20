import Foundation
import Testing
import NotchKit
import NotchWidgetAPI
import DesignSystem
@testable import SettingsFeature

@MainActor
final class PreferencesTests {
    let defaults: UserDefaults
    nonisolated let suiteName: String

    init() {
        suiteName = "PreferencesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// The three widgets this app ships, matching what `AppEnvironment` would actually pass in —
    /// tests that don't care about widget-specific behaviour just use `Preferences(defaults:)` and
    /// get an (intentionally) empty `knownWidgetIDs`.
    private static let allWidgetIDs: [WidgetID] = [.shelf, .notes, .reminders]

    private func makePreferences(knownWidgetIDs: [WidgetID] = allWidgetIDs) -> Preferences {
        Preferences(defaults: defaults, knownWidgetIDs: knownWidgetIDs)
    }

    @Test func defaultsWhenNothingSaved() {
        let preferences = makePreferences()
        #expect(preferences.edge == .right)
        #expect(preferences.displayID == nil)
        #expect(preferences.alongOffset == 0)
        #expect(preferences.isNotchVisible)
        #expect(preferences.enabledWidgetIDs == [.shelf, .notes, .reminders])
    }

    @Test func knownWidgetIDsDefaultsToEmptyWhenNotProvided() {
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.enabledWidgetIDs.isEmpty)
    }

    @Test func changesPersistAcrossInstances() {
        let first = Preferences(defaults: defaults)
        first.edge = .left
        first.displayID = "DISPLAY-UUID"
        first.alongOffset = -120
        first.isNotchVisible = false

        let second = Preferences(defaults: defaults)
        #expect(second.edge == .left)
        #expect(second.displayID == "DISPLAY-UUID")
        #expect(second.alongOffset == -120)
        #expect(!second.isNotchVisible)
    }

    @Test func clearingDisplayFallsBackToPrimary() {
        let first = Preferences(defaults: defaults)
        first.displayID = "DISPLAY-UUID"
        first.displayID = nil
        #expect(Preferences(defaults: defaults).displayID == nil)
    }

    @Test func unknownSavedEdgeFallsBackToRight() {
        defaults.set("top", forKey: Preferences.Key.edge)
        #expect(Preferences(defaults: defaults).edge == .right)
    }

    @Test func mapsToNotchConfiguration() {
        let preferences = Preferences(defaults: defaults)
        preferences.edge = .left
        preferences.alongOffset = 40
        let configuration = preferences.notchConfiguration
        #expect(configuration.edge == .left)
        #expect(configuration.alongOffset == 40)
        #expect(configuration.isVisible)
    }

    @Test func resetPositionZeroesOffset() {
        let preferences = Preferences(defaults: defaults)
        preferences.alongOffset = 200
        preferences.resetPosition()
        #expect(preferences.alongOffset == 0)
    }

    // MARK: enabledWidgetIDs (spec §3.6 Widgets tab)

    @Test func enabledWidgetOrderPersistsAcrossInstances() {
        let first = makePreferences()
        first.enabledWidgetIDs = [.reminders, .shelf]

        let second = makePreferences()
        #expect(second.enabledWidgetIDs == [.reminders, .shelf])
    }

    /// Owner-ruling regression (post-review): a widget the user deliberately turned off must stay
    /// off across a relaunch — it must never be silently re-appended as though it were newly
    /// added to the app.
    @Test func aDeliberatelyDisabledWidgetStaysDisabledAcrossARelaunch() {
        let first = makePreferences()
        first.enabledWidgetIDs = [.shelf, .reminders] // Notes turned off.

        let second = makePreferences()
        #expect(second.enabledWidgetIDs == [.shelf, .reminders])
        #expect(!second.enabledWidgetIDs.contains(.notes))
    }

    @Test func unknownSavedWidgetIDsAreDropped() {
        defaults.set(["shelf", "some-removed-widget", "notes"], forKey: Preferences.Key.enabledWidgetIDs)
        let preferences = makePreferences()
        #expect(preferences.enabledWidgetIDs == [.shelf, .notes, .reminders])
    }

    @Test func aNewlyRegisteredWidgetIsAppendedAtTheEnd() {
        defaults.set(["reminders", "shelf"], forKey: Preferences.Key.enabledWidgetIDs)
        let preferences = makePreferences()
        #expect(preferences.enabledWidgetIDs == [.reminders, .shelf, .notes])
    }

    @Test func duplicateSavedIDsAreDeduplicated() {
        defaults.set(["shelf", "shelf", "notes"], forKey: Preferences.Key.enabledWidgetIDs)
        let preferences = makePreferences()
        #expect(preferences.enabledWidgetIDs == [.shelf, .notes, .reminders])
    }

    @Test func mapsEnabledWidgetIDsToNotchConfiguration() {
        let preferences = makePreferences()
        preferences.enabledWidgetIDs = [.notes]
        #expect(preferences.notchConfiguration.enabledWidgetIDs == [.notes])
    }

    // MARK: resolveEnabledWidgetIDs (pure static logic, tested directly)

    @Test func resolveDropsUnknownAppendsNewAndKeepsADisabledWidgetDisabled() {
        // Shelf and Notes were known as of the last save; the user disabled Notes (it's simply
        // absent from `saved`). Reminders is new to this build — it was never in `previouslyKnown`
        // — so it must append, while Notes must NOT come back.
        let result = Preferences.resolveEnabledWidgetIDs(
            saved: [.shelf],
            knownWidgetIDs: [.shelf, .notes, .reminders],
            previouslyKnown: [.shelf, .notes]
        )
        #expect(result == [.shelf, .reminders])
    }

    @Test func resolveWithNothingSavedEnablesEveryKnownWidgetInOrder() {
        let result = Preferences.resolveEnabledWidgetIDs(saved: nil, knownWidgetIDs: [.notes, .shelf, .reminders])
        #expect(result == [.notes, .shelf, .reminders])
    }

    // MARK: Appearance (spec §3.6 Appearance tab)

    @Test func appearanceDefaults() {
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.style == .solid)
        #expect(preferences.pillSize == .medium)
        #expect(preferences.accentColor == .systemBlue)
        #expect(preferences.hoverDelaySeconds == 0.15)
        #expect(preferences.reduceMotion == .system)
        #expect(!preferences.hidesInFullScreen)
    }

    @Test func appearanceSettingsPersistAcrossInstances() {
        let first = Preferences(defaults: defaults)
        first.style = .liquidGlass
        first.pillSize = .large
        first.accentColor = AccentColor(red: 1, green: 0, blue: 0)
        first.hoverDelaySeconds = 0.3
        first.reduceMotion = .always
        first.hidesInFullScreen = true

        let second = Preferences(defaults: defaults)
        #expect(second.style == .liquidGlass)
        #expect(second.pillSize == .large)
        #expect(second.accentColor == AccentColor(red: 1, green: 0, blue: 0))
        #expect(second.hoverDelaySeconds == 0.3)
        #expect(second.reduceMotion == .always)
        #expect(second.hidesInFullScreen)
    }

    @Test func hoverDelayIsClampedToTheSpecRange() {
        let preferences = Preferences(defaults: defaults)
        preferences.hoverDelaySeconds = 10
        #expect(preferences.hoverDelaySeconds == 0.5)
        preferences.hoverDelaySeconds = -1
        #expect(preferences.hoverDelaySeconds == 0.05)
    }

    @Test func aStaleOutOfRangeSavedHoverDelayIsClampedOnLoad() {
        defaults.set(99.0, forKey: Preferences.Key.hoverDelaySeconds)
        #expect(Preferences(defaults: defaults).hoverDelaySeconds == 0.5)
    }

    @Test func unknownSavedStyleAndPillSizeFallBackToDefaults() {
        defaults.set("neon", forKey: Preferences.Key.style)
        defaults.set("xl", forKey: Preferences.Key.pillSize)
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.style == .solid)
        #expect(preferences.pillSize == .medium)
    }

    @Test func mapsAppearanceToNotchConfiguration() {
        let preferences = Preferences(defaults: defaults)
        preferences.style = .liquidGlass
        preferences.pillSize = .small
        preferences.reduceMotion = .never
        preferences.hidesInFullScreen = true
        let configuration = preferences.notchConfiguration
        #expect(configuration.style == .liquidGlass)
        #expect(configuration.pillSize == .small)
        #expect(configuration.reduceMotion == .never)
        #expect(configuration.hidesInFullScreen)
    }

    // MARK: Reminders (spec §3.6 Reminders tab)

    @Test func reminderSettingDefaults() {
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.snoozeMinutes == 10)
        #expect(preferences.tonightHour == 20)
        #expect(preferences.tomorrowHour == 9)
    }

    @Test func reminderSettingsPersistAcrossInstances() {
        let first = Preferences(defaults: defaults)
        first.snoozeMinutes = 30
        first.tonightHour = 22
        first.tomorrowHour = 7

        let second = Preferences(defaults: defaults)
        #expect(second.snoozeMinutes == 30)
        #expect(second.tonightHour == 22)
        #expect(second.tomorrowHour == 7)
    }

    @Test func aStaleInvalidSnoozeLengthFallsBackToTenMinutes() {
        defaults.set(7, forKey: Preferences.Key.snoozeMinutes)
        #expect(Preferences(defaults: defaults).snoozeMinutes == 10)
    }

    // MARK: Shortcuts (spec §3.6 Shortcuts tab)

    @Test func shortcutsDefaultToNoneAssigned() {
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.shortcuts == ShortcutAssignments())
    }

    @Test func assigningAShortcutPersistsAcrossInstances() {
        let first = Preferences(defaults: defaults)
        let shortcut = KeyShortcut(keyCode: 15, modifiers: 256)
        #expect(first.assignShortcut(shortcut, to: .widget(.reminders)))

        let second = Preferences(defaults: defaults)
        #expect(second.shortcuts.shortcut(for: .widget(.reminders)) == shortcut)
    }

    @Test func assigningAConflictingShortcutIsRejectedAndLeavesTheExistingOneInPlace() {
        let preferences = Preferences(defaults: defaults)
        let shortcut = KeyShortcut(keyCode: 15, modifiers: 256)
        preferences.assignShortcut(shortcut, to: .widget(.reminders))

        let succeeded = preferences.assignShortcut(shortcut, to: .widget(.notes))

        #expect(!succeeded)
        #expect(preferences.shortcuts.shortcut(for: .widget(.notes)) == nil)
        #expect(preferences.shortcuts.shortcut(for: .widget(.reminders)) == shortcut)
    }

    @Test func clearingAShortcutPersists() {
        let first = Preferences(defaults: defaults)
        let shortcut = KeyShortcut(keyCode: 15, modifiers: 256)
        first.assignShortcut(shortcut, to: .toggle)
        first.clearShortcut(.toggle)

        let second = Preferences(defaults: defaults)
        #expect(second.shortcuts.toggle == nil)
    }

    @Test func unavailableShortcutsDefaultsToEmptyAndIsNotPersisted() {
        let first = Preferences(defaults: defaults)
        first.unavailableShortcuts = [.toggle]

        let second = Preferences(defaults: defaults)
        #expect(second.unavailableShortcuts.isEmpty)
    }
}
