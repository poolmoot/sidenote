import SwiftUI

/// The identifier of a mini app. String-backed (rather than a fixed enum) so a new widget needs no
/// edit to shared code: it just declares its own `WidgetID` constant. The raw value is what's
/// persisted (in `Preferences.enabledWidgetIDs`, shortcut assignments, and anywhere a saved widget
/// id lives), so never change an existing widget's raw value.
public struct WidgetID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let shelf = WidgetID(rawValue: "shelf")
    public static let notes = WidgetID(rawValue: "notes")
    public static let reminders = WidgetID(rawValue: "reminders")
}

extension WidgetID: CustomStringConvertible {
    public var description: String { rawValue }
}

/// A small mark the folded pill shows on behalf of a widget (e.g. an overdue reminder).
public enum WidgetBadge: Equatable, Sendable {
    case dot
}

/// What the notch hands a widget's view, so the view can talk back without knowing about windows.
@MainActor
public struct WidgetContext {
    /// Report that a text field gained (`true`) or lost (`false`) focus. While editing, the notch
    /// does not fold when the pointer leaves.
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
