import AppKit
import SwiftUI

/// Wraps an AppKit drag source over a SwiftUI cell, so dragging a shelf item out always *copies*
/// the original rather than moving or aliasing it.
///
/// SwiftUI's `.onDrag` can't restrict which operation a drop target is offered — the destination
/// decides — so this drops down to `NSDraggingSource`, whose `sourceOperationMaskFor` pins the
/// mask to `.copy` in every context. It also does its own mouse-down tracking to tell a plain
/// click from the start of a drag, the same way Finder icons do, so `onClick` still fires for a
/// click that never turns into a drag; and it owns Space-to-Quick-Look, since a click here (an
/// `NSView`) never gives a sibling SwiftUI `.focusable()` real keyboard focus.
struct FileDragSource: NSViewRepresentable {
    /// Resolves the (id, url) pairs this cell (or its whole selection) would drag, called only
    /// once — right when a real drag starts, never during view rendering (resolving a shelf
    /// item's URL can refresh and persist its bookmark) and never repeated while tracking a drag
    /// that turned out to have nothing to drag.
    let itemsProvider: () -> [(id: ShelfItem.ID, url: URL)]
    let onClick: (_ isCommandDown: Bool) -> Void
    /// Called once a real drag actually begins (past the movement threshold, with something to
    /// drag). The notch is held open (`context.setEditing(true)`) for as long as the drag lasts.
    let onDragStarted: () -> Void
    /// Called once a real drag session ends, with exactly the ids that were dragged (never more
    /// than what `itemsProvider` returned at drag start, so a missing selected item is never
    /// reported as consumed) and whether some operation other than `[]` was performed.
    let onDragFinished: (_ draggedIDs: Set<ShelfItem.ID>, _ performed: Bool) -> Void
    /// The user pressed Space while this cell was the one last interacted with.
    let onSpacePressed: () -> Void

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: DragSourceView) {
        view.itemsProvider = itemsProvider
        view.onClick = onClick
        view.onDragStarted = onDragStarted
        view.onDragFinished = onDragFinished
        view.onSpacePressed = onSpacePressed
    }
}

/// A transparent view that turns a mouse-down-and-move into a `.copy`-only drag session, or a
/// mouse-down-and-up with no meaningful movement into a click.
final class DragSourceView: NSView, NSDraggingSource {
    var itemsProvider: (() -> [(id: ShelfItem.ID, url: URL)])?
    var onClick: ((Bool) -> Void)?
    var onDragStarted: (() -> Void)?
    var onDragFinished: ((Set<ShelfItem.ID>, Bool) -> Void)?
    var onSpacePressed: (() -> Void)?

    /// How far the pointer must move, in points, before a mouse-down becomes a drag.
    private let dragThreshold: CGFloat = 4

    private var draggedIDs: Set<ShelfItem.ID> = []
    /// URLs whose security scope this view opened for the in-flight drag, so it can close exactly
    /// those (and only those that actually started) when the session ends.
    private var accessedURLs: [URL] = []

    override var acceptsFirstResponder: Bool { true }

    /// The notch's panel only becomes key when a view inside it asks to (spec §4.3's
    /// activation-agnostic hover/tiles/expanded flow means the panel doesn't grab key on its
    /// own — see `NotchController`'s `.fileDragEntered` case, which opens the shelf without
    /// `.makeKey`). Without this, a shelf opened by a file drag never becomes key, so this view
    /// never becomes first responder and Space never reaches `keyDown`.
    override var needsPanelToBecomeKey: Bool { true }

    /// Lets a single click both act on an item *and* focus it for Quick Look, even when the
    /// panel wasn't key yet (e.g. it was opened by a file drag rather than a click).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let downLocation = event.locationInWindow
        // Once a drag attempt turns out to have nothing to drag (e.g. every selected item became
        // unresolvable between mouse-down and the movement threshold), the whole gesture is void:
        // no drag begins, the eventual mouse-up isn't a click either, and `itemsProvider` isn't
        // asked again for the rest of this mouse-down.
        var isVoided = false
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            switch next.type {
            case .leftMouseUp:
                if !isVoided {
                    onClick?(next.modifierFlags.contains(.command))
                }
                return
            case .leftMouseDragged:
                guard !isVoided else { continue }
                let distance = hypot(next.locationInWindow.x - downLocation.x, next.locationInWindow.y - downLocation.y)
                guard distance > dragThreshold else { continue }
                let items = itemsProvider?() ?? []
                guard !items.isEmpty else {
                    isVoided = true
                    continue
                }
                beginDrag(with: next, items: items)
                return
            default:
                continue
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        guard event.charactersIgnoringModifiers == " " else {
            super.keyDown(with: event)
            return
        }
        onSpacePressed?()
    }

    private func beginDrag(with event: NSEvent, items: [(id: ShelfItem.ID, url: URL)]) {
        let draggingItems = items.map { pair -> NSDraggingItem in
            let draggingItem = NSDraggingItem(pasteboardWriter: pair.url as NSURL)
            draggingItem.setDraggingFrame(bounds, contents: nil)
            return draggingItem
        }
        draggedIDs = Set(items.map(\.id))
        accessedURLs = items.map(\.url).filter { $0.startAccessingSecurityScopedResource() }
        onDragStarted?()
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        for url in accessedURLs { url.stopAccessingSecurityScopedResource() }
        accessedURLs = []
        let ids = draggedIDs
        draggedIDs = []
        onDragFinished?(ids, operation != [])
    }
}
