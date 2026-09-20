import Foundation
import Observation
import NotchKit
import NotchWidgetAPI

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

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        edge = defaults.string(forKey: Key.edge).flatMap(NotchEdge.init(rawValue:)) ?? .right
        displayID = defaults.string(forKey: Key.displayID)
        alongOffset = defaults.double(forKey: Key.alongOffset)
        isNotchVisible = defaults.object(forKey: Key.isNotchVisible) as? Bool ?? true
        let savedWidgetIDs = (defaults.array(forKey: Key.enabledWidgetIDs) as? [String])?.map(WidgetID.init(rawValue:))
        let previouslyKnownIDs = Set((defaults.array(forKey: Key.knownWidgetIDsAsOfLastSave) as? [String] ?? []).map(WidgetID.init(rawValue:)))
        enabledWidgetIDs = Preferences.resolveEnabledWidgetIDs(saved: savedWidgetIDs, previouslyKnown: previouslyKnownIDs)
    }

    /// What the notch needs from these settings.
    public var notchConfiguration: NotchConfiguration {
        NotchConfiguration(
            edge: edge,
            displayID: displayID,
            alongOffset: alongOffset,
            isVisible: isNotchVisible,
            enabledWidgetIDs: enabledWidgetIDs
        )
    }

    public func resetPosition() {
        alongOffset = 0
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
        static let enabledWidgetIDs = "notch.enabledWidgetIDs"
        static let knownWidgetIDsAsOfLastSave = "notch.knownWidgetIDsAsOfLastSave"
    }
}
