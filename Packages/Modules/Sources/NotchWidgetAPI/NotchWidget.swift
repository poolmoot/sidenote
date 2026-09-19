import SwiftUI

/// The three mini apps. The raw value is persisted, so never rename a case.
public enum WidgetID: String, CaseIterable, Codable, Sendable {
    case shelf
    case notes
    case reminders
}

/// A small mark the folded pill shows on behalf of a widget (e.g. an overdue reminder).
public enum WidgetBadge: Equatable, Sendable {
    case dot
}

/// What the notch hands a widget's view, so the view can talk back without knowing about windows.
@MainActor
public struct WidgetContext {
    /// Report that a text field gained (`true`) or lost (`false`) focus. While editing, the notch
    /// does not fold when the pointer leaves it.
    public let setEditing: (Bool) -> Void
    /// Fold the notch, e.g. after an action that finishes the user's task.
    public let close: () -> Void

    public init(setEditing: @escaping (Bool) -> Void, close: @escaping () -> Void) {
        self.setEditing = setEditing
        self.close = close
    }
}

/// The only contract between the notch and a mini app. Feature modules conform to this and never
/// import NotchKit.
@MainActor
public protocol NotchWidget: AnyObject {
    var id: WidgetID { get }
    var title: String { get }
    /// An SF Symbol name.
    var systemImage: String { get }
    /// The expanded panel: `width` is the depth in from the screen edge, `height` the length along it.
    var expandedSize: CGSize { get }
    var acceptsFileDrops: Bool { get }
    var badge: WidgetBadge? { get }
    func makeExpandedView(context: WidgetContext) -> AnyView
    /// Called only when `acceptsFileDrops` is true. Returns whether the drop was taken.
    func handleFileDrop(_ urls: [URL]) -> Bool
}

public extension NotchWidget {
    var acceptsFileDrops: Bool { false }
    var badge: WidgetBadge? { nil }
    func handleFileDrop(_ urls: [URL]) -> Bool { false }
}
