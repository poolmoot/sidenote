import Foundation
import Testing
@testable import NotesFeature

struct NotesExportFilenameTests {
    @Test func derivesFilenameFromTitle() {
        #expect(NotesExport.filename(for: "Groceries", existingNames: []) == "Groceries.md")
    }

    @Test func collidingTitlesGetANumericSuffix() {
        let existing: Set<String> = ["Groceries.md"]
        #expect(NotesExport.filename(for: "Groceries", existingNames: existing) == "Groceries 2.md")
    }

    @Test func aThirdCollisionSkipsToTheNextFreeSuffix() {
        let existing: Set<String> = ["Groceries.md", "Groceries 2.md"]
        #expect(NotesExport.filename(for: "Groceries", existingNames: existing) == "Groceries 3.md")
    }

    @Test func invalidPathCharactersAreReplaced() {
        #expect(NotesExport.filename(for: "Q1/Q2 plan", existingNames: []) == "Q1-Q2 plan.md")
        #expect(NotesExport.filename(for: "a:b?c*d", existingNames: []) == "a-b-c-d.md")
    }

    @Test func anEmptyOrWhitespaceOnlyTitleFallsBackToUntitled() {
        #expect(NotesExport.filename(for: "", existingNames: []) == "Untitled.md")
        #expect(NotesExport.filename(for: "   ", existingNames: []) == "Untitled.md")
    }

    @Test func collidingUntitledNotesAreAlsoDisambiguated() {
        let existing: Set<String> = ["Untitled.md"]
        #expect(NotesExport.filename(for: "", existingNames: existing) == "Untitled 2.md")
    }

    /// A leading "." makes a hidden file on macOS — a title that happens to start with one (e.g.
    /// a note about a ".env" file) must not silently produce one.
    @Test func aLeadingDotIsReplacedSoTheFileIsNotHidden() {
        #expect(NotesExport.filename(for: ".env notes", existingNames: []) == "-env notes.md")
        #expect(NotesExport.filename(for: "...", existingNames: []) == "-...md")
    }
}

struct NotesExportWritingTests {
    private let directory: URL

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesExportTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test func writesOneFilePerNoteNamedFromItsTitle() throws {
        let notes = [
            Note(text: "Groceries\nmilk\neggs"),
            Note(text: "Trip plan\npack bags"),
        ]
        let written = NotesExport.exportAll(notes, to: directory)
        #expect(written == 2)

        let groceries = try String(contentsOf: directory.appendingPathComponent("Groceries.md"), encoding: .utf8)
        #expect(groceries == "Groceries\nmilk\neggs")
        let trip = try String(contentsOf: directory.appendingPathComponent("Trip plan.md"), encoding: .utf8)
        #expect(trip == "Trip plan\npack bags")
    }

    @Test func exportingTwoNotesWithTheSameTitleWritesBothUnderDistinctNames() throws {
        let notes = [Note(text: "Groceries\nmilk"), Note(text: "Groceries\neggs")]
        let written = NotesExport.exportAll(notes, to: directory)
        #expect(written == 2)

        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(contents == ["Groceries 2.md", "Groceries.md"])
    }

    @Test func exportingNoNotesWritesNothing() {
        #expect(NotesExport.exportAll([], to: directory) == 0)
    }

    /// Fixed post-review: `exportAll` used to start its collision-tracking set empty, so exporting
    /// into a folder that already had a same-named file (from an earlier export, or anything else
    /// the user put there) silently overwrote it instead of disambiguating.
    @Test func aNoteWhoseNameAlreadyExistsInTheFolderIsDisambiguatedRatherThanOverwritten() throws {
        let existingURL = directory.appendingPathComponent("Groceries.md")
        try "pre-existing content, not written by this export".write(to: existingURL, atomically: true, encoding: .utf8)

        let written = NotesExport.exportAll([Note(text: "Groceries\nmilk")], to: directory)
        #expect(written == 1)

        let untouched = try String(contentsOf: existingURL, encoding: .utf8)
        #expect(untouched == "pre-existing content, not written by this export")
        let newFile = try String(contentsOf: directory.appendingPathComponent("Groceries 2.md"), encoding: .utf8)
        #expect(newFile == "Groceries\nmilk")
    }
}
