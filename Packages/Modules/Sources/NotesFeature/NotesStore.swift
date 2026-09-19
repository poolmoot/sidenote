import Foundation
import Observation
import Persistence

/// Backs the Notes widget: freeform text notes with tickable checklist lines, persisted across
/// launches (spec §3.4).
@MainActor
@Observable
public final class NotesStore {
    /// Sorted by `updatedAt`, newest first.
    public private(set) var notes: [Note]

    @ObservationIgnored private let store: JSONFileStore<NotesDocument>
    /// The most recently deleted note and the index it lived at, kept for a single level of undo.
    /// Cleared by `clearUndo()`, which the widget calls when it closes, so ⌘Z never reaches back
    /// past the last time the list was on screen.
    @ObservationIgnored private var deleted: (note: Note, index: Int)?

    public init(store: JSONFileStore<NotesDocument>) {
        self.store = store
        // A document from a future, unrecognized schema is quarantined rather than accepted as
        // though it were version 1 — see `JSONFileStore.load(isValid:)`.
        notes = (store.load(isValid: { $0.version == 1 }) ?? NotesDocument()).notes
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Whether `undoDelete()` would currently restore something.
    public var canUndo: Bool { deleted != nil }

    /// `id`'s current text, or `""` if `id` is unknown. The single source of truth for a note's
    /// text is this store, not a view's own `@State` copy — that's how a checkbox toggle and an
    /// in-flight keystroke stayed in sync (see `NoteEditorView`, which binds directly through
    /// this accessor rather than caching the text itself).
    public func text(for id: UUID) -> String {
        notes.first(where: { $0.id == id })?.text ?? ""
    }

    /// Creates an empty note and puts it at the top of the list, ready to be opened and focused.
    @discardableResult
    public func create() -> Note {
        let note = Note()
        notes.insert(note, at: 0)
        persist()
        return note
    }

    /// Replaces `id`'s text, bumps `updatedAt`, and re-sorts — the edited note moves to the top.
    /// Does nothing if `id` isn't in the store (e.g. it was deleted from another view).
    public func update(id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].text = text
        notes[index].updatedAt = Date()
        resort()
        persist()
    }

    /// Removes `id`, remembering its position so `undoDelete()` can put it back.
    public func delete(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        deleted = (notes.remove(at: index), index)
        persist()
    }

    /// Restores the last-deleted note, then re-sorts by `updatedAt` — its original array position
    /// is just a starting point, not the final word, since notes may have been added, edited, or
    /// removed while it was gone. A no-op when there's nothing to restore, including after
    /// `clearUndo()`.
    public func undoDelete() {
        guard let deleted else { return }
        let index = min(deleted.index, notes.count)
        notes.insert(deleted.note, at: index)
        self.deleted = nil
        resort()
        persist()
    }

    /// Drops the single-level undo. Called when the widget closes (spec §3.4).
    public func clearUndo() {
        deleted = nil
    }

    /// Flips the checkbox on `text`'s line at `lineIndex` — structurally, via
    /// `ChecklistLine.togglingMarker`, so nothing but that one marker character can ever change.
    /// Does nothing if `id` is unknown, the line index is out of range, or that line isn't a
    /// checkbox line. Lines are split on the "\n" scalar (`splitIntoLines`), so this is CRLF-safe:
    /// a Windows-authored note's lines are still found and only the toggled line's bytes change,
    /// down to a preserved trailing "\r".
    public func toggleCheckbox(id: UUID, lineIndex: Int) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var lines = splitIntoLines(notes[index].text)
        guard lines.indices.contains(lineIndex) else { return }
        guard case .checkbox = ChecklistLine.parse(lines[lineIndex]) else { return }
        lines[lineIndex] = ChecklistLine.togglingMarker(in: lines[lineIndex])
        notes[index].text = lines.joined(separator: "\n")
        notes[index].updatedAt = Date()
        resort()
        persist()
    }

    /// Writes any pending change synchronously. Called on fold and at app termination.
    public func flush() {
        store.flush()
    }

    private func resort() {
        notes.sort { $0.updatedAt > $1.updatedAt }
    }

    private func persist() {
        store.save(NotesDocument(notes: notes))
    }
}
