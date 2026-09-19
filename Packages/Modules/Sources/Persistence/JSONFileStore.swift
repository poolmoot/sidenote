import Foundation
import os
import AppInfo

/// Writes `data` to `url` atomically, creating the containing directory if needed. A free
/// function (not a method) so it carries no actor isolation and can run safely off the main
/// actor from a background queue. Always uses `FileManager.default`: that instance's methods are
/// documented thread-safe, unlike the `FileManager` type itself, which isn't `Sendable`.
private func writeAtomically(_ data: Data, to url: URL, logger: Logger) {
    let fileManager = FileManager.default
    do {
        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try data.write(to: url, options: .atomic)
    } catch {
        logger.error("Failed to write \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
    }
}

/// A single `Codable` value persisted to one JSON file.
///
/// Writes are atomic and debounced: `save` coalesces rapid changes into one write roughly
/// `debounceInterval` after the last call, performed off the main actor so it never blocks the
/// UI. `flush` writes any pending value immediately and synchronously, for use on fold and at
/// app termination.
///
/// A file that fails to decode is quarantined (renamed `<name>.corrupt-<timestamp>.json`) and
/// `load()` returns `nil`, so the caller starts empty rather than crashing on old or damaged data.
@MainActor
public final class JSONFileStore<Value: Codable> {
    private let url: URL
    private let fileManager: FileManager
    private let logger: Logger
    private let debounceInterval: Duration
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let writeQueue = DispatchQueue(label: "JSONFileStore.write", qos: .utility)

    private var pendingValue: Value?
    private var debounceTask: Task<Void, Never>?

    public init(
        url: URL,
        fileManager: FileManager = .default,
        logger: Logger = AppIdentity.current.logger("persistence"),
        debounceInterval: Duration = .milliseconds(500)
    ) {
        self.url = url
        self.fileManager = fileManager
        self.logger = logger
        self.debounceInterval = debounceInterval
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    /// The persisted value, or `nil` if there is none yet, the file couldn't be decoded, or it
    /// decoded fine but failed `isValid` (e.g. a schema `version` this build doesn't understand).
    /// Either failure quarantines the file rather than handing back data a caller doesn't expect —
    /// silently accepting an unrecognized future version is how a downgrade corrupts a document.
    public func load(isValid: (Value) -> Bool = { _ in true }) -> Value? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try decoder.decode(Value.self, from: data)
            guard isValid(decoded) else {
                logger.error("Rejecting \(self.url.lastPathComponent, privacy: .public): failed validation.")
                quarantine()
                return nil
            }
            return decoded
        } catch {
            logger.error("Failed to decode \(self.url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            quarantine()
            return nil
        }
    }

    /// Schedules a debounced write of `value`. Superseded by any later `save` before it fires.
    public func save(_ value: Value) {
        pendingValue = value
        debounceTask?.cancel()
        debounceTask = Task { [weak self, debounceInterval] in
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            self?.writePending(synchronously: false)
        }
    }

    /// Writes the pending value now, blocking until the write completes. A no-op when nothing is
    /// pending.
    public func flush() {
        debounceTask?.cancel()
        debounceTask = nil
        writePending(synchronously: true)
    }

    private func writePending(synchronously: Bool) {
        guard let value = pendingValue else { return }
        pendingValue = nil
        do {
            let data = try encoder.encode(value)
            let url = self.url
            let logger = self.logger
            if synchronously {
                writeQueue.sync { writeAtomically(data, to: url, logger: logger) }
            } else {
                writeQueue.async { writeAtomically(data, to: url, logger: logger) }
            }
        } catch {
            logger.error("Failed to encode \(self.url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func quarantine() {
        let timestamp = Int(Date().timeIntervalSince1970)
        let baseName = url.deletingPathExtension().lastPathComponent
        let corruptURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(baseName).corrupt-\(timestamp).json")
        try? fileManager.removeItem(at: corruptURL)
        try? fileManager.moveItem(at: url, to: corruptURL)
    }
}
