import Foundation
import Testing
import NotchKit
import NotchWidgetAPI
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

    @Test func defaultsWhenNothingSaved() {
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.edge == .right)
        #expect(preferences.displayID == nil)
        #expect(preferences.alongOffset == 0)
        #expect(preferences.isNotchVisible)
        #expect(preferences.enabledWidgetIDs == [.shelf, .notes, .reminders])
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
        let first = Preferences(defaults: defaults)
        first.enabledWidgetIDs = [.reminders, .shelf]

        let second = Preferences(defaults: defaults)
        #expect(second.enabledWidgetIDs == [.reminders, .shelf])
    }

    @Test func unknownSavedWidgetIDsAreDropped() {
        defaults.set(["shelf", "some-removed-widget", "notes"], forKey: Preferences.Key.enabledWidgetIDs)
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.enabledWidgetIDs == [.shelf, .notes, .reminders])
    }

    @Test func aNewlyRegisteredWidgetIsAppendedAtTheEnd() {
        defaults.set(["reminders", "shelf"], forKey: Preferences.Key.enabledWidgetIDs)
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.enabledWidgetIDs == [.reminders, .shelf, .notes])
    }

    @Test func duplicateSavedIDsAreDeduplicated() {
        defaults.set(["shelf", "shelf", "notes"], forKey: Preferences.Key.enabledWidgetIDs)
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.enabledWidgetIDs == [.shelf, .notes, .reminders])
    }

    @Test func mapsEnabledWidgetIDsToNotchConfiguration() {
        let preferences = Preferences(defaults: defaults)
        preferences.enabledWidgetIDs = [.notes]
        #expect(preferences.notchConfiguration.enabledWidgetIDs == [.notes])
    }
}
