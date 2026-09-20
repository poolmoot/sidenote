import AppKit
import Carbon.HIToolbox
import NotchWidgetAPI
import SettingsFeature

/// Registers the app's global keyboard shortcuts (spec §4.8) with Carbon's `RegisterEventHotKey` —
/// works inside the sandbox and needs no Accessibility permission, unlike an `NSEvent` global
/// monitor, which this codebase avoids everywhere (see `AGENTS.md`'s no-polling rule and the grep
/// check in `docs/architecture.md`; `ShortcutRecorder` in `SettingsFeature` makes the same choice
/// for capturing a shortcut while recording it).
///
/// Hand-checked only: registering a real system-wide hot key and receiving Carbon's callback isn't
/// something a unit test can exercise, and this lives outside `Packages/Modules` for exactly that
/// reason — see `AGENTS.md` rule 4.
@MainActor
final class ShortcutCenter {
    private struct Registration {
        let ref: EventHotKeyRef
        let action: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var handlerRef: EventHandlerRef?
    private var nextHotKeyID: UInt32 = 1
    /// An arbitrary four-character signature Carbon requires to namespace hot key ids; it never
    /// leaves this process, so any stable value works.
    private static let signature = OSType(0x5344_4E43) // 'SDNC'

    func start() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
                )
                guard status == noErr else { return noErr }
                let center = Unmanaged<ShortcutCenter>.fromOpaque(userData).takeUnretainedValue()
                center.fire(hotKeyID.id)
                return noErr
            },
            1, &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    func stop() {
        unregisterAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        handlerRef = nil
    }

    /// Replaces every registered hot key with `assignments` — always a full tear-down and rebuild,
    /// so this is safe to call again any time a shortcut changes in Settings, not just once at
    /// launch.
    func apply(_ assignments: ShortcutAssignments, onToggle: @escaping () -> Void, onWidget: @escaping (WidgetID) -> Void) {
        unregisterAll()
        if let toggle = assignments.toggle {
            register(toggle, action: onToggle)
        }
        for (id, shortcut) in assignments.widgets {
            register(shortcut) { onWidget(id) }
        }
    }

    private func register(_ shortcut: KeyShortcut, action: @escaping () -> Void) {
        let id = nextHotKeyID
        nextHotKeyID += 1
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            carbonModifiers(from: shortcut.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else { return }
        registrations[id] = Registration(ref: hotKeyRef, action: action)
    }

    private func fire(_ id: UInt32) {
        registrations[id]?.action()
    }

    private func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
    }

    private func carbonModifiers(from flags: UInt) -> UInt32 {
        let modifiers = NSEvent.ModifierFlags(rawValue: flags)
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
