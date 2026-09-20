import SwiftUI
import DesignSystem
import NotchWidgetAPI

/// The whole notch surface. Fills the panel; everything is placed from rects the controller
/// computed, so this view has no layout logic of its own.
struct NotchRootView: View {
    let model: NotchViewModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            // Fully transparent pixels let events fall through the window, so the live region is
            // painted at 1% opacity — invisible, but it keeps hover and drops working even when
            // the pill itself is hidden for a full-screen app.
            Rectangle()
                .fill(Color.black.opacity(0.01))
                .frame(width: model.hotRect.width, height: model.hotRect.height)
                .offset(x: model.hotRect.minX, y: model.hotRect.minY)

            SideNotchShape(edge: model.edge, flare: model.metrics.flare, cornerRadius: model.cornerRadius)
                .notchSurface(style: model.style, isFolded: model.state == .folded)
                .opacity(model.isGhosted && model.state == .folded ? 0 : 1)
                .frame(width: model.shapeRect.width, height: model.shapeRect.height)
                .offset(x: model.shapeRect.minX, y: model.shapeRect.minY)

            // A small overdue-reminder dot on the folded pill (spec §3.5). Read directly here in
            // `body` — not through a computed property on `NotchViewModel`, whose `widgets` array
            // is `@ObservationIgnored` — so SwiftUI's observation tracking, triggered by actually
            // evaluating `widget.badge` (which for `RemindersWidget` reads `RemindersStore.overdue`
            // through the existential), registers on that store property and this view redraws
            // when it changes.
            if model.state == .folded, !model.isGhosted, model.widgets.contains(where: { $0.badge == .dot }) {
                Circle()
                    .fill(Palette.secondaryText)
                    .frame(width: 4, height: 4)
                    .position(x: model.shapeRect.midX, y: model.shapeRect.midY)
            }

            let content = model.metrics.contentRect(in: model.shapeRect)
            stateContent
                .frame(width: content.width, height: content.height)
                .offset(x: content.minX, y: content.minY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var stateContent: some View {
        switch model.state {
        case .folded:
            EmptyView()
        case .tiles:
            TilesView(model: model)
                .transition(contentTransition)
        case .expanded(let id, let dropTarget):
            if let widget = model.widget(id) {
                ExpandedWidgetView(model: model, widget: widget, dropTarget: dropTarget)
                    .transition(contentTransition)
            }
        }
    }

    /// Deferred from M1: Reduce Motion (system or the Settings override) used to silence only the
    /// shape's spring — the tiles/expanded content still faded in on its own animation, attached
    /// directly to the transition rather than the outer `withAnimation`. `.identity` swaps content
    /// instantly, with no animation at all, the same way `updateShape` skips `withAnimation`.
    private var contentTransition: AnyTransition {
        model.reduceMotion ? .identity : .opacity.animation(NotchMotion.contents)
    }
}
