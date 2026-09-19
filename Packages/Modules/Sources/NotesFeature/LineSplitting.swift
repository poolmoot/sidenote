import Foundation

/// Splits `text` into lines on the "\n" Unicode **scalar**, not the `Character` (extended grapheme
/// cluster). `"\r\n"` is a single `Character` in Swift, so a naive `text.split(separator: "\n" as
/// Character)` never finds a boundary inside a CRLF pair and treats a whole Windows-authored note
/// as one line — silently breaking checklist parsing (spec §12: text input needs care).
///
/// Splitting the `unicodeScalars` view instead cuts precisely at each line-feed scalar, so a
/// trailing "\r" stays attached to the line before it. `lines.joined(separator: "\n")` therefore
/// reconstructs the original bytes exactly, CRLF included.
func splitIntoLines<S: StringProtocol>(_ text: S) -> [Substring] {
    Substring(text).unicodeScalars
        .split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" })
        .map(Substring.init)
}
