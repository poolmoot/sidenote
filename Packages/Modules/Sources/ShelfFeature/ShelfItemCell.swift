import SwiftUI
import DesignSystem

/// One tile in the shelf grid: thumbnail, name, a hover ✕ to remove, and a "Missing" label when
/// the original can't be resolved. Click opens the file; ⌘-click toggles selection; dragging it
/// out copies the original (`FileDragSource`) — all reported through closures, so this view knows
/// nothing about `ShelfStore`.
struct ShelfItemCell: View {
    let item: ShelfItem
    let isMissing: Bool
    let isSelected: Bool
    let thumbnail: NSImage?
    let itemsProvider: () -> [(id: ShelfItem.ID, url: URL)]
    let onOpen: () -> Void
    let onToggleSelect: () -> Void
    let onRemove: () -> Void
    let onDragStarted: () -> Void
    let onDragFinished: (Set<ShelfItem.ID>, Bool) -> Void
    let onSpacePressed: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            thumbnailView
                .frame(width: 56, height: 56)
                .opacity(isMissing ? 0.4 : 1)
                .background(Palette.tileFill, in: RoundedRectangle(cornerRadius: 8))

            Text(item.displayName)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isMissing ? Palette.secondaryText : Palette.primaryText)

            if isMissing {
                Text("Missing")
                    .font(.caption2.bold())
                    .foregroundStyle(.red)
            }
        }
        .padding(6)
        .frame(width: 76)
        .background(isSelected ? Palette.tileHover : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        // The drag source sits below the ✕: it's an AppKit `NSView` that would otherwise swallow
        // every mouse-down in the cell, including a click meant for the button layered on top of
        // it. Hover is driven by `.onHover` on this same outer view (not from anything under the
        // NSView), so it isn't at the mercy of what that view does with mouse events.
        .overlay {
            if !isMissing {
                FileDragSource(
                    itemsProvider: itemsProvider,
                    onClick: { isCommandDown in
                        if isCommandDown {
                            onToggleSelect()
                        } else {
                            onOpen()
                        }
                    },
                    onDragStarted: onDragStarted,
                    onDragFinished: onDragFinished,
                    onSpacePressed: onSpacePressed
                )
            }
        }
        // Anchored to the tile (so it stays above the drag source in hit-testing — see the
        // overlay above), but offset back in to sit at the thumbnail's corner rather than the
        // wider tile's: the thumbnail is inset ~10pt from the tile's edges (56pt thumbnail
        // centered under the ~64pt content width the grid gives this cell, plus 6pt padding), and
        // the top edges of thumbnail and tile coincide once that same padding is undone.
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .offset(x: -4, y: 0)
                .accessibilityLabel("Remove \(item.displayName)")
            }
        }
        .onHover { isHovering = $0 }
        .onTapGesture {
            // Missing items have no drag source overlay to field the click, so handle it here.
            guard isMissing else { return }
            if NSEvent.modifierFlags.contains(.command) {
                onToggleSelect()
            }
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(4)
        } else {
            Image(systemName: "doc")
                .font(.system(size: 22))
                .foregroundStyle(Palette.secondaryText)
        }
    }
}
