import Foundation
import AppInfo

/// Where this app keeps its content files: `Application Support/<AppName>/` inside the sandbox
/// container, created on first use.
public enum AppPaths {
    /// The app's Application Support directory, creating it if it doesn't exist yet.
    public static func applicationSupportDirectory(
        fileManager: FileManager = .default,
        identity: AppIdentity = .current
    ) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(identity.name, isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// The URL of `shelf.json`, inside `applicationSupportDirectory`.
    public static func shelfFile(
        fileManager: FileManager = .default,
        identity: AppIdentity = .current
    ) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager, identity: identity)
            .appendingPathComponent("shelf.json")
    }
}
