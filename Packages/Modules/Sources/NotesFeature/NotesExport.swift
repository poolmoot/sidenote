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
        var trimmed = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
        // A leading "." makes a hidden file on macOS — not what a title starting with "." (e.g.
        // ".env notes" or "...to think about") means to produce (fixed post-review).
        if trimmed.hasPrefix(".") {
            trimmed = "-" + trimmed.dropFirst()
        }
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    /// Writes one `.md` file per note into `directory`. A note whose file can't be written is
    /// logged and skipped rather than aborting the rest of the export. Returns how many files were
    /// actually written.
    ///
    /// Seeds the used-names set from whatever's already in `directory` (fixed post-review: this
    /// used to start from an empty set, so exporting into a folder that already had a
    /// same-titled note's file would silently overwrite it) — so a name already on disk, from an
    /// earlier export or anything else, is treated exactly like a same-title collision within
    /// this export and gets a numeric suffix instead.
    @discardableResult
    public static func exportAll(_ notes: [Note], to directory: URL, logger: Logger = AppIdentity.current.logger("notes")) -> Int {
        var existingNames = existingFilenames(in: directory)
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

    private static func existingFilenames(in directory: URL) -> Set<String> {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return Set(contents)
    }
}
