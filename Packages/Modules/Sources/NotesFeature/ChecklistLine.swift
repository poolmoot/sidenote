import Foundation

/// One line of a note's text, parsed into either a tickable checkbox or plain text. Spec §3.4:
/// a line beginning `- [ ]` or `- [x]` (uppercase `X` accepted) renders as a checkbox; anything
/// else — including `-[ ]` with no space before the bracket — is plain text.
///
/// Parsing is pure string matching with no notion of a note or a store, so every edge case (case,
/// indentation, missing text) can be pinned down here rather than through a view or a store.
public enum ChecklistLine: Equatable, Sendable {
    /// `indent` is any leading whitespace before the `-`, preserved so a nested checklist item
    /// round-trips exactly. `text` is everything after the mandatory single space following the
    /// closing bracket, or empty when the line ends right at `]`.
    case checkbox(indent: String, done: Bool, text: String)
    case plain(String)

    /// Parses a single line (no trailing newline).
    public static func parse<S: StringProtocol>(_ line: S) -> ChecklistLine {
        let characters = Array(line)
        var index = characters.startIndex

        while index < characters.count, characters[index] == " " || characters[index] == "\t" {
            index += 1
        }
        let indent = String(characters[characters.startIndex..<index])

        func fallbackToPlain() -> ChecklistLine { .plain(String(line)) }

        guard index < characters.count, characters[index] == "-" else { return fallbackToPlain() }
        index += 1
        guard index < characters.count, characters[index] == " " else { return fallbackToPlain() }
        index += 1
        guard index < characters.count, characters[index] == "[" else { return fallbackToPlain() }
        index += 1
        guard index < characters.count, characters[index] == " " || characters[index] == "x" || characters[index] == "X" else {
            return fallbackToPlain()
        }
        let done = characters[index] != " "
        index += 1
        guard index < characters.count, characters[index] == "]" else { return fallbackToPlain() }
        index += 1

        let text: String
        if index < characters.count {
            guard characters[index] == " " else { return fallbackToPlain() }
            index += 1
            text = String(characters[index...])
        } else {
            text = ""
        }
        return .checkbox(indent: indent, done: done, text: text)
    }
}

public extension ChecklistLine {
    /// The line's marker flipped; a no-op on plain text.
    var toggled: ChecklistLine {
        switch self {
        case .plain:
            return self
        case .checkbox(let indent, let done, let text):
            return .checkbox(indent: indent, done: !done, text: text)
        }
    }

    /// The raw line text this case represents. For a value produced by `parse`, this round-trips
    /// to the original line exactly.
    var rendered: String {
        switch self {
        case .plain(let text):
            return text
        case .checkbox(let indent, let done, let text):
            let marker = done ? "x" : " "
            return text.isEmpty ? "\(indent)- [\(marker)]" : "\(indent)- [\(marker)] \(text)"
        }
    }
}
