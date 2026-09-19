import AppKit
import SwiftUI

/// Wraps an AppKit drag source over a SwiftUI cell, so dragging a shelf item out always *copies*
/// the original rather than moving or aliasing it.
///
/// SwiftUI's `.onDrag` can't restrict which operation a drop target is offered — the destination
/// decides — so this drops down to `NSDraggingSource`, whose `sourceOperationMaskFor` pins the
/// mask to `.copy` in every context. It also does its own mouse-down tracking to tell a plain
/// click from the start of a drag, the same way Finder icons do, so `onClick` still fires for a
/// click that never turns into a drag.
struct FileDragSource: NSViewRepresentable {
    /// Resolves the files this cell (or its whole selection) would drag, called only once a
    /// real drag actually starts — never during view rendering, since resolving a shelf item's
    /// URL can refresh and persist its bookmark.
    let urlsProvider: () -> [URL]
    let onClick: (_ isCommandDown: Bool) -> Void
    /// Called once a real drag session ends. `true` means some operation other than `[]` was
    /// performed — i.e. the drag wasn't cancelled or rejected.
    let onDragFinished: (Bool) -> Void

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: DragSourceView) {
        view.urlsProvider = urlsProvider
        view.onClick = onClick
        view.onDragFinished = onDragFinished
    }
}

/// A transparent view that turns a mouse-down-and-move into an `.copy`-only drag session, or a
/// mouse-down-and-up with no meaningful movement into a click.
final class DragSourceView: NSView, NSDraggingSource {
    var urlsProvider: (() -> [URL])?
    var onClick: ((Bool) -> Void)?
    var onDragFinished: ((Bool) -> Void)?

    /// How far the pointer must move, in points, before a mouse-down becomes a drag.
    private let dragThreshold: CGFloat = 4

    override func mouseDown(with event: NSEvent) {
        let downLocation = event.locationInWindow
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            switch next.type {
            case .leftMouseUp:
                onClick?(next.modifierFlags.contains(.command))
                return
            case .leftMouseDragged:
                let distance = hypot(next.locationInWindow.x - downLocation.x, next.locationInWindow.y - downLocation.y)
                guard distance > dragThreshold else { continue }
                let urls = urlsProvider?() ?? []
                guard !urls.isEmpty else { continue }
                beginDrag(with: next, urls: urls)
                return
            default:
                continue
            }
        }
    }

    private func beginDrag(with event: NSEvent, urls: [URL]) {
        let items = urls.map { url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(bounds, contents: nil)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragFinished?(operation != [])
    }
}
