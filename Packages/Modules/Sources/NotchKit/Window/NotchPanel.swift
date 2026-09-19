import AppKit

/// A borderless, non-activating panel that stays above everything else, full-screen apps
/// included. "Non-activating" is the load-bearing part: showing the notch must never steal focus
/// from whatever app the user is currently in.
final class NotchPanel: NSPanel {
    /// Set only while a widget is expanded — the folded pill and the tile column never take the
    /// keyboard.
    var allowsKey = false
    var contextMenuProvider: (() -> NSMenu?)?
    var onEscape: (() -> Void)?
    var onResignKey: (() -> Void)?
    /// Reports an ⌥-drag along the edge as raw pointer deltas; a positive `deltaY` moves downward.
    var onDragStart: (() -> Void)?
    var onDrag: ((CGFloat, CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    /// Intercepted here instead of in a view: `sendEvent` sees every event before hit-testing
    /// does, whereas a SwiftUI subview that swallows the event would never let us react to it.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53, !firstResponderIsComposingText { // Escape
            onEscape?()
            return
        }
        if event.type == .rightMouseDown, isOverChrome(event) {
            if let menu = contextMenuProvider?(), let view = contentView {
                NSMenu.popUpContextMenu(menu, with: event, for: view)
                return
            }
        }
        if event.type == .leftMouseDown,
           event.modifierFlags.contains(.option),
           onDrag != nil,
           isOverChrome(event) {
            onDragStart?()
            trackOptionDrag()
            return
        }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    /// Hands the keyboard back to whichever app previously held it. A window only stops being key
    /// once it leaves the screen, so this orders the panel out and immediately back in — losing
    /// key status without the notch ever disappearing.
    func relinquishKey() {
        allowsKey = false
        guard isKeyWindow else { return }
        orderOut(nil)
        orderFrontRegardless()
    }

    /// Whether `event`'s location falls on visible chrome rather than the transparent, click-
    /// through margin around it.
    private func isOverChrome(_ event: NSEvent) -> Bool {
        guard let view = contentView else { return false }
        return view.hitTest(event.locationInWindow) != nil
    }

    /// Whether the first responder is an `NSTextView` mid-composition with an input method (spec
    /// §12 risk: typing Japanese/Chinese leaves an uncommitted candidate string marked via
    /// `hasMarkedText()`). Escape's usual job there is to cancel that composition, not fold the
    /// notch — intercepting it first would discard the user's in-progress input, so this case is
    /// let fall through to `super.sendEvent`, which delivers it to the text view as normal.
    private var firstResponderIsComposingText: Bool {
        guard let textView = firstResponder as? NSTextView else { return false }
        return textView.hasMarkedText()
    }

    /// Pumps this window's own event queue until the mouse button lifts. This is the standard
    /// AppKit idiom for tracking a drag that began on mouse-down, rather than waiting for
    /// `mouseDragged` callbacks to arrive through the responder chain.
    private func trackOptionDrag() {
        while let event = nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            guard event.type != .leftMouseUp else {
                onDragEnd?()
                return
            }
            onDrag?(event.deltaX, event.deltaY)
        }
    }
}
