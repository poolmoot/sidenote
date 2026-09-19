import Testing
import NotchWidgetAPI
@testable import NotchKit

struct NotchStateMachineTests {
    private func machine(dropWidget: WidgetID? = .shelf) -> NotchStateMachine {
        NotchStateMachine(dropWidget: dropWidget)
    }

    /// A machine already showing tiles with the pointer inside.
    private func tiles() -> NotchStateMachine {
        var m = machine()
        _ = m.handle(.pointerEntered)
        _ = m.handle(.hoverDelayElapsed)
        return m
    }

    /// A machine showing the notes widget with the pointer inside.
    private func expandedNotes() -> NotchStateMachine {
        var m = tiles()
        _ = m.handle(.tileSelected(.notes))
        return m
    }

    @Test func startsFolded() {
        let m = machine()
        #expect(m.state == .folded)
        #expect(!m.isPointerInside)
        #expect(!m.isEditing)
    }

    @Test func pointerEnteringFoldedStartsHoverTimer() {
        var m = machine()
        #expect(m.handle(.pointerEntered) == [.startHoverTimer])
        #expect(m.state == .folded)
    }

    @Test func hoverDelayUnfoldsToTiles() {
        var m = machine()
        _ = m.handle(.pointerEntered)
        #expect(m.handle(.hoverDelayElapsed) == [])
        #expect(m.state == .tiles)
    }

    @Test func leavingBeforeHoverDelayCancelsAndStaysFolded() {
        var m = machine()
        _ = m.handle(.pointerEntered)
        #expect(m.handle(.pointerExited) == [.cancelTimers])
        _ = m.handle(.hoverDelayElapsed)
        #expect(m.state == .folded)
    }

    @Test func leavingTilesStartsGraceThenFolds() {
        var m = tiles()
        #expect(m.handle(.pointerExited) == [.startGraceTimer])
        #expect(m.handle(.graceElapsed) == [.cancelTimers, .resignKey])
        #expect(m.state == .folded)
    }

    @Test func returningDuringGraceCancelsFold() {
        var m = tiles()
        _ = m.handle(.pointerExited)
        #expect(m.handle(.pointerEntered) == [.cancelTimers])
        #expect(m.handle(.graceElapsed) == [])
        #expect(m.state == .tiles)
    }

    @Test func selectingTileExpandsAndTakesKey() {
        var m = tiles()
        #expect(m.handle(.tileSelected(.notes)) == [.cancelTimers, .makeKey])
        #expect(m.state == .expanded(.notes, dropTarget: false))
    }

    @Test func selectingTileWhileFoldedIsIgnored() {
        var m = machine()
        #expect(m.handle(.tileSelected(.notes)) == [])
        #expect(m.state == .folded)
    }

    @Test func leavingExpandedWithoutEditingFoldsAfterGrace() {
        var m = expandedNotes()
        #expect(m.handle(.pointerExited) == [.startGraceTimer])
        _ = m.handle(.graceElapsed)
        #expect(m.state == .folded)
    }

    @Test func editingLockKeepsExpandedWhenPointerLeaves() {
        var m = expandedNotes()
        #expect(m.handle(.editingBegan) == [.cancelTimers])
        #expect(m.handle(.pointerExited) == [])
        #expect(m.handle(.graceElapsed) == [])
        #expect(m.state == .expanded(.notes, dropTarget: false))
    }

    @Test func endingEditOutsideStartsGrace() {
        var m = expandedNotes()
        _ = m.handle(.editingBegan)
        _ = m.handle(.pointerExited)
        #expect(m.handle(.editingEnded) == [.startGraceTimer])
        _ = m.handle(.graceElapsed)
        #expect(m.state == .folded)
    }

    @Test func endingEditInsideDoesNothing() {
        var m = expandedNotes()
        _ = m.handle(.editingBegan)
        #expect(m.handle(.editingEnded) == [])
        #expect(m.state == .expanded(.notes, dropTarget: false))
    }

    @Test func escapeFoldsEvenWhileEditing() {
        var m = expandedNotes()
        _ = m.handle(.editingBegan)
        #expect(m.handle(.escape) == [.cancelTimers, .resignKey])
        #expect(m.state == .folded)
        #expect(!m.isEditing)
    }

    @Test func escapeWhenFoldedIsIgnored() {
        var m = machine()
        #expect(m.handle(.escape) == [])
    }

    @Test func resigningKeyFoldsExpanded() {
        var m = expandedNotes()
        _ = m.handle(.editingBegan)
        #expect(m.handle(.resignedKey) == [.cancelTimers, .resignKey])
        #expect(m.state == .folded)
    }

    @Test func resigningKeyInTilesIsIgnored() {
        var m = tiles()
        #expect(m.handle(.resignedKey) == [])
        #expect(m.state == .tiles)
    }

    @Test func backReturnsToTilesAndGivesUpKey() {
        var m = expandedNotes()
        _ = m.handle(.editingBegan)
        #expect(m.handle(.back) == [.resignKey])
        #expect(m.state == .tiles)
        #expect(!m.isEditing)
    }

    @Test func fileDragOpensDropWidgetDirectly() {
        var m = machine()
        #expect(m.handle(.fileDragEntered) == [.cancelTimers])
        #expect(m.state == .expanded(.shelf, dropTarget: true))
    }

    @Test func fileDragIgnoredWithoutDropWidget() {
        var m = machine(dropWidget: nil)
        #expect(m.handle(.fileDragEntered) == [])
        #expect(m.state == .folded)
    }

    @Test func fileDragLeavingClearsHighlightThenFolds() {
        var m = machine()
        _ = m.handle(.fileDragEntered)
        #expect(m.handle(.fileDragExited) == [.startGraceTimer])
        #expect(m.state == .expanded(.shelf, dropTarget: false))
        _ = m.handle(.graceElapsed)
        #expect(m.state == .folded)
    }

    @Test func droppingClearsHighlightAndStaysOpen() {
        var m = machine()
        _ = m.handle(.fileDragEntered)
        #expect(m.handle(.fileDropped) == [])
        #expect(m.state == .expanded(.shelf, dropTarget: false))
        #expect(m.isPointerInside)
    }

    @Test func fileDragWhileEditingAnotherWidgetClearsEditingLock() {
        var m = expandedNotes()
        _ = m.handle(.editingBegan)
        _ = m.handle(.fileDragEntered)
        #expect(m.state == .expanded(.shelf, dropTarget: true))
        #expect(!m.isEditing)
        _ = m.handle(.fileDragExited)
        _ = m.handle(.graceElapsed)
        #expect(m.state == .folded)
    }

    @Test func shortcutOpensWidgetFromAnywhereAndTogglesClosed() {
        var m = machine()
        #expect(m.handle(.shortcut(.reminders)) == [.cancelTimers, .makeKey])
        #expect(m.state == .expanded(.reminders, dropTarget: false))
        #expect(m.handle(.shortcut(.reminders)) == [.cancelTimers, .resignKey])
        #expect(m.state == .folded)
    }

    @Test func shortcutSwitchesBetweenWidgets() {
        var m = expandedNotes()
        _ = m.handle(.shortcut(.shelf))
        #expect(m.state == .expanded(.shelf, dropTarget: false))
    }
}
