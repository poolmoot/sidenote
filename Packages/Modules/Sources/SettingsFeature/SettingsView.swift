import SwiftUI

/// The Settings window's content. M1 has the General tab; later milestones add the rest.
public struct SettingsView: View {
    private let preferences: Preferences

    public init(preferences: Preferences) {
        self.preferences = preferences
    }

    public var body: some View {
        TabView {
            GeneralSettingsView(preferences: preferences)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
