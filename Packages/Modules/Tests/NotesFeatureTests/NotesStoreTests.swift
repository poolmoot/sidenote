import Foundation
import Testing
import Persistence
@testable import NotesFeature

@MainActor
final class NotesStoreTests {
    private let directory: URL

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore(fileName: String = "notes.json") -> NotesStore {
        let fileStore = JSONFileStore<NotesDocument>(url: directory.appendingPathComponent(fileName))
        return NotesStore(store: fileStore)
    }

    @Test func createInsertsAnEmptyNoteAtTheTop() {
        let store = makeStore()
        let note = store.create()
        #expect(note.text.isEmpty)
        #expect(store.notes.first?.id == note.id)
    }

    @Test func textForReturnsTheCurrentTextAndIsTheSourceOfTruth() {
        let store = makeStore()
        let note = store.create()
        #expect(store.text(for: note.id).isEmpty)

        store.update(id: note.id, text: "hello")
        #expect(store.text(for: note.id) == "hello")
    }

    @Test func textForAnUnknownIDIsEmpty() {
        let store = makeStore()
        #expect(store.text(for: UUID()) == "")
    }

    @Test func updateBumpsUpdatedAtAndReordersToTheTop() {
        let store = makeStore()
        let first = store.create()
        let second = store.create()
        #expect(store.notes.map(\.id) == [second.id, first.id])

        store.update(id: first.id, text: "hello")
        #expect(store.notes.map(\.id) == [first.id, second.id])
        #expect(store.notes.first(where: { $0.id == first.id })!.text == "hello")
    }

    @Test func deleteThenUndoRestoresOriginalPosition() {
        let store = makeStore()
        let a = store.create()
        let b = store.create()
        let c = store.create()
        // insertion order puts newest first: c, b, a
        #expect(store.notes.map(\.id) == [c.id, b.id, a.id])

        store.delete(id: b.id)
        #expect(store.notes.map(\.id) == [c.id, a.id])

        store.undoDelete()
        #expect(store.notes.map(\.id) == [c.id, b.id, a.id])
    }

    @Test func undoDeleteReSortsByUpdatedAtRatherThanJustRestoringTheOldIndex() {
        let store = makeStore()
        let a = store.create()
        let b = store.create()
        let c = store.create()
        // newest first at creation: c, b, a
        store.delete(id: b.id)
        // now: c, a
        store.update(id: a.id, text: "a is freshest now")
        // now: a, c

        store.undoDelete()

        // b's `updatedAt` is still its original (oldest) timestamp, so it belongs at the end —
        // not back at its pre-delete array index (1), which would wrongly land it in the middle
        // ahead of `c`.
        #expect(store.notes.map(\.id) == [a.id, c.id, b.id])
    }

    @Test func undoWithNothingDeletedIsANoOp() {
        let store = makeStore()
        let a = store.create()
        store.undoDelete()
        #expect(store.notes.map(\.id) == [a.id])
    }

    @Test func clearUndoPreventsARestoreAfterTheWidgetCloses() {
        let store = makeStore()
        let a = store.create()
        store.delete(id: a.id)
        store.clearUndo()
        store.undoDelete()
        #expect(store.notes.isEmpty)
    }

    @Test func canUndoReflectsWhetherARestoreIsAvailable() {
        let store = makeStore()
        let a = store.create()
        #expect(!store.canUndo)

        store.delete(id: a.id)
        #expect(store.canUndo)

        store.undoDelete()
        #expect(!store.canUndo)
    }

    @Test func toggleCheckboxFlipsOnlyThatLine() {
        let store = makeStore()
        let note = store.create()
        store.update(id: note.id, text: "shopping\n- [ ] milk\n- [ ] eggs")

        store.toggleCheckbox(id: note.id, lineIndex: 1)

        #expect(store.notes.first?.text == "shopping\n- [x] milk\n- [ ] eggs")
    }

    @Test func toggleCheckboxOnAPlainLineDoesNothing() {
        let store = makeStore()
        let note = store.create()
        store.update(id: note.id, text: "just text")

        store.toggleCheckbox(id: note.id, lineIndex: 0)

        #expect(store.notes.first?.text == "just text")
    }

    @Test func toggleCheckboxOutOfRangeDoesNothing() {
        let store = makeStore()
        let note = store.create()
        store.update(id: note.id, text: "one line")

        store.toggleCheckbox(id: note.id, lineIndex: 5)

        #expect(store.notes.first?.text == "one line")
    }

    @Test func toggleCheckboxPreservesTabIndentationAndTheRestOfTheDocument() {
        let store = makeStore()
        let note = store.create()
        let original = "list\n\t- [ ] sub-item\nafter"
        store.update(id: note.id, text: original)

        store.toggleCheckbox(id: note.id, lineIndex: 1)

        #expect(store.notes.first?.text == "list\n\t- [x] sub-item\nafter")
    }

    @Test func toggleCheckboxPreservesTrailingWhitespaceInTheLine() {
        let store = makeStore()
        let note = store.create()
        store.update(id: note.id, text: "- [ ] milk   \nafter")

        store.toggleCheckbox(id: note.id, lineIndex: 0)

        #expect(store.notes.first?.text == "- [x] milk   \nafter")
    }

    @Test func toggleCheckboxPreservesEmojiAndMultiByteText() {
        let store = makeStore()
        let note = store.create()
        store.update(id: note.id, text: "before\n- [ ] 買い物 🛒\nafter")

        store.toggleCheckbox(id: note.id, lineIndex: 1)

        #expect(store.notes.first?.text == "before\n- [x] 買い物 🛒\nafter")
    }

    @Test func toggleCheckboxOnACRLFDocumentFindsTheRightLineAndIsByteIdenticalElsewhere() {
        let store = makeStore()
        let note = store.create()
        let original = "shopping\r\n- [ ] milk\r\n- [ ] eggs\r\n"
        store.update(id: note.id, text: original)

        store.toggleCheckbox(id: note.id, lineIndex: 1)

        #expect(store.notes.first?.text == "shopping\r\n- [x] milk\r\n- [ ] eggs\r\n")
    }

    @Test func notesSurviveAReloadThroughJSONFileStore() {
        let fileURL = directory.appendingPathComponent("notes.json")
        let firstFileStore = JSONFileStore<NotesDocument>(url: fileURL)
        let store = NotesStore(store: firstFileStore)
        let note = store.create()
        store.update(id: note.id, text: "remember this")
        store.flush()

        let secondFileStore = JSONFileStore<NotesDocument>(url: fileURL)
        let reloaded = NotesStore(store: secondFileStore)
        #expect(reloaded.notes.map(\.text) == ["remember this"])
    }

    @Test func aFutureSchemaVersionIsQuarantinedAndStartsEmpty() throws {
        let fileURL = directory.appendingPathComponent("notes.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let future = NotesDocument(version: 2, notes: [Note(text: "from the future")])
        try JSONEncoder().encode(future).write(to: fileURL)

        let store = NotesStore(store: JSONFileStore<NotesDocument>(url: fileURL))

        #expect(store.notes.isEmpty)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(siblings.contains { $0.hasPrefix("notes.corrupt-") })
    }

    @Test func titleIsTheFirstNonEmptyLineTrimmedWithNextLineAsPreview() {
        let note = Note(text: "  Groceries  \nmilk, eggs")
        #expect(note.title == "Groceries")
        #expect(note.preview == "milk, eggs")
    }

    @Test func emptyNoteTitleFallsBackToPlaceholderWithNoPreview() {
        let note = Note(text: "")
        #expect(note.title == "New note")
        #expect(note.preview == nil)
    }

    @Test func blankLeadingLinesAreSkippedForTitleAndPreview() {
        let note = Note(text: "\n\n  \nActual title\nActual preview")
        #expect(note.title == "Actual title")
        #expect(note.preview == "Actual preview")
    }

    @Test func singleLineNoteHasNoPreview() {
        let note = Note(text: "Just one line")
        #expect(note.title == "Just one line")
        #expect(note.preview == nil)
    }

    @Test func titleAndPreviewTrimAStrayCarriageReturnFromACRLFNote() {
        let note = Note(text: "Groceries\r\nmilk, eggs\r")
        #expect(note.title == "Groceries")
        #expect(note.preview == "milk, eggs")
    }
}

@MainActor
struct DiscardingNewNotesTests {
    private func store() throws -> NotesStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return NotesStore(store: JSONFileStore<NotesDocument>(url: directory.appendingPathComponent("notes.json")))
    }

    @Test func discardingAnUntouchedNewNoteLeavesAnEarlierDeletionUndoable() throws {
        let notes = try store()
        let keeper = notes.create()
        notes.update(id: keeper.id, text: "shopping list")
        notes.delete(id: keeper.id)          // the deletion the user wants back

        let blank = notes.create()           // "+" pressed, nothing typed
        notes.discardUnsavedNewNote(id: blank.id)
        #expect(notes.notes.isEmpty)

        notes.undoDelete()                   // ⌘Z must restore the real note, not the blank one
        #expect(notes.notes.map(\.text) == ["shopping list"])
    }

    @Test func anExistingNoteClearedByTheUserIsKept() throws {
        let notes = try store()
        let note = notes.create()
        notes.update(id: note.id, text: "draft")
        notes.update(id: note.id, text: "")   // cleared on purpose

        notes.discardUnsavedNewNote(id: note.id)
        // The guard only discards a note that was never written to; this one was, so it stays.
        #expect(notes.notes.count == 1)
    }
}
