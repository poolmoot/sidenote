import NotchWidgetAPI

/// What the notch is showing.
public enum NotchState: Equatable, Sendable {
    case folded
    case tiles
    case expanded(WidgetID, dropTarget: Bool)

    public var isExpanded: Bool {
        if case .expanded = self { return true }
        return false
    }

    public var expandedWidget: WidgetID? {
        if case .expanded(let id, _) = self { return id }
        return nil
    }
}

/// Everything that can happen to the notch. Pointer and drag events come from the window,
/// timer events from `NotchController`, the rest from the user.
public enum NotchEvent: Equatable, Sendable {
    case pointerEntered
    case pointerExited
    case hoverDelayElapsed
    case graceElapsed
    case fileDragEntered
    case fileDragExited
    case fileDropped
    case tileSelected(WidgetID)
    case back
    case editingBegan
    case editingEnded
    case escape
    case resignedKey
    case shortcut(WidgetID)
    /// Opens the tiles from anywhere while folded, folds from anywhere otherwise — unlike
    /// `.hoverDelayElapsed`, this doesn't require the pointer to be inside the notch, so it can
    /// arrive while the pointer is nowhere near it. Not currently wired to the Settings ›
    /// Shortcuts "toggle the notch" shortcut, which an owner ruling redirected to toggling the
    /// notch's *visibility* (`Preferences.isNotchVisible`) instead — kept here as a tested,
    /// available primitive for a future "toggle the tiles" affordance.
    case toggleRequested
}

/// Side effects the controller must carry out after a transition.
public enum NotchEffect: Equatable, Sendable {
    case startHoverTimer
    case startGraceTimer
    case cancelTimers
    case makeKey
    case resignKey
}

/// The notch's behaviour as a pure value: no AppKit, no timers, no clock. `NotchController`
/// feeds it events and performs the effects it returns, which keeps every rule unit-testable.
public struct NotchStateMachine: Equatable, Sendable {
    public private(set) var state: NotchState = .folded
    public private(set) var isPointerInside = false
    public private(set) var isEditing = false
    /// The widget a file drag opens, or nil when no widget takes files. Settable via
    /// `updateActiveWidgets(dropWidget:knownWidgetIDs:)` — a disabled widget must stop taking
    /// drops and answering its shortcut without waiting for a relaunch.
    public private(set) var dropWidget: WidgetID?
    /// Every widget id the controller actually holds *and has enabled*. A `.shortcut(id)` for
    /// anything outside this set is ignored (deferred from M1: with the old fixed-enum `WidgetID`
    /// this could never happen, but a string-backed id can now name a widget that no longer
    /// exists, e.g. a stale shortcut assignment left over from a removed module — or one that
    /// still exists but was disabled in Settings › Widgets).
    private var knownWidgetIDs: Set<WidgetID>

    public init(dropWidget: WidgetID?, knownWidgetIDs: Set<WidgetID> = []) {
        self.dropWidget = dropWidget
        self.knownWidgetIDs = knownWidgetIDs
    }

    /// Rebuilds `dropWidget`/`knownWidgetIDs` from the currently active widget list — called by
    /// `NotchController` whenever `Preferences.enabledWidgetIDs` changes, so a disabled widget
    /// immediately stops taking file drops or answering its shortcut, and a re-enabled one starts
    /// again, with no relaunch needed.
    public mutating func updateActiveWidgets(dropWidget: WidgetID?, knownWidgetIDs: Set<WidgetID>) {
        self.dropWidget = dropWidget
        self.knownWidgetIDs = knownWidgetIDs
    }

    public mutating func handle(_ event: NotchEvent) -> [NotchEffect] {
        switch event {
        case .pointerEntered:
            isPointerInside = true
            return state == .folded ? [.startHoverTimer] : [.cancelTimers]

        case .pointerExited:
            isPointerInside = false
            switch state {
            case .folded: return [.cancelTimers]
            case .tiles: return [.startGraceTimer]
            case .expanded: return isEditing ? [] : [.startGraceTimer]
            }

        case .hoverDelayElapsed:
            guard state == .folded, isPointerInside else { return [] }
            state = .tiles
            return []

        case .graceElapsed:
            guard state != .folded, !isPointerInside, !isEditing else { return [] }
            return fold()

        case .fileDragEntered:
            guard let dropWidget else { return [] }
            isPointerInside = true
            isEditing = false
            state = .expanded(dropWidget, dropTarget: true)
            return [.cancelTimers]

        case .fileDragExited:
            guard case .expanded(let id, true) = state else { return [] }
            isPointerInside = false
            state = .expanded(id, dropTarget: false)
            return [.startGraceTimer]

        case .fileDropped:
            guard case .expanded(let id, true) = state else { return [] }
            isPointerInside = true
            state = .expanded(id, dropTarget: false)
            return []

        case .tileSelected(let id):
            guard state == .tiles else { return [] }
            state = .expanded(id, dropTarget: false)
            return [.cancelTimers, .makeKey]

        case .back:
            guard state.isExpanded else { return [] }
            isEditing = false
            state = .tiles
            return [.resignKey]

        case .editingBegan:
            guard state.isExpanded else { return [] }
            isEditing = true
            return [.cancelTimers]

        case .editingEnded:
            guard isEditing else { return [] }
            isEditing = false
            return state.isExpanded && !isPointerInside ? [.startGraceTimer] : []

        case .escape:
            guard state != .folded else { return [] }
            return fold()

        case .resignedKey:
            guard state.isExpanded else { return [] }
            return fold()

        case .shortcut(let id):
            guard knownWidgetIDs.contains(id) else { return [] }
            if state.expandedWidget == id { return fold() }
            isEditing = false
            state = .expanded(id, dropTarget: false)
            return [.cancelTimers, .makeKey]

        case .toggleRequested:
            if state == .folded {
                state = .tiles
                return []
            }
            return fold()
        }
    }

    private mutating func fold() -> [NotchEffect] {
        state = .folded
        isEditing = false
        return [.cancelTimers, .resignKey]
    }
}
