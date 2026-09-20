import AppKit
import SwiftUI

/// Captures the next key press while it has focus, so a shortcut can be recorded without an
/// `NSEvent` monitor (global or local) — this codebase avoids both everywhere; see `AGENTS.md`'s
/// no-polling rule and the grep check in `docs/architecture.md`. Ordinary `NSResponder` overrides
/// on a first-responder view are the standard way to do this instead.
private final class ShortcutRecorderNSView: NSView {
    var onCapture: ((KeyShortcut) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape cancels recording without assigning anything.
            onCancel?()
            return
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        onCapture?(KeyShortcut(keyCode: event.keyCode, modifiers: modifiers.rawValue))
    }

    // A bare NSResponder normally lets Cocoa route arrow keys, tab, etc. to interface navigation
    // instead of `keyDown` — this recorder wants every key while it's active, shortcuts included.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        keyDown(with: event)
        return true
    }
}

/// The `NSViewRepresentable` wrapper: becomes first responder exactly while `isRecording` is true,
/// so `SettingsFeature`'s recorder button can start/stop it without any bookkeeping of its own.
private struct ShortcutRecorderRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (KeyShortcut) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ShortcutRecorderNSView(frame: .zero)
        view.onCapture = { shortcut in
            isRecording = false
            onCapture(shortcut)
        }
        view.onCancel = { isRecording = false }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard isRecording, let window = nsView.window, window.firstResponder !== nsView else { return }
        window.makeFirstResponder(nsView)
    }
}

/// One shortcut row: a label, the current shortcut (or "None"), a record button and a clear
/// button (spec §3.6 Shortcuts tab).
struct ShortcutRow: View {
    let title: String
    let systemImage: String
    let shortcut: KeyShortcut?
    /// `nil` while nothing is being recorded for *any* row — only one row records at a time.
    @Binding var recordingSlot: ShortcutAssignments.Slot?
    let slot: ShortcutAssignments.Slot
    let onCapture: (KeyShortcut) -> Void
    let onClear: () -> Void

    private var isRecording: Bool { recordingSlot == slot }

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
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
                onCapture: onCapture
            )
            .frame(width: 0, height: 0)
        )
    }
}
