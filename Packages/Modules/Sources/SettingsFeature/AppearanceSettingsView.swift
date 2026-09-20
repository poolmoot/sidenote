import AppKit
import SwiftUI
import NotchKit
import DesignSystem

/// Settings › Appearance: style, pill size, accent colour, hover delay, reduce motion (spec §3.6).
struct AppearanceSettingsView: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section("Style") {
                Picker("Style", selection: $preferences.style) {
                    ForEach(NotchStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Pill size", selection: $preferences.pillSize) {
                    ForEach(PillSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)

                ColorPicker("Accent colour", selection: accentColorBinding, supportsOpacity: false)
            }

            Section("Motion") {
                Slider(value: $preferences.hoverDelaySeconds, in: Preferences.hoverDelayRange) {
                    Text("Hover delay")
                } minimumValueLabel: {
                    Text("Fast")
                } maximumValueLabel: {
                    Text("Slow")
                }

                Picker("Reduce motion", selection: $preferences.reduceMotion) {
                    ForEach(ReduceMotionSetting.allCases) { setting in
                        Text(setting.title).tag(setting)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var accentColorBinding: Binding<Color> {
        Binding(
            get: { preferences.accentColor.color },
            set: { preferences.accentColor = AccentColor(nsColor: NSColor($0)) }
        )
    }
}

private extension AccentColor {
    /// Extracts sRGB-ish components from whatever colour space `NSColor(Color)` handed back.
    /// Falls back to `.systemBlue` for a colour (e.g. a pattern or catalog colour) that can't
    /// convert to device RGB, rather than crashing or silently keeping a stale value.
    init(nsColor: NSColor) {
        guard let converted = nsColor.usingColorSpace(.deviceRGB) else {
            self = .systemBlue
            return
        }
        self.init(red: Double(converted.redComponent), green: Double(converted.greenComponent), blue: Double(converted.blueComponent))
    }
}

private extension ReduceMotionSetting {
    var title: String {
        switch self {
        case .system: "System"
        case .always: "Always"
        case .never: "Never"
        }
    }
}
