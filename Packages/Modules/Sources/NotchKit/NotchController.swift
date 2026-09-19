import AppKit
import SwiftUI
import AppInfo
import DesignSystem
import NotchWidgetAPI

/// Owns the notch window and runs its state machine.
///
/// Performance contract: while folded, nothing here runs. Hover, drags, screen and space changes
/// all arrive as events; the only timers are the one-shot hover and grace delays, and they exist
/// only for the moment a transition is pending.
@MainActor
public final class NotchController {
    public var onOpenSettings: () -> Void = {}
    /// Called when an ⌥-drag ends, with the new offset to persist.
    public var onAlongOffsetCommitted: (CGFloat) -> Void = { _ in }
    public var contextMenuProvider: () -> NSMenu? = { nil }

    public private(set) var configuration: NotchConfiguration
    public var state: NotchState { machine.state }

    private let widgets: [any NotchWidget]
    private let metrics = NotchMetrics.standard
    private var machine: NotchStateMachine
    private let model = NotchViewModel()
    private let panel = NotchPanel()
    private let container = NotchContainerView(frame: .zero)
    private lazy var fullScreen = FullScreenObserver { [weak self] in self?.currentScreen() }
    private var hoverTask: Task<Void, Never>?
    private var graceTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private let log = AppIdentity.current.logger("notch")

    public init(widgets: [any NotchWidget], configuration: NotchConfiguration) {
        self.widgets = widgets
        self.configuration = configuration
        machine = NotchStateMachine(dropWidget: widgets.first { $0.acceptsFileDrops }?.id)

        let hosting = NotchHostingView(rootView: NotchRootView(model: model))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container

        model.widgets = widgets
        model.metrics = metrics
        wire()
    }

    /// Puts the notch on screen and starts listening for screen and space changes.
    public func start() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        fullScreen.start()
        layout()
        applyVisibility()
    }

    public func apply(_ newValue: NotchConfiguration) {
        let old = configuration
        configuration = newValue
        if old.edge != newValue.edge || old.displayID != newValue.displayID || old.alongOffset != newValue.alongOffset {
            layout()
        }
        if old.isVisible != newValue.isVisible {
            applyVisibility()
        }
        if old.hidesInFullScreen != newValue.hidesInFullScreen {
            updateGhosting()
        }
    }

    /// Feeds one event through the state machine and carries out what it asks for.
    public func send(_ event: NotchEvent) {
        let before = machine.state
        let effects = machine.handle(event)
        effects.forEach(perform)
        // Any expanded state may become key, including one opened by a file drag (which emits no
        // .makeKey effect) — becomesKeyOnlyIfNeeded means this alone never steals focus.
        panel.allowsKey = machine.state.isExpanded
        if machine.state != before {
            log.debug("\(String(describing: before), privacy: .public) → \(String(describing: self.machine.state), privacy: .public)")
            updateShape(animated: true)
        }
    }

    // MARK: Wiring

    private func wire() {
        container.onPointerEntered = { [weak self] in self?.send(.pointerEntered) }
        container.onPointerExited = { [weak self] in self?.send(.pointerExited) }
        container.onFileDragEntered = { [weak self] in self?.send(.fileDragEntered) }
        container.onFileDragExited = { [weak self] in self?.send(.fileDragExited) }
        container.onFileDrop = { [weak self] urls in self?.drop(urls) ?? false }

        panel.onEscape = { [weak self] in self?.send(.escape) }
        // Spec §3.1: clicking outside the notch folds it, even while editing — that must not be
        // swallowed just because a widget holds the editing lock. But losing key status while
        // editing can also be *our own doing and nothing else* (e.g. Quick Look's preview panel
        // taking key to show a file) — in that case the app is still active, just a different one
        // of our own windows is key, and folding would dismiss the preview it belongs to. So the
        // two are told apart by `NSApp.isActive`: still active + editing means key moved inside
        // this app; not active means the user genuinely left, and that always folds regardless of
        // the editing lock. The state machine's own .resignedKey rule is untouched (still folds
        // unconditionally whenever expanded, and its test still passes) — this is a
        // controller-level guard for the one specific case that must not reach it.
        panel.onResignKey = { [weak self] in
            guard let self else { return }
            if machine.isEditing, NSApp.isActive { return }
            send(.resignedKey)
        }
        panel.contextMenuProvider = { [weak self] in self?.contextMenuProvider() }
        panel.onDragStart = { [weak self] in self?.cancelTimers() }
        panel.onDrag = { [weak self] _, dy in self?.slide(by: dy) }
        panel.onDragEnd = { [weak self] in
            guard let self else { return }
            onAlongOffsetCommitted(configuration.alongOffset)
        }

        model.onSelect = { [weak self] in self?.send(.tileSelected($0)) }
        model.onBack = { [weak self] in self?.send(.back) }
        model.onClose = { [weak self] in self?.send(.escape) }
        model.onEditingChanged = { [weak self] isEditing in
            guard let self else { return }
            send(isEditing ? .editingBegan : .editingEnded)
            // A drag (and, transitively, a Quick Look preview holding the lock) suppresses
            // ordinary tracking events for its duration, so the container's notion of where the
            // pointer is goes stale. Re-learn it whenever a widget lets go of the lock, the same
            // way `concludeDragOperation` already does for an incoming file drag.
            if !isEditing { container.syncPointer() }
        }
        model.onOpenSettings = { [weak self] in
            self?.send(.escape)
            self?.onOpenSettings()
        }

        fullScreen.onChange = { [weak self] _ in self?.updateGhosting() }
    }

    // MARK: Effects

    private func perform(_ effect: NotchEffect) {
        switch effect {
        case .startHoverTimer:
            hoverTask?.cancel()
            hoverTask = after(configuration.hoverDelay) { [weak self] in self?.send(.hoverDelayElapsed) }
        case .startGraceTimer:
            graceTask?.cancel()
            graceTask = after(configuration.graceDelay) { [weak self] in self?.send(.graceElapsed) }
        case .cancelTimers:
            cancelTimers()
        case .makeKey:
            panel.allowsKey = true
            panel.makeKey()
        case .resignKey:
            panel.relinquishKey()
        }
    }

    private func after(_ delay: Duration, _ action: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    private func cancelTimers() {
        hoverTask?.cancel()
        graceTask?.cancel()
        hoverTask = nil
        graceTask = nil
    }

    // MARK: Layout

    private func currentScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let index = NotchGeometry.preferredScreenIndex(
            displayIDs: screens.map(\.displayIdentifier),
            preferred: configuration.displayID
        )
        return index.map { screens[$0] }
    }

    /// Re-places the panel: on start, on screen changes and when the edge or display changes.
    private func layout() {
        guard let screen = currentScreen() else { return }
        let depth = metrics.panelDepth(expandedSizes: widgets.map(\.expandedSize))
        let frame = NotchGeometry.panelFrame(screenFrame: screen.frame, edge: configuration.edge, depth: depth)
        panel.setFrame(frame, display: false)
        model.edge = configuration.edge
        updateShape(animated: false)
    }

    private var expandedSizes: [WidgetID: CGSize] {
        Dictionary(uniqueKeysWithValues: widgets.map { ($0.id, $0.expandedSize) })
    }

    /// Moves the shape to match the current state. The panel frame never changes here — only the
    /// shape inside it animates — so the window is never resized per animation frame.
    private func updateShape(animated: Bool) {
        let state = machine.state
        let size = metrics.shapeSize(for: state, tileCount: widgets.count, expandedSizes: expandedSizes)
        let rect = NotchGeometry.shapeRect(
            panelSize: panel.frame.size, edge: configuration.edge, size: size, alongOffset: configuration.alongOffset
        )
        let hot = NotchGeometry.hotRect(
            shapeRect: rect,
            edge: configuration.edge,
            margin: state == .folded ? metrics.foldedHoverMargin : metrics.hoverMargin,
            lengthInset: state == .folded ? metrics.flare : 0
        )
        let radius = metrics.cornerRadius(for: state)

        model.hotRect = hot
        let apply = { [model] in
            model.state = state
            model.shapeRect = rect
            model.cornerRadius = radius
        }
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            withAnimation(NotchMotion.unfold, apply)
        } else {
            apply()
        }
        container.setHotRect(hot)
    }

    /// The pill only disappears under a full-screen app when the user asked for that.
    private func updateGhosting() {
        model.isGhosted = configuration.hidesInFullScreen && fullScreen.isFullScreen
    }

    private func applyVisibility() {
        if configuration.isVisible {
            panel.orderFrontRegardless()
            container.syncPointer()
        } else {
            cancelTimers()
            send(.escape)
            panel.orderOut(nil)
        }
    }

    // MARK: Drops and dragging

    private func drop(_ urls: [URL]) -> Bool {
        defer { send(.fileDropped) }
        guard let id = machine.state.expandedWidget,
              let widget = model.widget(id),
              widget.acceptsFileDrops
        else { return false }
        return widget.handleFileDrop(urls)
    }

    private func slide(by dy: CGFloat) {
        let folded = metrics.shapeSize(for: .folded, tileCount: widgets.count, expandedSizes: expandedSizes)
        configuration.alongOffset = NotchGeometry.clampedOffset(
            configuration.alongOffset + dy, panelLength: panel.frame.height, length: folded.length
        )
        updateShape(animated: false)
    }
}
