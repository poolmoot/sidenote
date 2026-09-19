/// Which side of the screen the notch is attached to. The raw value is persisted.
public enum NotchEdge: String, CaseIterable, Codable, Sendable, Identifiable {
    case left
    case right

    public var id: String { rawValue }
}
