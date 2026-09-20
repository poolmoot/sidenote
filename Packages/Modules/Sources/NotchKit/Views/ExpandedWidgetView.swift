import SwiftUI
import DesignSystem
import NotchWidgetAPI

/// An open mini app: a header with a back chevron, then the widget's own view.
struct ExpandedWidgetView: View {
    let model: NotchViewModel
    let widget: any NotchWidget
    let dropTarget: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: model.onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back")
                .accessibilityLabel("Back")
                Image(systemName: widget.systemImage)
                Text(widget.title)
                    .font(.headline)
                Spacer()
            }
            .foregroundStyle(Palette.primaryText)

            widget.makeExpandedView(context: model.widgetContext)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay {
            if dropTarget {
                // `model.accentColor`, not `Palette.dropHighlight` — tracked, so a Settings ›
                // Appearance change re-renders this border live (fixed post-review).
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(model.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .overlay(Text("Drop here").font(.headline).foregroundStyle(Palette.primaryText))
                    .background(Palette.notch.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
