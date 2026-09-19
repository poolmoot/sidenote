import Foundation

/// One free-form note. Spec §4.6.
public struct Note: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var text: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), text: String = "", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public extension Note {
    /// The first non-empty line, trimmed, or "New note" for a note with no text yet. Spec §3.4.
    var title: String {
        nonEmptyLines.first ?? "New note"
    }

    /// The next non-empty line after the title, for the list row's subtitle — `nil` when there
    /// isn't one (a one-line note, or an empty note).
    var preview: String? {
        let lines = nonEmptyLines
        return lines.count > 1 ? lines[1] : nil
    }

    /// Every line with content, trimmed of surrounding whitespace, blank lines dropped. Title and
    /// preview both skip blank lines rather than treating "line 1" and "line 2" literally, so a
    /// note that starts with a couple of blank lines still shows a sensible title.
    private var nonEmptyLines: [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// The on-disk shape of `notes.json`. `version` enables future migrations. Spec §4.5.
public struct NotesDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var notes: [Note]

    public init(version: Int = 1, notes: [Note] = []) {
        self.version = version
        self.notes = notes
    }
}
