import Foundation

/// Runs `body` while `url`'s security scope is active, matching every
/// `startAccessingSecurityScopedResource()` with a `stopAccessingSecurityScopedResource()`.
/// Safe to call on a URL that isn't security-scoped at all: `startAccessingSecurityScopedResource`
/// then simply returns `false` and `body` still runs normally.
@discardableResult
func withSecurityScopedAccess<T>(to url: URL, _ body: () -> T) -> T {
    let didStart = url.startAccessingSecurityScopedResource()
    defer { if didStart { url.stopAccessingSecurityScopedResource() } }
    return body()
}
