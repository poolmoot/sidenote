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
            // Read from Info.plist (fixed post-review: this used to be a URL literal in Swift),
            // via `AppIdentity.repositoryURL` — omitted entirely rather than guessed if the build
            // didn't set it.
            if let repositoryURL = identity.repositoryURL {
                Link("View on GitHub", destination: repositoryURL)
                    .font(.callout)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
