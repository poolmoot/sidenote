import AppKit

/// Tells the controller when a full-screen app comes to the front of the notch's display.
///
/// Event-driven only: it re-checks when macOS announces a space change or an app activation (and
/// once more shortly after, since space transitions animate). There is no polling timer.
@MainActor
final class FullScreenObserver {
    var onChange: ((Bool) -> Void)?
    private(set) var isFullScreen = false

    private let screen: () -> NSScreen?
    private var tokens: [NSObjectProtocol] = []
    private var followUp: Task<Void, Never>?

    init(screen: @escaping () -> NSScreen?) {
        self.screen = screen
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.spaceOrAppChanged() }
            }
            tokens.append(token)
        }
        evaluate()
    }

    func stop() {
        tokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        tokens.removeAll()
        followUp?.cancel()
    }

    /// Re-checks immediately, for a change `start()`'s notifications don't cover — e.g. the
    /// notch moving to a different screen or edge (deferred from M1). A no-op call when the
    /// answer hasn't changed, same as the notification-driven path.
    func refresh() {
        evaluate()
    }

    private func spaceOrAppChanged() {
        evaluate()
        followUp?.cancel()
        followUp = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }

    private func evaluate() {
        guard let screen = screen() else { return }
        let value = FullScreenDetector.isFullScreenAppFrontmost(on: screen)
        guard value != isFullScreen else { return }
        isFullScreen = value
        onChange?(value)
    }
}
