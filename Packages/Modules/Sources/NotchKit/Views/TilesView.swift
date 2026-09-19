import SwiftUI
import DesignSystem
import NotchWidgetAPI

/// The unfolded column: one tile per enabled widget, then the Settings gear.
struct TilesView: View {
    let model: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(model.widgets, id: \.id) { widget in
                TileButton(title: widget.title, systemImage: widget.systemImage) {
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
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.primaryText)
                .frame(width: 40, height: 40)
                .background(isHovering ? Palette.tileHover : Palette.tileFill, in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .onHover { isHovering = $0 }
    }
}
