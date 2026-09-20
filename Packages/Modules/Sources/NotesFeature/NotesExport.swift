import Foundation
import os
import AppInfo

/// "Export all notes…" (spec §3.6 Notes tab): one `.md` file per note, named from its title.
public enum NotesExport {
    /// Characters that can't appear in a macOS filename, or that would read oddly in one — the
    /// path separators plus a handful of shell/reserved punctuation. Replaced with "-" rather than
    /// dropped outright, so e.g. "Q1/Q2 plan" doesn't collapse into "Q1Q2 plan".
    private static let invalidFilenameCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")

    /// Derives a safe, unique `.md` filename from `title`: invalid characters replaced with "-",
    /// then disambiguated against `existingNames` (the names already produced earlier in the same
    /// export) with a numeric suffix — `"Groceries.md"`, `"Groceries 2.md"`, `"Groceries 3.md"`.
    public static func filename(for title: String, existingNames: Set<String>) -> String {
        let base = sanitizedBase(of: title)
        var candidate = "\(base).md"
        var suffix = 2
        while existingNames.contains(candidate) {
            candidate = "\(base) \(suffix).md"
            suffix += 1
        }
        return candidate
    }

    private static func sanitizedBase(of title: String) -> String {
        let replaced = String(title.unicodeScalars.map { invalidFilenameCharacters.contains($0) ? "-" : Character($0) })
        let trimmed = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    /// Writes one `.md` file per note into `directory`. A note whose file can't be written is
    /// logged and skipped rather than aborting the rest of the export. Returns how many files were
    /// actually written.
    @discardableResult
    public static func exportAll(_ notes: [Note], to directory: URL, logger: Logger = AppIdentity.current.logger("notes")) -> Int {
        var existingNames: Set<String> = []
        var written = 0
        for note in notes {
            let name = filename(for: note.title, existingNames: existingNames)
            existingNames.insert(name)
            let url = directory.appendingPathComponent(name)
            do {
                try note.text.write(to: url, atomically: true, encoding: .utf8)
                written += 1
            } catch {
                logger.error("Could not export note \(note.id): \(error.localizedDescription, privacy: .public)")
            }
        }
        return written
    }
}
