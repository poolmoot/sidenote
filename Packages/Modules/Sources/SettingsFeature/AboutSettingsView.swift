import SwiftUI
import AppInfo

/// Settings › About: app name, version, build, a link to the repository (spec §3.6).
struct AboutSettingsView: View {
    private let identity = AppIdentity.current

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sidebar.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(identity.name)
                .font(.title2.bold())
            Text("Version \(identity.version) (\(identity.build))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Link("View on GitHub", destination: AboutSettingsView.repositoryURL)
                .font(.callout)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private static let repositoryURL = URL(string: "https://github.com/poolmoot/sidenote")!
}
