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
    let dragURLsProvider: () -> [URL]
    let onOpen: () -> Void
    let onToggleSelect: () -> Void
    let onRemove: () -> Void
    let onDragFinished: (Bool) -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                thumbnailView
                    .frame(width: 56, height: 56)
                    .opacity(isMissing ? 0.4 : 1)
                    .background(Palette.tileFill, in: RoundedRectangle(cornerRadius: 8))

                if isHovering {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                    .accessibilityLabel("Remove \(item.displayName)")
                }
            }

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
        .onHover { isHovering = $0 }
        .overlay {
            if !isMissing {
                FileDragSource(
                    urlsProvider: dragURLsProvider,
                    onClick: { isCommandDown in
                        if isCommandDown {
                            onToggleSelect()
                        } else {
                            onOpen()
                        }
                    },
                    onDragFinished: onDragFinished
                )
            }
        }
        .contentShape(Rectangle())
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
