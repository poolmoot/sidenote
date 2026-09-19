import Testing
@testable import NotesFeature

/// `ChecklistLine.parse` is pure text matching, so every edge case can be nailed down here without
/// touching a store or a view. Spec §3.4: `- [ ]` / `- [x]` lines are tickable checkboxes;
/// anything else is plain text.
struct ChecklistLineTests {
    @Test func uncheckedBoxParses() {
        #expect(ChecklistLine.parse("- [ ] buy milk") == .checkbox(indent: "", done: false, text: "buy milk"))
    }

    @Test func checkedBoxParses() {
        #expect(ChecklistLine.parse("- [x] buy milk") == .checkbox(indent: "", done: true, text: "buy milk"))
    }

    @Test func uppercaseCheckedMarkerIsAccepted() {
        #expect(ChecklistLine.parse("- [X] buy milk") == .checkbox(indent: "", done: true, text: "buy milk"))
    }

    @Test func leadingSpacesBeforeTheHyphenArePreserved() {
        #expect(ChecklistLine.parse("  - [ ] nested") == .checkbox(indent: "  ", done: false, text: "nested"))
    }

    @Test func hyphenWithoutASpaceBeforeTheBracketIsPlainText() {
        let line = "-[ ] not a checkbox"
        #expect(ChecklistLine.parse(line) == .plain(line))
    }

    @Test func emptyTextAfterTheMarkerIsAllowed() {
        #expect(ChecklistLine.parse("- [ ]") == .checkbox(indent: "", done: false, text: ""))
    }

    @Test func plainLineParsesAsPlain() {
        let line = "just a note"
        #expect(ChecklistLine.parse(line) == .plain(line))
    }

    @Test func emptyLineParsesAsPlain() {
        #expect(ChecklistLine.parse("") == .plain(""))
    }

    @Test func toggleFlipsOnlyTheMarker() {
        let parsed = ChecklistLine.parse("- [ ] buy milk")
        #expect(parsed.toggled == .checkbox(indent: "", done: true, text: "buy milk"))
        #expect(parsed.toggled.rendered == "- [x] buy milk")
    }

    @Test func togglingTwiceReturnsToTheOriginal() {
        let parsed = ChecklistLine.parse("- [x] buy milk")
        #expect(parsed.toggled.toggled == parsed)
    }

    @Test func toggleOnAPlainLineIsANoOp() {
        let parsed = ChecklistLine.parse("just a note")
        #expect(parsed.toggled == parsed)
    }

    @Test func renderingRoundTripsTheOriginalLine() {
        let original = "  - [x] done thing"
        #expect(ChecklistLine.parse(original).rendered == original)
    }

    @Test func renderingAnEmptyCheckboxRoundTrips() {
        let original = "- [ ]"
        #expect(ChecklistLine.parse(original).rendered == original)
    }
}
