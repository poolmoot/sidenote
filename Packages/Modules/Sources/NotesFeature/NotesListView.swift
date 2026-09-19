import SwiftUI
import NotchWidgetAPI
import DesignSystem

/// The Notes widget's root view: the list of notes, or — while one is open — its editor. Spec
/// §3.4.
struct NotesView: View {
    let store: NotesStore
    let context: WidgetContext

    @State private var openNoteID: UUID?

    var body: some View {
        Group {
            if let openNoteID, store.notes.contains(where: { $0.id == openNoteID }) {
                NoteEditorView(noteID: openNoteID, store: store, context: context, onBack: { self.openNoteID = nil })
            } else {
                listContent
            }
        }
        // Spec §4.5: written on fold, not just at app termination. Undo is single-level and does
        // not reach back past the last time the widget was open (spec §3.4).
        .onDisappear {
            store.clearUndo()
            store.flush()
        }
    }

    private var listContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if store.notes.isEmpty {
                emptyState
            } else {
                rows
            }
        }
        // ⌘Z needs a responder somewhere in the tree even though nothing is focused while
        // browsing the list; a zero-opacity button carrying the shortcut is simpler than an
        // NSEvent monitor and doesn't intercept anything else. Disabled (rather than always live)
        // so `canUndo` is the actual gate on whether ⌘Z does anything, not just `undoDelete()`'s
        // own no-op guard.
        .background(
            Button("Undo", action: store.undoDelete)
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!store.canUndo)
                .opacity(0)
                .allowsHitTesting(false)
        )
    }

    private var header: some View {
        HStack {
            Text(countLabel)
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
            Spacer()
            Button(action: createNote) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .foregroundStyle(Palette.primaryText)
            .accessibilityLabel("New note")
        }
    }

    private var countLabel: String {
        let count = store.notes.count
        return count == 0 ? "No notes" : "\(count) note\(count == 1 ? "" : "s")"
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("No notes yet")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var rows: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(store.notes) { note in
                    NoteRow(
                        note: note,
                        onOpen: { openNoteID = note.id },
                        onRemove: { store.delete(id: note.id) }
                    )
                }
            }
        }
    }

    private func createNote() {
        let note = store.create()
        openNoteID = note.id
    }
}

/// One row in the notes list: title, an optional preview line, and a hover ✕ to delete. Spec §3.4.
private struct NoteRow: View {
    let note: Note
    let onOpen: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.callout.bold())
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)
                if let preview = note.preview {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityLabel("Delete \(note.title)")
            }
        }
        .padding(8)
        .contentShape(Rectangle())
        .background(isHovering ? Palette.tileHover : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onOpen)
    }
}
