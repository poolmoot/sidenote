import SwiftUI
import AppKit
import NotesFeature
import AppInfo

/// Settings › Notes: note count and *Export all notes…* (spec §3.6). Lives in the app target, not
/// `SettingsFeature`, because it needs `NotesStore`/`NotesExport` directly and features never
/// import each other.
struct NotesSettingsTab: View {
    let store: NotesStore

    @State private var exportResultMessage: String?

    var body: some View {
        Form {
            Section("Notes") {
                LabeledContent("Notes", value: "\(store.notes.count)")
                Button("Export All Notes…") {
                    exportAll()
                }
                .disabled(store.notes.isEmpty)
                if let exportResultMessage {
                    Text(exportResultMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func exportAll() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.message = "Choose a folder to export notes into"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let written = NotesExport.exportAll(store.notes, to: url)
        exportResultMessage = written == 1 ? "Exported 1 note." : "Exported \(written) notes."
    }
}
