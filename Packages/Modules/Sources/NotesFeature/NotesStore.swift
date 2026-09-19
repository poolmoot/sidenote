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
        notes = (store.load() ?? NotesDocument()).notes.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Whether `undoDelete()` would currently restore something.
    public var canUndo: Bool { deleted != nil }

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

    /// Restores the last-deleted note to its original position. A no-op when there's nothing to
    /// restore, including after `clearUndo()`.
    public func undoDelete() {
        guard let deleted else { return }
        let index = min(deleted.index, notes.count)
        notes.insert(deleted.note, at: index)
        self.deleted = nil
        persist()
    }

    /// Drops the single-level undo. Called when the widget closes (spec §3.4).
    public func clearUndo() {
        deleted = nil
    }

    /// Flips the checkbox on `text`'s line at `lineIndex`, rewriting only that line's marker and
    /// leaving every other character byte-identical. Does nothing if `id` is unknown, the line
    /// index is out of range, or that line isn't a checkbox line.
    public func toggleCheckbox(id: UUID, lineIndex: Int) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var lines = notes[index].text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.indices.contains(lineIndex) else { return }
        let parsed = ChecklistLine.parse(lines[lineIndex])
        guard case .checkbox = parsed else { return }
        lines[lineIndex] = Substring(parsed.toggled.rendered)
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
