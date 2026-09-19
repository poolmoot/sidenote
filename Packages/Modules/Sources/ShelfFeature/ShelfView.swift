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
    @State private var quickLookURL: URL?
    /// Whether `quickLookURL`'s security scope is currently open, so it's closed exactly once.
    @State private var quickLookAccessGranted = false

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
        // A resolve isn't free (and can refresh a bookmark), so it happens once here rather than
        // from every cell's body — see `ShelfStore.refreshMissingStatus`.
        .onAppear { store.refreshMissingStatus() }
        // Spec §4.5: written on fold, not just at app termination.
        .onDisappear { store.flush() }
        .onChange(of: quickLookURL) { oldValue, newValue in
            if let oldValue, quickLookAccessGranted {
                oldValue.stopAccessingSecurityScopedResource()
                quickLookAccessGranted = false
            }
            if let newValue {
                // Held for as long as the preview is up, and paired with the editing lock so the
                // preview taking key doesn't fold the notch (see `NotchController`'s guard on
                // `.resignedKey` while a widget is editing).
                quickLookAccessGranted = newValue.startAccessingSecurityScopedResource()
                context.setEditing(true)
            } else {
                context.setEditing(false)
            }
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
                .focusEffectDisabled()
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
            itemsProvider: { dragItems(startingWith: item.id) },
            onOpen: { open(item.id) },
            onToggleSelect: { toggleSelection(item.id) },
            onRemove: { remove(item.id) },
            onDragStarted: { context.setEditing(true) },
            onDragFinished: { draggedIDs, performed in
                context.setEditing(false)
                guard performed, !draggedIDs.isEmpty else { return }
                store.consume(draggedIDs)
                selection.subtract(draggedIDs)
            },
            onSpacePressed: { showQuickLook(for: item.id) }
        )
        .task(id: item.id) {
            guard !isMissing, let url = store.url(for: item.id) else { return }
            thumbnailLoader.load(id: item.id, url: url)
        }
    }

    // MARK: Actions

    /// The (id, url) pairs a drag starting on `id` should carry: every selected item that's
    /// still resolvable when `id` is part of the current selection, otherwise just `id` on its
    /// own. Called lazily, right as a drag begins, never during view rendering. A missing
    /// selected item is silently left out, so it's never reported back as dragged or consumed.
    private func dragItems(startingWith id: ShelfItem.ID) -> [(id: ShelfItem.ID, url: URL)] {
        selectionOrSingle(id).compactMap { itemID in
            store.url(for: itemID).map { (itemID, $0) }
        }
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

    private func showQuickLook(for id: ShelfItem.ID) {
        guard let url = store.url(for: id) else { return }
        quickLookURL = url
    }
}
