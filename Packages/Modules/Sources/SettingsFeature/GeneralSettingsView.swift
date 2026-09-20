import AppKit
import SwiftUI
import NotchKit

/// Settings › General: where the notch lives and whether the app starts at login.
struct GeneralSettingsView: View {
    @Bindable var preferences: Preferences
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("Position") {
                Picker("Screen edge", selection: $preferences.edge) {
                    ForEach(NotchEdge.allCases) { edge in
                        Text(edge.title).tag(edge)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Display", selection: $preferences.displayID) {
                    Text("Primary display").tag(String?.none)
                    ForEach(DisplayOption.connected()) { display in
                        Text(display.name).tag(Optional(display.id))
                    }
                }

                LabeledContent("Position along edge") {
                    Button("Reset") { preferences.resetPosition() }
                }
                Text("Tip: hold ⌥ and drag the notch to slide it along the edge.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle("Hide under full-screen apps", isOn: $preferences.hidesInFullScreen)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                if let launchError {
                    Text(launchError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Only flips the toggle once registration actually succeeded.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                do {
                    try LaunchAtLogin.setEnabled(newValue)
                    launchAtLogin = newValue
                    launchError = nil
                } catch {
                    launchError = "Couldn't change the login item: \(error.localizedDescription)"
                }
            }
        )
    }
}

extension NotchEdge {
    var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        }
    }
}

/// A connected display the notch can be placed on.
struct DisplayOption: Identifiable, Hashable {
    let id: String
    let name: String

    @MainActor
    static func connected() -> [DisplayOption] {
        NSScreen.screens.compactMap { screen in
            screen.displayIdentifier.map { DisplayOption(id: $0, name: screen.localizedName) }
        }
    }
}
