import Foundation
@testable import ShelfFeature

/// A resolver that maps a URL to bookmark data and back, in memory, so tests never touch the
/// real security-scoped bookmark APIs (which need an entitled, sandboxed process).
///
/// Each `makeBookmark(for:)` call returns a distinct blob, like the real API does, so a refreshed
/// bookmark is never byte-identical to the one it replaces.
@MainActor
final class FakeBookmarkResolver: BookmarkResolver {
    private var pathsByBookmark: [Data: String] = [:]
    private var latestBookmarkByPath: [String: Data] = [:]
    private var staleBookmarks: Set<Data> = []
    private var nextToken = 0
    private(set) var makeBookmarkCallCount = 0

    /// Every `makeBookmark(for:)` call after this is set returns `nil`, simulating a URL that
    /// can't be bookmarked.
    var failToBookmark = false

    func makeBookmark(for url: URL) -> Data? {
        makeBookmarkCallCount += 1
        guard !failToBookmark else { return nil }
        nextToken += 1
        let bookmark = Data("bookmark:\(nextToken):\(url.path)".utf8)
        pathsByBookmark[bookmark] = url.path
        latestBookmarkByPath[url.path] = bookmark
        return bookmark
    }

    func resolve(_ bookmark: Data) -> (url: URL, isStale: Bool)? {
        guard let path = pathsByBookmark[bookmark] else { return nil }
        return (URL(fileURLWithPath: path), staleBookmarks.contains(bookmark))
    }

    /// Marks the current bookmark for `url` (the one `makeBookmark` most recently returned for
    /// it) stale.
    func markStale(_ url: URL) {
        guard let bookmark = latestBookmarkByPath[url.path] else { return }
        staleBookmarks.insert(bookmark)
    }

    /// Simulates the original being deleted or otherwise no longer resolvable: every bookmark
    /// ever issued for `url` stops resolving.
    func breakBookmark(for url: URL) {
        for key in pathsByBookmark.filter({ $0.value == url.path }).keys {
            pathsByBookmark.removeValue(forKey: key)
        }
        latestBookmarkByPath.removeValue(forKey: url.path)
    }
}
