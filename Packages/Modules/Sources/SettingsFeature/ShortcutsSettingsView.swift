import SwiftUI
import NotchWidgetAPI

/// Settings › Shortcuts: a global shortcut to open each widget, and one to toggle the notch
/// (spec §3.6, §4.8).
struct ShortcutsSettingsView: View {
    let preferences: Preferences
    let widgets: [any NotchWidget]

    /// Which row is actively recording, if any — only one at a time.
    @State private var recordingSlot: ShortcutAssignments.Slot?
    @State private var message: String?

    var body: some View {
        Form {
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Section("Notch") {
                ShortcutRow(
                    title: "Toggle the notch",
                    systemImage: "rectangle.dashed",
                    shortcut: preferences.shortcuts.toggle,
                    isUnavailable: preferences.unavailableShortcuts.contains(.toggle),
                    recordingSlot: $recordingSlot,
                    slot: .toggle,
                    onCapture: { capture($0, to: .toggle) },
                    onReject: { reject($0) },
                    onClear: { preferences.clearShortcut(.toggle) }
                )
            }

            Section("Widgets") {
                ForEach(widgets, id: \.id) { widget in
                    ShortcutRow(
                        title: widget.title,
                        systemImage: widget.systemImage,
                        shortcut: preferences.shortcuts.widgets[widget.id],
                        isUnavailable: preferences.unavailableShortcuts.contains(.widget(widget.id)),
                        recordingSlot: $recordingSlot,
                        slot: .widget(widget.id),
                        onCapture: { capture($0, to: .widget(widget.id)) },
                        onReject: { reject($0) },
                        onClear: { preferences.clearShortcut(.widget(widget.id)) }
                    )
                }
            }
        }
        .formStyle(.grouped)
    }

    private func capture(_ shortcut: KeyShortcut, to slot: ShortcutAssignments.Slot) {
        guard preferences.assignShortcut(shortcut, to: slot) else {
            message = "\(shortcut.displayString) is already assigned to another shortcut."
            return
        }
        message = nil
    }

    /// Same inline banner the conflict path uses — a capture with no modifier keys never reaches
    /// `assignShortcut` at all (rejected inside `ShortcutRecorderNSView`), but the message it
    /// produces belongs in the same place.
    private func reject(_ text: String) {
        message = text
    }
}
