import SwiftUI
import NotchWidgetAPI

/// The Shelf mini app: a security-scoped bookmark shelf for files and folders (spec §3.3).
@MainActor
public final class ShelfWidget: NotchWidget {
    public let id: WidgetID = .shelf
    public let title = "Shelf"
    public let systemImage = "tray"
    public let expandedSize = CGSize(width: 320, height: 420)
    public let acceptsFileDrops = true

    private let store: ShelfStore

    public init(store: ShelfStore) {
        self.store = store
    }

    public func makeExpandedView(context: WidgetContext) -> AnyView {
        AnyView(ShelfView(store: store, context: context))
    }

    public func handleFileDrop(_ urls: [URL]) -> Bool {
        store.add(urls: urls) > 0
    }
}
