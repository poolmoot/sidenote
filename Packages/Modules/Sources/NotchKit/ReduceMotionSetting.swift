/// Settings › Appearance's "Reduce motion" override (spec §3.6): follow the system accessibility
/// setting, or force motion on/off regardless of it.
public enum ReduceMotionSetting: String, CaseIterable, Codable, Sendable, Identifiable {
    case system
    case always
    case never

    public var id: String { rawValue }
}
