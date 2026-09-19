import Foundation
import Observation
import AppInfo
import Persistence

/// Backs the Shelf widget: bookmarked files and folders, persisted across launches (spec §3.3).
///
/// Never copies a file — every item is a security-scoped bookmark, resolved on demand. An item
/// whose bookmark can't be resolved is "missing": still listed, still removable, but not
/// openable or draggable.
@MainActor
@Observable
public final class ShelfStore {
    public private(set) var items: [ShelfItem]

    @ObservationIgnored private let resolver: BookmarkResolver
    @ObservationIgnored private let store: JSONFileStore<ShelfDocument>
    @ObservationIgnored private let logger = AppIdentity.current.logger("shelf")

    public init(store: JSONFileStore<ShelfDocument>, resolver: BookmarkResolver = SecurityScopedBookmarkResolver()) {
        self.store = store
        self.resolver = resolver
        items = (store.load() ?? ShelfDocument()).items.sorted { $0.addedAt > $1.addedAt }
        refreshStaleBookmarks()
    }

    /// Adds items for URLs not already on the shelf (matched by resolved, standardized path) and
    /// not duplicated within this same drop. Returns how many were actually added.
    @discardableResult
    public func add(urls: [URL]) -> Int {
        var knownPaths = Set(resolvedPaths())
        var added = 0
        for url in urls {
            let path = Self.standardizedPath(url)
            guard !knownPaths.contains(path) else { continue }
            guard let bookmark = resolver.makeBookmark(for: url) else {
                logger.error("Could not bookmark \(url.lastPathComponent, privacy: .public)")
                continue
            }
            items.insert(ShelfItem(bookmark: bookmark, displayName: url.lastPathComponent), at: 0)
            knownPaths.insert(path)
            added += 1
        }
        if added > 0 { persist() }
        return added
    }

    /// Removes the given items, if any are present.
    public func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let before = items.count
        items.removeAll { ids.contains($0.id) }
        if items.count != before { persist() }
    }

    public func clear() {
        remove(Set(items.map(\.id)))
    }

    /// Same as `remove`, named for what it means when called after a successful drag-out.
    public func consume(_ ids: Set<UUID>) {
        remove(ids)
    }

    /// Whether `id`'s bookmark can no longer be resolved.
    public func isMissing(_ id: UUID) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        return resolver.resolve(item.bookmark) == nil
    }

    /// The item's resolved URL, or `nil` if it's missing. Refreshes and saves a stale bookmark
    /// along the way.
    public func url(for id: UUID) -> URL? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        guard let resolved = resolver.resolve(item.bookmark) else { return nil }
        if resolved.isStale {
            refreshBookmark(for: id, url: resolved.url)
        }
        return resolved.url
    }

    /// Writes any pending change synchronously. Called on fold and at app termination.
    public func flush() {
        store.flush()
    }

    private func refreshStaleBookmarks() {
        var changed = false
        for index in items.indices {
            guard let resolved = resolver.resolve(items[index].bookmark), resolved.isStale,
                  let fresh = resolver.makeBookmark(for: resolved.url) else { continue }
            items[index].bookmark = fresh
            changed = true
        }
        if changed { persist() }
    }

    private func refreshBookmark(for id: UUID, url: URL) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              let fresh = resolver.makeBookmark(for: url) else { return }
        items[index].bookmark = fresh
        persist()
    }

    private func resolvedPaths() -> [String] {
        items.compactMap { resolver.resolve($0.bookmark).map { Self.standardizedPath($0.url) } }
    }

    private static func standardizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func persist() {
        store.save(ShelfDocument(items: items))
    }
}
