import CoreGraphics
import Observation
import NotchWidgetAPI

/// Everything the SwiftUI notch draws, pushed in by `NotchController`, plus the user's intents
/// flowing back out. Views never compute geometry themselves.
@MainActor
@Observable
final class NotchViewModel {
    var state: NotchState = .folded
    var edge: NotchEdge = .right
    var metrics = NotchMetrics.standard
    /// The visible shape, in panel coordinates (top-left origin).
    var shapeRect: CGRect = .zero
    /// The region that takes hover and drops; drawn near-transparent so it receives events.
    var hotRect: CGRect = .zero
    var cornerRadius: CGFloat = NotchMetrics.standard.foldedCornerRadius
    /// True while a full-screen app is in front: the folded pill is not drawn, but stays live.
    var isGhosted = false
    @ObservationIgnored var widgets: [any NotchWidget] = []

    @ObservationIgnored var onSelect: (WidgetID) -> Void = { _ in }
    @ObservationIgnored var onBack: () -> Void = {}
    @ObservationIgnored var onOpenSettings: () -> Void = {}
    @ObservationIgnored var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservationIgnored var onClose: () -> Void = {}

    func widget(_ id: WidgetID) -> (any NotchWidget)? {
        widgets.first { $0.id == id }
    }

    var widgetContext: WidgetContext {
        WidgetContext(
            setEditing: { [weak self] in self?.onEditingChanged($0) },
            close: { [weak self] in self?.onClose() }
        )
    }
}
