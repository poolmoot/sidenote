import AppKit
import QuickLookThumbnailing
import Observation

/// Generates and caches Quick Look thumbnails for shelf items, keyed by item id rather than URL
/// so a render pass never needs to resolve a bookmark just to look up a cached image.
///
/// The cache is owned by whoever creates the loader — in practice a `@State` in `ShelfView` — so
/// it is released automatically when the expanded shelf is torn down on fold (spec §3.3, §7).
@MainActor
@Observable
public final class ThumbnailLoader {
    private var cache: [ShelfItem.ID: NSImage] = [:]
    private var inFlight: Set<ShelfItem.ID> = []

    public init() {}

    /// The cached thumbnail for `id`, if one has finished loading.
    public func thumbnail(for id: ShelfItem.ID) -> NSImage? {
        cache[id]
    }

    /// Kicks off generation for `id` if it isn't cached or already loading. Safe to call every
    /// time a cell appears.
    public func load(id: ShelfItem.ID, url: URL, pointSize: CGFloat = 64, scale: CGFloat = 2) {
        guard cache[id] == nil, !inFlight.contains(id) else { return }
        inFlight.insert(id)
        // Generation happens asynchronously and may read the file at any point before the
        // completion handler runs, so the scope stays open until then rather than using the
        // synchronous `withSecurityScopedAccess` helper.
        let didStartAccess = url.startAccessingSecurityScopedResource()
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: pointSize, height: pointSize),
            scale: scale,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            // Pull the image out here: `QLThumbnailRepresentation` itself isn't `Sendable`, so it
            // can't cross into the `@MainActor` task below.
            let image = representation?.nsImage
            Task { @MainActor in
                if didStartAccess { url.stopAccessingSecurityScopedResource() }
                guard let self else { return }
                self.inFlight.remove(id)
                if let image {
                    self.cache[id] = image
                }
            }
        }
    }
}
