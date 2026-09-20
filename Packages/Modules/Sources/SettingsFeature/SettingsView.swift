import SwiftUI
import NotchWidgetAPI

/// The Settings window's content (spec §3.6): General, Appearance, Widgets, then whatever
/// feature-specific tabs the app target supplies (Shelf, Notes — each needs its own store, which
/// this module can't depend on without breaking the "features never import each other" rule),
/// Reminders, Shortcuts, About.
public struct SettingsView<ExtraTabs: View>: View {
    private let preferences: Preferences
    private let widgets: [any NotchWidget]
    private let extraTabs: () -> ExtraTabs

    public init(preferences: Preferences, widgets: [any NotchWidget], @ViewBuilder extraTabs: @escaping () -> ExtraTabs) {
        self.preferences = preferences
        self.widgets = widgets
        self.extraTabs = extraTabs
    }

    public var body: some View {
        TabView {
            GeneralSettingsView(preferences: preferences)
                .tabItem { Label("General", systemImage: "gearshape") }

            AppearanceSettingsView(preferences: preferences)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            WidgetsSettingsView(preferences: preferences, widgets: widgets)
                .tabItem { Label("Widgets", systemImage: "square.grid.2x2") }

            extraTabs()

            RemindersSettingsView(preferences: preferences)
                .tabItem { Label("Reminders", systemImage: "bell") }

            ShortcutsSettingsView(preferences: preferences, widgets: widgets)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
