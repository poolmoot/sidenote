import SwiftUI
import DesignSystem
import NotchWidgetAPI

/// The unfolded column: one tile per enabled widget, then the Settings gear.
struct TilesView: View {
    let model: NotchViewModel

    /// The tile's square side, derived from the tiles column's own depth rather than a fixed
    /// 40×40 (fixed post-review: at pill size S that overflowed the column, at L it looked
    /// undersized). `tilesDepth` already scales with `PillSize`; `contentPadding` doesn't, so this
    /// tracks the actual space available inside the column at every size.
    private var tileSquareSide: CGFloat {
        let available = model.metrics.tilesDepth - 2 * model.metrics.contentPadding
        return min(max(available, 24), 56)
    }

    private var tileIconSize: CGFloat {
        tileSquareSide * 0.45
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(model.widgets, id: \.id) { widget in
                TileButton(
                    title: widget.title,
                    systemImage: widget.systemImage,
                    squareSide: tileSquareSide,
                    iconSize: tileIconSize,
                    accentColor: model.accentColor
                ) {
                    model.onSelect(widget.id)
                }
                .frame(height: model.metrics.tileExtent)
            }
            Button(action: model.onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
            .frame(height: model.metrics.gearExtent)
        }
    }
}

private struct TileButton: View {
    let title: String
    let systemImage: String
    let squareSide: CGFloat
    let iconSize: CGFloat
    /// The user's accent colour (spec §3.6 Appearance), read from `NotchViewModel` — which is
    /// `@Observable`-tracked, unlike `Palette.accent` — so a change re-renders this tile live.
    let accentColor: Color
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(Palette.primaryText)
                .frame(width: squareSide, height: squareSide)
                .background(isHovering ? accentColor.opacity(0.35) : Palette.tileFill, in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .onHover { isHovering = $0 }
    }
}
