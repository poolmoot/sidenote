import Foundation
import Observation
import NotchKit

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

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        edge = defaults.string(forKey: Key.edge).flatMap(NotchEdge.init(rawValue:)) ?? .right
        displayID = defaults.string(forKey: Key.displayID)
        alongOffset = defaults.double(forKey: Key.alongOffset)
        isNotchVisible = defaults.object(forKey: Key.isNotchVisible) as? Bool ?? true
    }

    /// What the notch needs from these settings.
    public var notchConfiguration: NotchConfiguration {
        NotchConfiguration(edge: edge, displayID: displayID, alongOffset: alongOffset, isVisible: isNotchVisible)
    }

    public func resetPosition() {
        alongOffset = 0
    }

    enum Key {
        static let edge = "notch.edge"
        static let displayID = "notch.displayID"
        static let alongOffset = "notch.alongOffset"
        static let isNotchVisible = "notch.isVisible"
    }
}
