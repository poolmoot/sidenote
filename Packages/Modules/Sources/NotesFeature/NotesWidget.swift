import SwiftUI
import NotchWidgetAPI

/// The Notes mini app: a list of freeform notes with tickable checklist lines (spec §3.4).
@MainActor
public final class NotesWidget: NotchWidget {
    public let id: WidgetID = .notes
    public let title = "Notes"
    public let systemImage = "note.text"
    public let expandedSize = CGSize(width: 320, height: 420)

    private let store: NotesStore

    public init(store: NotesStore) {
        self.store = store
    }

    public func makeExpandedView(context: WidgetContext) -> AnyView {
        AnyView(NotesView(store: store, context: context))
    }
}
