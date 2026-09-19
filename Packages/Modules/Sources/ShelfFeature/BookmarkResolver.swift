import Foundation

/// Turns URLs into security-scoped bookmarks and back. The shelf never copies a file — every item
/// is a bookmark to the original.
@MainActor
public protocol BookmarkResolver {
    /// Creates a security-scoped bookmark for `url`, or `nil` if one can't be created.
    func makeBookmark(for url: URL) -> Data?
    /// Resolves bookmark data back to a URL. `isStale` means the bookmark still resolved but
    /// should be recreated. `nil` means the original can no longer be found.
    func resolve(_ bookmark: Data) -> (url: URL, isStale: Bool)?
}

/// The real resolver, backed by `URL`'s security-scoped bookmark APIs (spec §3.3, §6).
public struct SecurityScopedBookmarkResolver: BookmarkResolver {
    public init() {}

    public func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public func resolve(_ bookmark: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return (url, isStale)
    }
}
