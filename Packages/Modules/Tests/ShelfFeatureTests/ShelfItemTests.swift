import Foundation
import Testing
@testable import ShelfFeature

struct ShelfItemTests {
    @Test func roundTripsThroughJSON() throws {
        let item = ShelfItem(bookmark: Data("bookmark".utf8), displayName: "report.pdf")
        let document = ShelfDocument(items: [item])
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(ShelfDocument.self, from: data)
        #expect(decoded == document)
    }
}
