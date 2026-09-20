import SwiftUI
import NotchWidgetAPI

/// The Reminders mini app: write what to be reminded of, pick when, get a macOS notification even
/// if the app isn't running (spec §3.5).
@MainActor
public final class RemindersWidget: NotchWidget {
    public let id: WidgetID = .reminders
    public let title = "Reminders"
    public let systemImage = "bell"
    public let expandedSize = CGSize(width: 320, height: 420)

    private let store: RemindersStore

    public init(store: RemindersStore) {
        self.store = store
    }

    /// A dot while anything is overdue (spec §3.5), cleared the moment it's marked done or
    /// snoozed — `store.overdue` is already recomputed live off the clock, so this never needs
    /// its own timer.
    public var badge: WidgetBadge? {
        store.overdue.isEmpty ? nil : .dot
    }

    public func makeExpandedView(context: WidgetContext) -> AnyView {
        AnyView(RemindersView(store: store, context: context))
    }
}
