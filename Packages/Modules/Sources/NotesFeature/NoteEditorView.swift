import SwiftUI
import NotchWidgetAPI
import DesignSystem

/// One checklist line worth of derived display state, cached in `NoteEditorView` so parsing runs
/// only when the text actually changes, not on every `body` evaluation. `lineIndex` is what
/// `NotesStore.toggleCheckbox(id:lineIndex:)` needs to flip the right line.
private struct ChecklistRow: Identifiable {
    var id: Int { lineIndex }
    let lineIndex: Int
    let done: Bool
    let text: String
}

/// A single note's editor: the `TextEditor` is the *only* place the note's text is shown or typed
/// — there is no second copy of it — plus, below it, a small checklist of just this note's
/// tickable lines (`- [ ]` / `- [x]`). Plain text isn't duplicated there; that would mean showing
/// the whole note twice. Spec §3.4. Clickable links are deferred past M3.
///
/// The `TextEditor` binds straight through `NotesStore.text(for:)` / `update(id:text:)` — the
/// store is the single source of truth, so a checkbox toggle (which edits the store directly)
/// and an in-flight keystroke can never diverge the way they would with a view-owned `@State`
/// copy of the text.
///
/// Typing engages the widget's editing lock (`WidgetContext.setEditing`) so the notch doesn't fold
/// mid-keystroke when the app loses key status (see M1's review notes); leaving the editor — the
/// back row, or the notch folding — disengages it, deletes the note if it's still empty (so `+`
/// doesn't fill the list with untouched "New note" rows), and flushes any pending write.
struct NoteEditorView: View {
    let noteID: UUID
    /// True when `+` created this note for this editor: only such a note is discarded if it is
    /// left empty. A note that existed before and was cleared on purpose is the user's to keep.
    var isNewlyCreated: Bool = false
    let store: NotesStore
    let context: WidgetContext
    let onBack: () -> Void

    @FocusState private var isEditorFocused: Bool
    /// Recomputed in `onAppear`/`onChange`, never inside `body` — parsing every line on every
    /// keystroke was measurable cost for no benefit, since only the checkbox lines are ever shown.
    @State private var checklistRows: [ChecklistRow] = []

    private var textBinding: Binding<String> {
        Binding(
            get: { store.text(for: noteID) },
            set: { store.update(id: noteID, text: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            TextEditor(text: textBinding)
                .font(.body)
                .scrollContentBackground(.hidden)
                .foregroundStyle(Palette.primaryText)
                .frame(minHeight: 90, maxHeight: 140)
                .focused($isEditorFocused)
            if !checklistRows.isEmpty {
                Divider()
                checklist
            }
        }
        .onAppear {
            isEditorFocused = true
            recomputeChecklistRows(from: store.text(for: noteID))
        }
        .onChange(of: store.text(for: noteID)) { _, newText in
            recomputeChecklistRows(from: newText)
        }
        .onChange(of: isEditorFocused) { _, focused in
            context.setEditing(focused)
        }
        .onDisappear {
            context.setEditing(false)
            if isNewlyCreated, store.text(for: noteID).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                store.discardUnsavedNewNote(id: noteID)
            }
            store.flush()
        }
    }

    /// A labelled row, not a bare chevron: the widget header above the list already shows a plain
    /// chevron-less `+`, but a bare "‹" here would sit directly under nothing to distinguish it
    /// from any other back control — spelling out the destination makes the two unmistakable.
    private var header: some View {
        Button(action: onBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("All notes")
            }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .font(.caption.bold())
        .foregroundStyle(Palette.primaryText)
        .accessibilityLabel("Back to all notes")
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Checklist")
                .font(.caption2.bold())
                .foregroundStyle(Palette.secondaryText)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(checklistRows) { row in
                        checklistRowView(row)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func checklistRowView(_ row: ChecklistRow) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Button {
                store.toggleCheckbox(id: noteID, lineIndex: row.lineIndex)
            } label: {
                Image(systemName: row.done ? "checkmark.square.fill" : "square")
                    // The user's chosen accent colour (spec §3.6 Appearance), not the system
                    // `Color.accentColor` (fixed post-review) — `NotesFeature` can't see
                    // `NotchViewModel`'s tracked value (module boundary), so this reads
                    // `Palette.accent` best-effort, same as every other colour in this view.
                    .foregroundStyle(row.done ? Palette.accent : Palette.secondaryText)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .padding(4)
            .contentShape(Rectangle())

            Text(row.text)
                .strikethrough(row.done)
                .foregroundStyle(row.done ? Palette.secondaryText : Palette.primaryText)
        }
    }

    private func recomputeChecklistRows(from text: String) {
        checklistRows = splitIntoLines(text).enumerated().compactMap { lineIndex, line in
            guard case .checkbox(_, let done, let lineText) = ChecklistLine.parse(line) else { return nil }
            return ChecklistRow(lineIndex: lineIndex, done: done, text: lineText)
        }
    }
}
