import Foundation
import Testing
@testable import NotchWidgetAPI

/// `WidgetID` is `RawRepresentable<String>` rather than a fixed enum (spec §M5 Phase 1), so a
/// saved value must round-trip through JSON with the exact same raw values the old enum used, and
/// decoding must accept a raw value this build doesn't recognize (e.g. a widget removed since the
/// value was saved) rather than failing.
struct WidgetIDTests {
    @Test func staticConstantsHaveTheExpectedRawValues() {
        #expect(WidgetID.shelf.rawValue == "shelf")
        #expect(WidgetID.notes.rawValue == "notes")
        #expect(WidgetID.reminders.rawValue == "reminders")
    }

    @Test func roundTripsThroughJSONWithTheRawStringValue() throws {
        for id in [WidgetID.shelf, .notes, .reminders] {
            let data = try JSONEncoder().encode(id)
            #expect(String(data: data, encoding: .utf8) == "\"\(id.rawValue)\"")
            let decoded = try JSONDecoder().decode(WidgetID.self, from: data)
            #expect(decoded == id)
        }
    }

    @Test func decodingAnUnknownRawValueSucceeds() throws {
        let data = Data("\"some-removed-widget\"".utf8)
        let decoded = try JSONDecoder().decode(WidgetID.self, from: data)
        #expect(decoded.rawValue == "some-removed-widget")
        #expect(decoded != .shelf)
        #expect(decoded != .notes)
        #expect(decoded != .reminders)
    }

    @Test func equalityAndHashingAreByRawValue() {
        #expect(WidgetID(rawValue: "shelf") == WidgetID.shelf)
        #expect(WidgetID(rawValue: "shelf").hashValue == WidgetID.shelf.hashValue)
        #expect(WidgetID(rawValue: "x") != WidgetID(rawValue: "y"))
    }

    @Test func descriptionIsTheRawValue() {
        #expect("\(WidgetID.notes)" == "notes")
    }
}
