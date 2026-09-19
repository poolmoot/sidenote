import SwiftUI
import AppKit
import QuickLook
import NotchWidgetAPI
import DesignSystem

/// The Shelf's expanded view: a header (item count, *Clear all*), a grid of `ShelfItemCell`s, and
/// an empty-state message when there's nothing on the shelf. Spec §3.3.
struct ShelfView: View {
    let store: ShelfStore
    let context: WidgetContext

    /// Owned here, not by `ShelfStore`, so it's released whenever this view is torn down on fold
    /// (spec §3.3, §7).
    @State private var thumbnailLoader = ThumbnailLoader()
    @State private var selection: Set<ShelfItem.ID> = []
    @State private var hoveredID: ShelfItem.ID?
    @State private var quickLookURL: URL?

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if store.items.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .focusable()
        .onKeyPress(.space) {
            guard let id = quickLookCandidate, let url = store.url(for: id) else { return .ignored }
            quickLookURL = url
            return .handled
        }
        .quickLookPreview($quickLookURL)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text(countLabel)
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
            Spacer()
            if !store.items.isEmpty {
                Button("Clear all") {
                    store.clear()
                    selection.removeAll()
                }
                .buttonStyle(.plain)
                .font(.caption.bold())
                .foregroundStyle(Palette.secondaryText)
            }
        }
    }

    private var countLabel: String {
        let count = store.items.count
        return count == 0 ? "No files" : "\(count) item\(count == 1 ? "" : "s")"
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("Drop files here")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Grid

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(store.items) { item in
                    cell(for: item)
                }
            }
        }
    }

    private func cell(for item: ShelfItem) -> some View {
        let isMissing = store.isMissing(item.id)
        return ShelfItemCell(
            item: item,
            isMissing: isMissing,
            isSelected: selection.contains(item.id),
            thumbnail: thumbnailLoader.thumbnail(for: item.id),
            dragURLsProvider: { dragURLs(draggingFrom: item.id) },
            onOpen: { open(item.id) },
            onToggleSelect: { toggleSelection(item.id) },
            onRemove: { remove(item.id) },
            onDragFinished: { performed in
                guard performed else { return }
                store.consume(selectionOrSingle(item.id))
                selection.removeAll()
            }
        )
        .onHover { isHovering in
            hoveredID = isHovering ? item.id : (hoveredID == item.id ? nil : hoveredID)
        }
        .task(id: item.id) {
            guard !isMissing, let url = store.url(for: item.id) else { return }
            thumbnailLoader.load(id: item.id, url: url)
        }
    }

    // MARK: Actions

    private var quickLookCandidate: ShelfItem.ID? {
        hoveredID ?? (selection.count == 1 ? selection.first : nil)
    }

    /// The URLs a drag starting on `id` should carry: every selected item when `id` is part of
    /// the current selection, otherwise just `id` on its own. Called lazily, right as a drag
    /// begins, never during view rendering.
    private func dragURLs(draggingFrom id: ShelfItem.ID) -> [URL] {
        selectionOrSingle(id).compactMap { store.url(for: $0) }
    }

    private func selectionOrSingle(_ id: ShelfItem.ID) -> Set<ShelfItem.ID> {
        selection.contains(id) ? selection : [id]
    }

    private func toggleSelection(_ id: ShelfItem.ID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func open(_ id: ShelfItem.ID) {
        guard let url = store.url(for: id) else { return }
        withSecurityScopedAccess(to: url) {
            NSWorkspace.shared.open(url)
        }
    }

    private func remove(_ id: ShelfItem.ID) {
        selection.remove(id)
        store.remove([id])
    }
}
