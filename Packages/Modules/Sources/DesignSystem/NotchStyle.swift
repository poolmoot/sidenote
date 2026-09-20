/// The notch's visual style (spec §3.6, §5): plain black, or macOS 26's Liquid Glass material.
public enum NotchStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case solid
    case liquidGlass

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .solid: "Solid black"
        case .liquidGlass: "Liquid Glass"
        }
    }
}
