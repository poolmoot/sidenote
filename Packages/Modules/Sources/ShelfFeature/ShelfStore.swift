import Foundation
import Observation
import AppInfo
import Persistence

/// Backs the Shelf widget: bookmarked files and folders, persisted across launches (spec §3.3).
///
/// Never copies a file — every item is a security-scoped bookmark, resolved on demand. An item
/// whose bookmark can't be resolved, or whose resolved path is in the Trash, is "missing": still
/// listed, still removable, but not openable or draggable.
@MainActor
@Observable
public final class ShelfStore {
    public private(set) var items: [ShelfItem]
    /// Ids currently missing, as of the last `refreshMissingStatus()`. Cached rather than
    /// resolved on every read: resolving a bookmark isn't something to repeat on every SwiftUI
    /// re-render (e.g. a hover highlight), so callers refresh this once on expand and this store
    /// refreshes it itself after `add` and after a bookmark refresh.
    public private(set) var missingIDs: Set<UUID> = []

    @ObservationIgnored private let resolver: BookmarkResolver
    @ObservationIgnored private let store: JSONFileStore<ShelfDocument>
    @ObservationIgnored private let logger = AppIdentity.current.logger("shelf")

    public init(store: JSONFileStore<ShelfDocument>, resolver: BookmarkResolver = SecurityScopedBookmarkResolver()) {
        self.store = store
        self.resolver = resolver
        items = (store.load() ?? ShelfDocument()).items.sorted { $0.addedAt > $1.addedAt }
        refreshStaleBookmarks()
        refreshMissingStatus()
    }

    /// Adds items for URLs not already on the shelf (matched by resolved, standardized path) and
    /// not duplicated within this same drop. New items are inserted as one batch, newest-first
    /// relative to whatever was already there, but keeping the order they were dropped in within
    /// that batch. Returns how many were actually added.
    @discardableResult
    public func add(urls: [URL]) -> Int {
        var knownPaths = Set(resolvedPaths())
        var newItems: [ShelfItem] = []
        for url in urls {
            let path = Self.standardizedPath(url)
            guard !knownPaths.contains(path) else { continue }
            guard let bookmark = resolver.makeBookmark(for: url) else {
                logger.error("Could not bookmark \(url.lastPathComponent, privacy: .public)")
                continue
            }
            newItems.append(ShelfItem(bookmark: bookmark, displayName: url.lastPathComponent))
            knownPaths.insert(path)
        }
        guard !newItems.isEmpty else { return 0 }
        items.insert(contentsOf: newItems, at: 0)
        refreshMissingStatus()
        persist()
        return newItems.count
    }

    /// Removes the given items, if any are present.
    public func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let before = items.count
        items.removeAll { ids.contains($0.id) }
        missingIDs.subtract(ids)
        if items.count != before { persist() }
    }

    public func clear() {
        remove(Set(items.map(\.id)))
    }

    /// Same as `remove`, named for what it means when called after a successful drag-out.
    public func consume(_ ids: Set<UUID>) {
        remove(ids)
    }

    /// Whether `id` is missing, from the cache last built by `refreshMissingStatus()`.
    public func isMissing(_ id: UUID) -> Bool {
        missingIDs.contains(id)
    }

    /// Re-resolves every item and rebuilds `missingIDs`. A real resolve, so this is meant to be
    /// called once when the shelf is expanded — not from view rendering.
    public func refreshMissingStatus() {
        missingIDs = Set(items.compactMap { isMissing(resolving: $0) ? $0.id : nil })
    }

    /// The item's resolved URL, or `nil` if it's missing (including "resolves fine but the file
    /// is in the Trash", which spec treats as missing even though the bookmark still works).
    /// Refreshes and saves a stale bookmark along the way.
    public func url(for id: UUID) -> URL? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        guard let resolved = resolver.resolve(item.bookmark), !Self.isInTrash(resolved.url) else {
            missingIDs.insert(id)
            return nil
        }
        missingIDs.remove(id)
        if resolved.isStale {
            refreshBookmark(for: id, url: resolved.url)
        }
        return resolved.url
    }

    /// Writes any pending change synchronously. Called on fold and at app termination.
    public func flush() {
        store.flush()
    }

    private func isMissing(resolving item: ShelfItem) -> Bool {
        guard let resolved = resolver.resolve(item.bookmark) else { return true }
        return Self.isInTrash(resolved.url)
    }

    private func refreshStaleBookmarks() {
        var changed = false
        for index in items.indices {
            guard let resolved = resolver.resolve(items[index].bookmark), resolved.isStale else { continue }
            guard let fresh = refreshedBookmark(for: resolved.url) else { continue }
            items[index].bookmark = fresh
            items[index].displayName = resolved.url.lastPathComponent
            changed = true
        }
        if changed { persist() }
    }

    private func refreshBookmark(for id: UUID, url: URL) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard let fresh = refreshedBookmark(for: url) else { return }
        items[index].bookmark = fresh
        items[index].displayName = url.lastPathComponent
        persist()
    }

    /// Creates a fresh bookmark for a URL that just came out of `resolve`, with that URL's
    /// security scope held open. Recreating a bookmark from a resolved security-scoped URL needs
    /// the scope active — skipping this made refreshing a stale bookmark silently fail in a real
    /// sandboxed run (nothing enforces that in tests, since `FakeBookmarkResolver` doesn't need a
    /// scope at all). Logs and returns `nil` on failure rather than swallowing it.
    private func refreshedBookmark(for url: URL) -> Data? {
        guard let fresh = withSecurityScopedAccess(to: url, { resolver.makeBookmark(for: url) }) else {
            logger.error("Could not refresh bookmark for \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        return fresh
    }

    private func resolvedPaths() -> [String] {
        items.compactMap { resolver.resolve($0.bookmark).map { Self.standardizedPath($0.url) } }
    }

    private static func standardizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func isInTrash(_ url: URL) -> Bool {
        url.standardizedFileURL.path.contains("/.Trash/")
    }

    private func persist() {
        store.save(ShelfDocument(items: items))
    }
}
