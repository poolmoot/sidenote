import CoreGraphics
import SwiftUI
import Observation
import DesignSystem
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
    /// The enabled widgets, in the user's chosen order (spec §3.6 Widgets tab) — exactly what
    /// `TilesView` renders and what the folded-pill badge check scans. Deliberately NOT
    /// `@ObservationIgnored`, unlike the rest of this file's collections: it now reacts live when
    /// `Preferences.enabledWidgetIDs` changes (see `NotchController.apply(_:)`), so `TilesView`
    /// must actually re-render when it does.
    var widgets: [any NotchWidget] = []
    /// Every widget the app registered, enabled or not, keyed by id — used to resolve an expanded
    /// widget's view and a file-drag's drop target regardless of whether it currently has a tile.
    /// Set once at construction; unlike `widgets`, this never changes at runtime.
    @ObservationIgnored private var registry: [WidgetID: any NotchWidget] = [:]
    /// Whether the current transition should skip its fade (Settings › Appearance ›
    /// "Reduce motion", or the system setting) — deferred from M1: previously this only silenced
    /// the shape's spring, not the tiles/expanded content transition.
    var reduceMotion = false
    /// Solid black or Liquid Glass (spec §3.6, §5).
    var style: NotchStyle = .solid
    /// The user's accent colour, tracked so tile hover/selection and the drop-target border
    /// re-render live when Settings › Appearance changes it (see `NotchConfiguration.accentColor`).
    var accentColor: Color = .accentColor

    @ObservationIgnored var onSelect: (WidgetID) -> Void = { _ in }
    @ObservationIgnored var onBack: () -> Void = {}
    @ObservationIgnored var onOpenSettings: () -> Void = {}
    @ObservationIgnored var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservationIgnored var onClose: () -> Void = {}

    func setRegistry(_ all: [any NotchWidget]) {
        registry = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func widget(_ id: WidgetID) -> (any NotchWidget)? {
        registry[id]
    }

    var widgetContext: WidgetContext {
        WidgetContext(
            setEditing: { [weak self] in self?.onEditingChanged($0) },
            close: { [weak self] in self?.onClose() }
        )
    }
}
