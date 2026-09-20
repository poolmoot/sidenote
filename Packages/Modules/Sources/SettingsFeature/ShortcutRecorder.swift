import AppKit
import SwiftUI

/// Captures the next key press while it has focus, so a shortcut can be recorded without an
/// `NSEvent` monitor (global or local) — this codebase avoids both everywhere; see `AGENTS.md`'s
/// no-polling rule and the grep check in `docs/architecture.md`. Ordinary `NSResponder` overrides
/// on a first-responder view are the standard way to do this instead.
final class ShortcutRecorderNSView: NSView {
    /// Mirrors the SwiftUI `isRecording` binding, kept current by `updateNSView` on every body
    /// evaluation — not just set once at construction (fixed post-review). `keyDown`/
    /// `performKeyEquivalent` both gate on this: false here means "ignore whatever key just
    /// arrived", which is what stops this view from re-recording every later keystroke once a
    /// shortcut (or Settings' own ⌘W/⌘,/⌘C/⌘V) has already been captured once.
    var isRecording = false
    var onCapture: ((KeyShortcut) -> Void)?
    /// A capture that isn't a valid shortcut on its own — no modifier held (fixed post-review: this
    /// used to be accepted and handed to `RegisterEventHotKey`, which then hijacks that bare key
    /// system-wide). Carries a message for the same inline banner the conflict path already shows.
    var onReject: ((String) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 { // Escape cancels recording without assigning anything.
            onCancel?()
            return
        }
        // A bare modifier key (⌘/⌥/⌃/⇧ pressed and released on its own) normally arrives via
        // `flagsChanged`, never `keyDown` — this is a defensive second guard against treating one
        // as a captured key, in case some future macOS routes it here instead.
        guard !Self.modifierOnlyKeyCodes.contains(event.keyCode) else { return }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !modifiers.isEmpty else {
            onReject?("Shortcuts need at least one modifier key (⌃, ⌥, ⇧ or ⌘).")
            return
        }
        onCapture?(KeyShortcut(keyCode: event.keyCode, modifiers: modifiers.rawValue))
    }

    // A bare NSResponder normally lets Cocoa route arrow keys, tab, etc. to interface navigation
    // instead of `keyDown` — this recorder wants every key while it's active, shortcuts included.
    // Gated the same way `keyDown` is (fixed post-review): without `isRecording` and an actual
    // first-responder check, this intercepted ⌘W/⌘Q/⌘,/⌘C/⌘V globally across the whole Settings
    // window, for all four-plus recorder rows simultaneously, whether or not any of them was
    // actually the one recording.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else { return false }
        keyDown(with: event)
        return true
    }

    /// Virtual key codes for the four modifier keys (each side) plus Caps Lock and Fn/Globe.
    private static let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
}

/// The `NSViewRepresentable` wrapper: becomes first responder exactly while `isRecording` is true,
/// hands it back to the window's content view the moment recording stops.
struct ShortcutRecorderRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (KeyShortcut) -> Void
    let onReject: (String) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        ShortcutRecorderNSView(frame: .zero)
    }

    /// Refreshes the closures and `isRecording` on every call (fixed post-review: previously only
    /// set once in `makeNSView`, so the view kept calling whichever closures happened to be
    /// current the first time SwiftUI built it). Responder-chain changes are dispatched onto the
    /// next run-loop turn rather than made here directly, since mutating first-responder state
    /// from inside a view-update pass is exactly the kind of thing SwiftUI warns against.
    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.isRecording = isRecording
        nsView.onCapture = { shortcut in
            isRecording = false
            onCapture(shortcut)
        }
        nsView.onReject = { message in
            isRecording = false
            onReject(message)
        }
        nsView.onCancel = { isRecording = false }

        let wantsRecording = isRecording
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView, let window = nsView.window else { return }
            if wantsRecording {
                guard window.firstResponder !== nsView else { return }
                window.makeFirstResponder(nsView)
            } else {
                guard window.firstResponder === nsView else { return }
                window.makeFirstResponder(window.contentView)
            }
        }
    }
}

/// One shortcut row: a label, the current shortcut (or "None"), a record button and a clear
/// button (spec §3.6 Shortcuts tab).
struct ShortcutRow: View {
    let title: String
    let systemImage: String
    let shortcut: KeyShortcut?
    /// Whether Carbon actually managed to register this shortcut — set by `AppEnvironment` after
    /// `ShortcutCenter.apply(_:...)` reports which slots failed (e.g. already owned by macOS).
    let isUnavailable: Bool
    /// `nil` while nothing is being recorded for *any* row — only one row records at a time.
    @Binding var recordingSlot: ShortcutAssignments.Slot?
    let slot: ShortcutAssignments.Slot
    let onCapture: (KeyShortcut) -> Void
    let onReject: (String) -> Void
    let onClear: () -> Void

    private var isRecording: Bool { recordingSlot == slot }

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if isUnavailable, !isRecording {
                Text("Unavailable")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text(isRecording ? "Press a key…" : (shortcut?.displayString ?? "None"))
                .foregroundStyle(.secondary)
                .frame(minWidth: 90, alignment: .trailing)
            Button(isRecording ? "Cancel" : "Record") {
                recordingSlot = isRecording ? nil : slot
            }
            .buttonStyle(.bordered)
            Button("Clear", action: onClear)
                .buttonStyle(.bordered)
                .disabled(shortcut == nil)
        }
        .background(
            ShortcutRecorderRepresentable(
                isRecording: Binding(
                    get: { isRecording },
                    set: { recordingSlot = $0 ? slot : nil }
                ),
                onCapture: onCapture,
                onReject: onReject
            )
            .frame(width: 0, height: 0)
        )
    }
}
