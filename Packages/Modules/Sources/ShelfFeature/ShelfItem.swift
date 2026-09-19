import Foundation

/// One bookmarked file or folder on the shelf. Spec §4.6.
public struct ShelfItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var bookmark: Data
    public var displayName: String
    public let addedAt: Date

    public init(id: UUID = UUID(), bookmark: Data, displayName: String, addedAt: Date = Date()) {
        self.id = id
        self.bookmark = bookmark
        self.displayName = displayName
        self.addedAt = addedAt
    }
}

/// The on-disk shape of `shelf.json`. `version` enables future migrations.
public struct ShelfDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var items: [ShelfItem]

    public init(version: Int = 1, items: [ShelfItem] = []) {
        self.version = version
        self.items = items
    }
}
