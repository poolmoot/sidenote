import AppKit
import AppInfo

/// The menu bar icon. The same menu is shown when the notch is right-clicked.
@MainActor
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private let isNotchVisible: () -> Bool
    private let onOpenSettings: () -> Void
    private let onToggleNotch: () -> Void

    init(isNotchVisible: @escaping () -> Bool, onOpenSettings: @escaping () -> Void, onToggleNotch: @escaping () -> Void) {
        self.isNotchVisible = isNotchVisible
        self.onOpenSettings = onOpenSettings
        self.onToggleNotch = onToggleNotch
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: AppIdentity.current.name)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// A fresh menu reflecting the current state.
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        populate(menu)
        return menu
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        let toggle = menu.addItem(
            withTitle: isNotchVisible() ? "Hide Notch" : "Show Notch",
            action: #selector(toggleNotch),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit \(AppIdentity.current.name)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
    }

    @objc private func openSettings() { onOpenSettings() }
    @objc private func toggleNotch() { onToggleNotch() }
}

extension StatusItemController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }
}
