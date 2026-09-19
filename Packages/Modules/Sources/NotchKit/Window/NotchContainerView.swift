import AppKit
import SwiftUI

/// The panel's content view. It owns everything that decides *where* the notch is live:
/// hit testing, hover tracking and file drops, all limited to `hotRect`. Outside it the panel is
/// a hole that clicks fall through.
///
/// Hover comes from a single `NSTrackingArea` — no cursor polling, no global event monitors — so
/// the notch costs nothing while the pointer is elsewhere.
final class NotchContainerView: NSView {
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?
    var onFileDragEntered: (() -> Void)?
    var onFileDragExited: (() -> Void)?
    /// Called for every drop that carries file URLs. The owner must end its drop-target state
    /// whether or not it accepts the files.
    var onFileDrop: (([URL]) -> Bool)?

    private(set) var hotRect: CGRect = .zero
    private(set) var isPointerInside = false
    private var isDragInside = false
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Moves the live region. Re-checks where the pointer is on the next run-loop turn, because a
    /// tracking area replaced while the pointer is already outside it never reports an exit.
    func setHotRect(_ rect: CGRect) {
        guard rect != hotRect else { return }
        hotRect = rect
        updateTrackingAreas()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.syncPointer() }
        }
    }

    /// Brings `isPointerInside` in line with where the pointer really is.
    func syncPointer() {
        guard let window else { return }
        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setPointerInside(hotRect.contains(location))
    }

    // MARK: Hit testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard hotRect.contains(local) else { return nil }
        return super.hitTest(point)
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: hotRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { setPointerInside(true) }
    override func mouseExited(with event: NSEvent) { setPointerInside(false) }

    private func setPointerInside(_ inside: Bool) {
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        if inside { onPointerEntered?() } else { onPointerExited?() }
    }

    // MARK: File drops

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource == nil else { return [] }
        return draggingUpdated(sender)
    }

    /// `draggingSource` is only non-nil when the drag originated inside this process — AppKit
    /// never hands back the source object across a process boundary — so this is exactly how to
    /// tell the shelf's own drag-out apart from a real incoming drop from Finder or another app.
    /// Treating it as "not a drop target" here means it never shows "Drop here" or forces a fold
    /// mid-drag (the widget already knows what it's dragging and ends the session itself).
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingSource == nil else { return [] }
        let location = convert(sender.draggingLocation, from: nil)
        let inside = hotRect.contains(location) && Self.hasFileURLs(sender.draggingPasteboard)
        if inside != isDragInside {
            isDragInside = inside
            if inside { onFileDragEntered?() } else { onFileDragExited?() }
        }
        return inside ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        guard sender?.draggingSource == nil else { return }
        guard isDragInside else { return }
        isDragInside = false
        onFileDragExited?()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard sender.draggingSource == nil else { return false }
        isDragInside = false
        let urls = Self.fileURLs(sender.draggingPasteboard)
        guard !urls.isEmpty else {
            onFileDragExited?()
            // AppKit only calls concludeDragOperation (which re-syncs the pointer) when this
            // method returns true, so a rejected drop must schedule its own re-sync.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.syncPointer() }
            }
            return false
        }
        let accepted = onFileDrop?(urls) ?? false
        if !accepted {
            // Same reasoning: concludeDragOperation never runs for a rejected drop.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.syncPointer() }
            }
        }
        return accepted
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        // A drag suppresses tracking events, so re-learn where the pointer is.
        syncPointer()
    }

    private static let fileURLOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]

    private static func hasFileURLs(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: fileURLOptions)
    }

    static func fileURLs(_ pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: fileURLOptions) as? [URL]) ?? []
    }
}

/// Hosts the SwiftUI notch. Accepts the first click so tiles respond even though the panel is
/// never the key window while they are showing.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
