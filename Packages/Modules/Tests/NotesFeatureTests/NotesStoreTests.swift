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
}
