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
    var title: String { titleAndPreview.title }

    /// The next non-empty line after the title, for the list row's subtitle — `nil` when there
    /// isn't one (a one-line note, or an empty note).
    var preview: String? { titleAndPreview.preview }

    /// Title and preview computed together in a single pass over `text`'s lines, stopping as soon
    /// as both are found — a list row needs both, and neither one should cost scanning the whole
    /// note (a large note shouldn't make every row redraw slower). `.whitespacesAndNewlines`
    /// (rather than just `.whitespaces`) trims a stray trailing "\r" from a CRLF-authored line.
    private var titleAndPreview: (title: String, preview: String?) {
        var title: String?
        var preview: String?
        for line in splitIntoLines(text) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if title == nil {
                title = trimmed
            } else {
                preview = trimmed
                break
            }
        }
        return (title ?? "New note", preview)
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
