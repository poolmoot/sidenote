import Foundation
import Observation
import NotchKit
import NotchWidgetAPI
import DesignSystem

/// The user's settings, persisted in UserDefaults. Observable, so Settings views bind straight
/// to it and the app can react to changes.
@MainActor
@Observable
public final class Preferences {
    public var edge: NotchEdge {
        didSet { defaults.set(edge.rawValue, forKey: Key.edge) }
    }
    /// nil means "the primary display".
    public var displayID: String? {
        didSet { defaults.set(displayID, forKey: Key.displayID) }
    }
    public var alongOffset: Double {
        didSet { defaults.set(alongOffset, forKey: Key.alongOffset) }
    }
    public var isNotchVisible: Bool {
        didSet { defaults.set(isNotchVisible, forKey: Key.isNotchVisible) }
    }
    /// Hide the folded pill under a full-screen app (spec §3.6 General tab). Off by default — see
    /// `NotchConfiguration.hidesInFullScreen`.
    public var hidesInFullScreen: Bool {
        didSet { defaults.set(hidesInFullScreen, forKey: Key.hidesInFullScreen) }
    }
    /// The enabled widgets, in tile order (spec §3.6 Widgets tab). Every known widget id not
    /// present here simply has no tile; order among the present ones is the tile order.
    public var enabledWidgetIDs: [WidgetID] {
        didSet {
            defaults.set(enabledWidgetIDs.map(\.rawValue), forKey: Key.enabledWidgetIDs)
            // Recorded on every save so a *deliberately* disabled widget (simply absent from the
            // list above) can be told apart, next launch, from a widget that's new to this build
            // and has never had a chance to appear in the list at all — see
            // `resolveEnabledWidgetIDs`.
            defaults.set(Preferences.knownWidgetIDs.map(\.rawValue), forKey: Key.knownWidgetIDsAsOfLastSave)
        }
    }

    // MARK: Appearance (spec §3.6 Appearance tab)

    public var style: NotchStyle {
        didSet { defaults.set(style.rawValue, forKey: Key.style) }
    }
    public var pillSize: PillSize {
        didSet { defaults.set(pillSize.rawValue, forKey: Key.pillSize) }
    }
    public var accentColor: AccentColor {
        didSet {
            guard let data = try? JSONEncoder().encode(accentColor) else { return }
            defaults.set(data, forKey: Key.accentColor)
        }
    }
    /// Seconds, clamped to the spec's 0.05–0.5 s range on every write (including from `init`, so a
    /// stray out-of-range value already on disk can't slip through either).
    public var hoverDelaySeconds: Double {
        get { rawHoverDelaySeconds }
        set { rawHoverDelaySeconds = Preferences.clampHoverDelay(newValue) }
    }
    private var rawHoverDelaySeconds: Double {
        didSet { defaults.set(rawHoverDelaySeconds, forKey: Key.hoverDelaySeconds) }
    }
    public var reduceMotion: ReduceMotionSetting {
        didSet { defaults.set(reduceMotion.rawValue, forKey: Key.reduceMotion) }
    }

    // MARK: Reminders (spec §3.6 Reminders tab)

    /// Minutes, one of 5/10/15/30 (spec §3.6).
    public var snoozeMinutes: Int {
        didSet { defaults.set(snoozeMinutes, forKey: Key.snoozeMinutes) }
    }
    /// The "Tonight" chip's hour, 24-hour clock.
    public var tonightHour: Int {
        didSet { defaults.set(tonightHour, forKey: Key.tonightHour) }
    }
    /// The "Tomorrow" chip's hour, 24-hour clock.
    public var tomorrowHour: Int {
        didSet { defaults.set(tomorrowHour, forKey: Key.tomorrowHour) }
    }

    // MARK: Shortcuts (spec §3.6 Shortcuts tab, §4.8)

    public var shortcuts: ShortcutAssignments {
        didSet {
            guard let data = try? JSONEncoder().encode(shortcuts) else { return }
            defaults.set(data, forKey: Key.shortcuts)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        edge = defaults.string(forKey: Key.edge).flatMap(NotchEdge.init(rawValue:)) ?? .right
        displayID = defaults.string(forKey: Key.displayID)
        alongOffset = defaults.double(forKey: Key.alongOffset)
        isNotchVisible = defaults.object(forKey: Key.isNotchVisible) as? Bool ?? true
        hidesInFullScreen = defaults.object(forKey: Key.hidesInFullScreen) as? Bool ?? false
        let savedWidgetIDs = (defaults.array(forKey: Key.enabledWidgetIDs) as? [String])?.map(WidgetID.init(rawValue:))
        let previouslyKnownIDs = Set((defaults.array(forKey: Key.knownWidgetIDsAsOfLastSave) as? [String] ?? []).map(WidgetID.init(rawValue:)))
        enabledWidgetIDs = Preferences.resolveEnabledWidgetIDs(saved: savedWidgetIDs, previouslyKnown: previouslyKnownIDs)

        style = defaults.string(forKey: Key.style).flatMap(NotchStyle.init(rawValue:)) ?? .solid
        pillSize = defaults.string(forKey: Key.pillSize).flatMap(PillSize.init(rawValue:)) ?? .medium
        if let data = defaults.data(forKey: Key.accentColor), let decoded = try? JSONDecoder().decode(AccentColor.self, from: data) {
            accentColor = decoded
        } else {
            accentColor = .systemBlue
        }
        let savedHoverDelay = defaults.object(forKey: Key.hoverDelaySeconds) as? Double
        rawHoverDelaySeconds = Preferences.clampHoverDelay(savedHoverDelay ?? 0.15)
        reduceMotion = defaults.string(forKey: Key.reduceMotion).flatMap(ReduceMotionSetting.init(rawValue:)) ?? .system

        let savedSnooze = defaults.object(forKey: Key.snoozeMinutes) as? Int
        snoozeMinutes = Preferences.snoozeOptions.contains(savedSnooze ?? -1) ? savedSnooze! : 10
        tonightHour = defaults.object(forKey: Key.tonightHour) as? Int ?? 20
        tomorrowHour = defaults.object(forKey: Key.tomorrowHour) as? Int ?? 9

        if let data = defaults.data(forKey: Key.shortcuts), let decoded = try? JSONDecoder().decode(ShortcutAssignments.self, from: data) {
            shortcuts = decoded
        } else {
            shortcuts = ShortcutAssignments()
        }
    }

    /// Assigns `shortcut` to `slot`, rejecting it if it conflicts with a different slot already
    /// assigned (spec: "conflicts inside the app are rejected with a message"). Returns whether it
    /// was assigned.
    @discardableResult
    public func assignShortcut(_ shortcut: KeyShortcut, to slot: ShortcutAssignments.Slot) -> Bool {
        var updated = shortcuts
        guard updated.assign(shortcut, to: slot) else { return false }
        shortcuts = updated
        return true
    }

    public func clearShortcut(_ slot: ShortcutAssignments.Slot) {
        var updated = shortcuts
        updated.clear(slot)
        shortcuts = updated
    }

    /// What the notch needs from these settings.
    public var notchConfiguration: NotchConfiguration {
        NotchConfiguration(
            edge: edge,
            displayID: displayID,
            alongOffset: alongOffset,
            isVisible: isNotchVisible,
            hidesInFullScreen: hidesInFullScreen,
            hoverDelay: .milliseconds(Int(hoverDelaySeconds * 1000)),
            style: style,
            pillSize: pillSize,
            reduceMotion: reduceMotion,
            enabledWidgetIDs: enabledWidgetIDs
        )
    }

    public func resetPosition() {
        alongOffset = 0
    }

    /// The four snooze lengths Settings › Reminders offers (spec §3.6).
    public static let snoozeOptions = [5, 10, 15, 30]

    static let hoverDelayRange = 0.05...0.5

    static func clampHoverDelay(_ value: Double) -> Double {
        min(max(value, hoverDelayRange.lowerBound), hoverDelayRange.upperBound)
    }

    /// Every widget this build of the app ships, in the default tile order (spec §3.1). The one
    /// place `Preferences` names a widget by id — it can't discover the app's actual widget array
    /// (that would mean depending on the feature modules), so a saved id is considered "known" iff
    /// it's one of these.
    static let knownWidgetIDs: [WidgetID] = [.shelf, .notes, .reminders]

    /// Filters `saved` down to known ids (an id from a widget that no longer exists is dropped,
    /// and a repeat is dropped too), then appends any known widget that's both missing from
    /// `saved` *and* absent from `previouslyKnown` — i.e. one this build knows about that never
    /// had a chance to appear in a saved list, as opposed to one the user deliberately unchecked.
    /// `saved == nil` (nothing saved at all yet) short-circuits to every known widget, enabled, in
    /// the default order.
    static func resolveEnabledWidgetIDs(saved: [WidgetID]?, previouslyKnown: Set<WidgetID> = []) -> [WidgetID] {
        guard let saved else { return knownWidgetIDs }
        var result: [WidgetID] = []
        var seen = Set<WidgetID>()
        for id in saved where knownWidgetIDs.contains(id) && seen.insert(id).inserted {
            result.append(id)
        }
        for id in knownWidgetIDs where !seen.contains(id) && !previouslyKnown.contains(id) {
            result.append(id)
        }
        return result
    }

    enum Key {
        static let edge = "notch.edge"
        static let displayID = "notch.displayID"
        static let alongOffset = "notch.alongOffset"
        static let isNotchVisible = "notch.isVisible"
        static let hidesInFullScreen = "notch.hidesInFullScreen"
        static let enabledWidgetIDs = "notch.enabledWidgetIDs"
        static let knownWidgetIDsAsOfLastSave = "notch.knownWidgetIDsAsOfLastSave"
        static let style = "appearance.style"
        static let pillSize = "appearance.pillSize"
        static let accentColor = "appearance.accentColor"
        static let hoverDelaySeconds = "appearance.hoverDelaySeconds"
        static let reduceMotion = "appearance.reduceMotion"
        static let snoozeMinutes = "reminders.snoozeMinutes"
        static let tonightHour = "reminders.tonightHour"
        static let tomorrowHour = "reminders.tomorrowHour"
        static let shortcuts = "shortcuts.assignments"
    }
}
