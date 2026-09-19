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

    @Test func tabIndentationBeforeTheHyphenIsPreserved() {
        #expect(ChecklistLine.parse("\t- [ ] nested") == .checkbox(indent: "\t", done: false, text: "nested"))
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

    @Test func aTrailingCarriageReturnFromACRLFLineStaysPartOfTheText() {
        #expect(ChecklistLine.parse("- [ ] buy milk\r") == .checkbox(indent: "", done: false, text: "buy milk\r"))
    }

    // MARK: togglingMarker

    @Test func togglingMarkerFlipsUncheckedToChecked() {
        #expect(ChecklistLine.togglingMarker(in: "- [ ] buy milk") == "- [x] buy milk")
    }

    @Test func togglingMarkerFlipsCheckedToUnchecked() {
        #expect(ChecklistLine.togglingMarker(in: "- [x] buy milk") == "- [ ] buy milk")
    }

    @Test func togglingMarkerFlipsUppercaseCheckedToUnchecked() {
        #expect(ChecklistLine.togglingMarker(in: "- [X] buy milk") == "- [ ] buy milk")
    }

    @Test func togglingMarkerTwiceReturnsToTheOriginal() {
        let original: Substring = "- [ ] buy milk"
        #expect(ChecklistLine.togglingMarker(in: ChecklistLine.togglingMarker(in: original)) == original)
    }

    @Test func togglingMarkerOnAPlainLineIsANoOp() {
        #expect(ChecklistLine.togglingMarker(in: "just a note") == "just a note")
    }

    @Test func togglingMarkerOnAHyphenWithoutASpaceIsANoOp() {
        #expect(ChecklistLine.togglingMarker(in: "-[ ] not a checkbox") == "-[ ] not a checkbox")
    }

    /// The specific edge case a parse-then-rebuild toggle didn't round-trip: a trailing space with
    /// no text after the marker. Flipping the marker character in place can't lose it.
    @Test func togglingMarkerPreservesATrailingSpaceWithEmptyText() {
        #expect(ChecklistLine.togglingMarker(in: "- [ ] ") == "- [x] ")
    }

    @Test func togglingMarkerPreservesIndentAndExtraSpacesInText() {
        #expect(ChecklistLine.togglingMarker(in: "  - [ ]  two spaces before text") == "  - [x]  two spaces before text")
    }

    @Test func togglingMarkerPreservesATrailingCarriageReturn() {
        #expect(ChecklistLine.togglingMarker(in: "- [ ] buy milk\r") == "- [x] buy milk\r")
    }

    @Test func togglingMarkerPreservesEmojiAndMultiByteText() {
        #expect(ChecklistLine.togglingMarker(in: "- [ ] 買い物 🛒") == "- [x] 買い物 🛒")
    }
}
