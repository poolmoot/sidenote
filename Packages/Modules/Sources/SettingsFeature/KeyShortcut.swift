import Foundation
import NotchWidgetAPI

/// A single global keyboard shortcut: a virtual key code plus modifier flags (spec §4.8). Plain
/// values rather than anything Carbon- or `NSEvent`-specific, so this module — and `Preferences`,
/// which persists it — never needs to import Carbon. The app target's `ShortcutCenter` is the only
/// place that translates this into an actual registration.
public struct KeyShortcut: Equatable, Codable, Sendable {
    /// The physical key, as `NSEvent.keyCode` reports it.
    public var keyCode: UInt16
    /// `NSEvent.ModifierFlags.rawValue`, masked to the four shortcut-relevant flags (command,
    /// option, control, shift) by whoever records this — this type doesn't enforce that itself.
    public var modifiers: UInt

    public init(keyCode: UInt16, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Modifier flags this type cares about, matching `NSEvent.ModifierFlags`' raw bits — kept
    /// here as plain numbers (rather than importing AppKit into this module) since only the bit
    /// positions matter for formatting and masking.
    private enum ModifierBit {
        static let control: UInt = 1 << 18
        static let option: UInt = 1 << 19
        static let shift: UInt = 1 << 17
        static let command: UInt = 1 << 20
    }

    /// "⌃⌥⇧⌘R" — the conventional macOS modifier order, then the key's label. Falls back to
    /// "Key <code>" for a virtual key code this table doesn't recognize (function-testable without
    /// needing every one of the ~130 codes covered).
    public var displayString: String {
        var symbols = ""
        if modifiers & ModifierBit.control != 0 { symbols += "\u{2303}" }
        if modifiers & ModifierBit.option != 0 { symbols += "\u{2325}" }
        if modifiers & ModifierBit.shift != 0 { symbols += "\u{21E7}" }
        if modifiers & ModifierBit.command != 0 { symbols += "\u{2318}" }
        return symbols + (KeyShortcut.keyLabels[keyCode] ?? "Key \(keyCode)")
    }

    /// Virtual key codes for the keys someone is actually likely to pick for a global shortcut:
    /// letters, digits, the common punctuation row, arrows, and a few named keys. Stable OS-level
    /// constants (the same values Carbon's `kVK_*` names refer to), spelled as literals here so
    /// this module doesn't need to import Carbon just to label a key.
    private static let keyLabels: [UInt16: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
        40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
        32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
        123: "\u{2190}", 124: "\u{2192}", 125: "\u{2193}", 126: "\u{2191}",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}

/// Every shortcut the app can assign: one per widget, plus the "toggle the notch" shortcut (spec
/// §3.6 Shortcuts tab, §4.8). A pure value type — no `UserDefaults`, no Carbon — so conflict
/// detection is unit-testable on its own; `Preferences` just persists one of these.
public struct ShortcutAssignments: Equatable, Codable, Sendable {
    /// Which action a shortcut is (or would be) assigned to — a widget's, or the notch-wide toggle.
    /// `Hashable` so `Preferences.unavailableShortcuts` can be a `Set`.
    public enum Slot: Hashable, Codable, Sendable {
        case toggle
        case widget(WidgetID)
    }

    public var toggle: KeyShortcut?
    public var widgets: [WidgetID: KeyShortcut]

    public init(toggle: KeyShortcut? = nil, widgets: [WidgetID: KeyShortcut] = [:]) {
        self.toggle = toggle
        self.widgets = widgets
    }

    public func shortcut(for slot: Slot) -> KeyShortcut? {
        switch slot {
        case .toggle: toggle
        case .widget(let id): widgets[id]
        }
    }

    /// Whether `shortcut` is already assigned to some slot other than `excluding` (spec: "conflicts
    /// inside the app are rejected with a message").
    public func conflictingSlot(for shortcut: KeyShortcut, excluding: Slot) -> Slot? {
        if excluding != .toggle, toggle == shortcut { return .toggle }
        for (id, existing) in widgets where Slot.widget(id) != excluding && existing == shortcut {
            return .widget(id)
        }
        return nil
    }

    /// Assigns `shortcut` to `slot`, unless it conflicts with a different slot — in which case
    /// nothing changes and this returns `false`.
    @discardableResult
    public mutating func assign(_ shortcut: KeyShortcut, to slot: Slot) -> Bool {
        guard conflictingSlot(for: shortcut, excluding: slot) == nil else { return false }
        switch slot {
        case .toggle: toggle = shortcut
        case .widget(let id): widgets[id] = shortcut
        }
        return true
    }

    public mutating func clear(_ slot: Slot) {
        switch slot {
        case .toggle: toggle = nil
        case .widget(let id): widgets[id] = nil
        }
    }
}
