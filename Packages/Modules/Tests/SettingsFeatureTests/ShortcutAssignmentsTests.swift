import Foundation
import Testing
import NotchWidgetAPI
@testable import SettingsFeature

struct KeyShortcutTests {
    @Test func roundTripsThroughJSON() throws {
        let shortcut = KeyShortcut(keyCode: 15, modifiers: 1_048_840) // R, ⌘⇧
        let data = try JSONEncoder().encode(shortcut)
        let decoded = try JSONDecoder().decode(KeyShortcut.self, from: data)
        #expect(decoded == shortcut)
    }

    @Test func displayStringOrdersModifiersConventionallyThenTheKey() {
        // ⌘⇧R: command (1<<20) | shift (1<<17)
        let shortcut = KeyShortcut(keyCode: 15, modifiers: (1 << 20) | (1 << 17))
        #expect(shortcut.displayString == "\u{21E7}\u{2318}R")
    }

    @Test func displayStringCoversAllFourModifiersInOrder() {
        let allModifiers: UInt = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)
        let shortcut = KeyShortcut(keyCode: 0, modifiers: allModifiers)
        #expect(shortcut.displayString == "\u{2303}\u{2325}\u{21E7}\u{2318}A")
    }

    @Test func displayStringWithNoModifiersIsJustTheKey() {
        #expect(KeyShortcut(keyCode: 49, modifiers: 0).displayString == "Space")
    }

    @Test func anUnrecognizedKeyCodeFallsBackToItsNumber() {
        #expect(KeyShortcut(keyCode: 9_999, modifiers: 0).displayString == "Key 9999")
    }
}

struct ShortcutAssignmentsTests {
    private let r = KeyShortcut(keyCode: 15, modifiers: 256)
    private let n = KeyShortcut(keyCode: 45, modifiers: 256)

    @Test func assigningToAnEmptySlotSucceeds() {
        var assignments = ShortcutAssignments()
        let succeeded = assignments.assign(r, to: .widget(.reminders))
        #expect(succeeded)
        #expect(assignments.shortcut(for: .widget(.reminders)) == r)
    }

    @Test func assigningTheSameShortcutToTwoWidgetsIsRejected() {
        var assignments = ShortcutAssignments()
        assignments.assign(r, to: .widget(.reminders))
        let succeeded = assignments.assign(r, to: .widget(.notes))
        #expect(!succeeded)
        #expect(assignments.shortcut(for: .widget(.notes)) == nil)
        #expect(assignments.shortcut(for: .widget(.reminders)) == r)
    }

    @Test func aWidgetShortcutConflictingWithTheToggleIsRejected() {
        var assignments = ShortcutAssignments()
        assignments.assign(r, to: .toggle)
        let succeeded = assignments.assign(r, to: .widget(.shelf))
        #expect(!succeeded)
    }

    @Test func reassigningTheSameSlotToItsOwnCurrentShortcutSucceeds() {
        var assignments = ShortcutAssignments()
        assignments.assign(r, to: .widget(.reminders))
        let succeeded = assignments.assign(r, to: .widget(.reminders))
        #expect(succeeded)
    }

    @Test func conflictingSlotNamesTheOtherOwner() {
        var assignments = ShortcutAssignments()
        assignments.assign(r, to: .widget(.reminders))
        #expect(assignments.conflictingSlot(for: r, excluding: .widget(.notes)) == .widget(.reminders))
        #expect(assignments.conflictingSlot(for: n, excluding: .widget(.notes)) == nil)
    }

    @Test func clearingASlotFreesItsShortcutForReuse() {
        var assignments = ShortcutAssignments()
        assignments.assign(r, to: .widget(.reminders))
        assignments.clear(.widget(.reminders))
        #expect(assignments.shortcut(for: .widget(.reminders)) == nil)
        let succeeded = assignments.assign(r, to: .widget(.notes))
        #expect(succeeded)
    }

    @Test func roundTripsThroughJSON() throws {
        var assignments = ShortcutAssignments()
        assignments.assign(r, to: .toggle)
        assignments.assign(n, to: .widget(.notes))
        let data = try JSONEncoder().encode(assignments)
        let decoded = try JSONDecoder().decode(ShortcutAssignments.self, from: data)
        #expect(decoded == assignments)
    }
}
