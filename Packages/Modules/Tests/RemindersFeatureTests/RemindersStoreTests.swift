import Foundation
import Testing
import Persistence
@testable import RemindersFeature

@MainActor
final class RemindersStoreTests {
    private let directory: URL
    /// A fixed "now" so overdue/upcoming and scheduling maths are deterministic. 2026-06-01
    /// 10:00:00 UTC.
    private let fixedNow = Date(timeIntervalSince1970: 1_780_394_400)
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemindersStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore(
        fileName: String = "reminders.json",
        scheduler: FakeScheduler = FakeScheduler(),
        now: Date? = nil
    ) -> (RemindersStore, FakeScheduler) {
        let resolvedNow = now ?? self.fixedNow
        let fileStore = JSONFileStore<RemindersDocument>(url: directory.appendingPathComponent(fileName))
        let store = RemindersStore(
            store: fileStore,
            scheduler: scheduler,
            now: { resolvedNow },
            calendar: calendar
        )
        return (store, scheduler)
    }

    // MARK: add

    @Test func addSchedulesExactlyOneRequest() {
        let (store, scheduler) = makeStore()
        let reminder = store.add(text: "buy milk", fireDate: fixedNow.addingTimeInterval(300))

        #expect(scheduler.scheduleCallCount == 1)
        #expect(scheduler.scheduled[reminder.id]?.id == reminder.id)
    }

    @Test func addStoresTheReminderImmediately() {
        let (store, _) = makeStore()
        let reminder = store.add(text: "buy milk", fireDate: fixedNow.addingTimeInterval(300))
        #expect(store.reminders.map(\.id) == [reminder.id])
    }

    @Test func aDeniedPermissionStillStoresTheReminder() {
        let scheduler = FakeScheduler()
        scheduler.authorizationResult = false
        let (store, _) = makeStore(scheduler: scheduler)

        let reminder = store.add(text: "buy milk", fireDate: fixedNow.addingTimeInterval(300))

        #expect(store.reminders.map(\.id) == [reminder.id])
    }

    // MARK: markDone

    @Test func markDoneCancelsTheRequestAndMarksTheStatus() {
        let (store, scheduler) = makeStore()
        let reminder = store.add(text: "buy milk", fireDate: fixedNow.addingTimeInterval(300))

        store.markDone(id: reminder.id)

        #expect(scheduler.cancelledIDs == [reminder.id])
        #expect(store.reminders.first(where: { $0.id == reminder.id })?.status == .done)
        #expect(store.upcoming.isEmpty)
        #expect(store.overdue.isEmpty)
    }

    @Test func markDoneOnAnUnknownIDIsANoOp() {
        let (store, scheduler) = makeStore()
        store.markDone(id: UUID())
        #expect(scheduler.cancelledIDs.isEmpty)
    }

    // MARK: undo (spec §3.5: "Done reminders are removed (⌘Z undo while the widget is open)")

    @Test func undoLastDoneRestoresItToPendingAndReschedules() {
        let (store, scheduler) = makeStore()
        let reminder = store.add(text: "buy milk", fireDate: fixedNow.addingTimeInterval(300))
        store.markDone(id: reminder.id)
        #expect(store.canUndoLastDone)
        let scheduleCallsBeforeUndo = scheduler.scheduleCallCount

        store.undoLastDone()

        #expect(store.reminders.first(where: { $0.id == reminder.id })?.status == .pending)
        #expect(store.upcoming.map(\.id) == [reminder.id])
        #expect(scheduler.scheduleCallCount == scheduleCallsBeforeUndo + 1)
        #expect(scheduler.scheduled[reminder.id]?.id == reminder.id)
    }

    @Test func canUndoLastDoneReflectsWhetherARestoreIsAvailable() {
        let (store, _) = makeStore()
        let reminder = store.add(text: "buy milk", fireDate: fixedNow.addingTimeInterval(300))
        #expect(!store.canUndoLastDone)

        store.markDone(id: reminder.id)
        #expect(store.canUndoLastDone)

        store.undoLastDone()
        #expect(!store.canUndoLastDone)
    }

    @Test func undoWithNothingDoneIsANoOp() {
        let (store, _) = makeStore()
        let reminder = store.add(text: "buy milk", fireDate: fixedNow.addingTimeInterval(300))
        store.undoLastDone()
        #expect(store.reminders.first(where: { $0.id == reminder.id })?.status == .pending)
    }

    @Test func clearUndoPreventsARestoreAfterTheWidgetCloses() {
        let (store, _) = makeStore()
        let reminder = store.add(text: "buy milk", fireDate: fixedNow.addingTimeInterval(300))
        store.markDone(id: reminder.id)

        store.clearUndo()
        store.undoLastDone()

        #expect(store.reminders.first(where: { $0.id == reminder.id })?.status == .done)
        #expect(!store.canUndoLastDone)
    }

    @Test func markingAnotherReminderDoneReplacesTheUndoSlot() {
        let (store, _) = makeStore()
        let first = store.add(text: "first", fireDate: fixedNow.addingTimeInterval(300))
        let second = store.add(text: "second", fireDate: fixedNow.addingTimeInterval(600))
        store.markDone(id: first.id)
        store.markDone(id: second.id)

        store.undoLastDone()

        #expect(store.reminders.first(where: { $0.id == second.id })?.status == .pending)
        #expect(store.reminders.first(where: { $0.id == first.id })?.status == .done)
    }

    // MARK: snooze

    @Test func snoozeMovesTheDateAndReschedules() {
        let (store, scheduler) = makeStore()
        let reminder = store.add(text: "buy milk", fireDate: fixedNow.addingTimeInterval(300))
        #expect(scheduler.scheduleCallCount == 1)

        store.snooze(id: reminder.id)

        #expect(scheduler.scheduleCallCount == 2)
        let expectedFireDate = fixedNow.addingTimeInterval(10 * 60)
        #expect(store.reminders.first(where: { $0.id == reminder.id })?.fireDate == expectedFireDate)
        #expect(scheduler.scheduled[reminder.id]?.fireDate == expectedFireDate)
    }

    @Test func snoozeUsesACustomInterval() {
        let scheduler = FakeScheduler()
        let fileStore = JSONFileStore<RemindersDocument>(url: directory.appendingPathComponent("reminders.json"))
        let store = RemindersStore(store: fileStore, scheduler: scheduler, now: { self.fixedNow }, calendar: calendar, snoozeInterval: 60)
        let reminder = store.add(text: "buy milk", fireDate: fixedNow.addingTimeInterval(300))

        store.snooze(id: reminder.id)

        #expect(store.reminders.first(where: { $0.id == reminder.id })?.fireDate == fixedNow.addingTimeInterval(60))
    }

    @Test func snoozeOnADoneReminderIsANoOp() {
        let (store, scheduler) = makeStore()
        let reminder = store.add(text: "buy milk", fireDate: fixedNow.addingTimeInterval(300))
        store.markDone(id: reminder.id)
        let scheduleCallsBefore = scheduler.scheduleCallCount

        store.snooze(id: reminder.id)

        #expect(scheduler.scheduleCallCount == scheduleCallsBefore)
    }

    // MARK: remove

    @Test func removeCancelsTheRequestAndDropsTheReminder() {
        let (store, scheduler) = makeStore()
        let reminder = store.add(text: "buy milk", fireDate: fixedNow.addingTimeInterval(300))

        store.remove(id: reminder.id)

        #expect(scheduler.cancelledIDs == [reminder.id])
        #expect(store.reminders.isEmpty)
    }

    // MARK: overdue / upcoming

    @Test func overdueIsComputedFromTheInjectedClock() {
        let (store, _) = makeStore()
        let overdueReminder = store.add(text: "already due", fireDate: fixedNow.addingTimeInterval(-60))
        let upcomingReminder = store.add(text: "not yet", fireDate: fixedNow.addingTimeInterval(60))

        #expect(store.overdue.map(\.id) == [overdueReminder.id])
        #expect(store.upcoming.map(\.id) == [upcomingReminder.id])
    }

    @Test func aReminderExactlyAtNowCountsAsOverdue() {
        let (store, _) = makeStore()
        let reminder = store.add(text: "right now", fireDate: fixedNow)
        #expect(store.overdue.map(\.id) == [reminder.id])
    }

    @Test func upcomingAndOverdueAreSortedByFireDateAscending() {
        let (store, _) = makeStore()
        let later = store.add(text: "later", fireDate: fixedNow.addingTimeInterval(600))
        let sooner = store.add(text: "sooner", fireDate: fixedNow.addingTimeInterval(60))
        #expect(store.upcoming.map(\.id) == [sooner.id, later.id])
    }

    // MARK: nextDueDate

    @Test func nextDueDateIsTheSoonestPendingOne() {
        let (store, _) = makeStore()
        #expect(store.nextDueDate == nil)

        store.add(text: "later", fireDate: fixedNow.addingTimeInterval(600))
        let sooner = store.add(text: "sooner", fireDate: fixedNow.addingTimeInterval(60))
        #expect(store.nextDueDate == sooner.fireDate)
    }

    @Test func nextDueDatePrefersAnOverdueReminderOverAnUpcomingOne() {
        let (store, _) = makeStore()
        store.add(text: "upcoming", fireDate: fixedNow.addingTimeInterval(60))
        let overdueReminder = store.add(text: "overdue", fireDate: fixedNow.addingTimeInterval(-60))
        #expect(store.nextDueDate == overdueReminder.fireDate)
    }

    @Test func nextDueDateIgnoresDoneReminders() {
        let (store, _) = makeStore()
        let reminder = store.add(text: "only one", fireDate: fixedNow.addingTimeInterval(60))
        store.markDone(id: reminder.id)
        #expect(store.nextDueDate == nil)
    }

    // MARK: reconcile

    @Test func reconcileSchedulesAPendingReminderThatHasNoRequest() async {
        // Simulate a reminder that was persisted on a previous launch but never got a chance to
        // schedule (e.g. the app crashed right after `add` returned).
        let fileURL = directory.appendingPathComponent("reminders.json")
        let seedingFileStore = JSONFileStore<RemindersDocument>(url: fileURL)
        let leftover = Reminder(text: "leftover", fireDate: fixedNow.addingTimeInterval(300))
        seedingFileStore.save(RemindersDocument(reminders: [leftover]))
        seedingFileStore.flush()

        let scheduler = FakeScheduler()
        let loadingFileStore = JSONFileStore<RemindersDocument>(url: fileURL)
        let store = RemindersStore(store: loadingFileStore, scheduler: scheduler, now: { self.fixedNow }, calendar: calendar)
        #expect(scheduler.scheduled.isEmpty)

        await store.reconcile()

        #expect(scheduler.scheduled[leftover.id]?.id == leftover.id)
    }

    @Test func reconcileCancelsARequestWithNoMatchingPendingReminder() async {
        let scheduler = FakeScheduler()
        let orphan = Reminder(text: "orphan", fireDate: fixedNow.addingTimeInterval(300))
        scheduler.preloadPendingRequest(for: orphan)

        let (store, _) = makeStore(scheduler: scheduler)
        #expect(store.reminders.isEmpty)

        await store.reconcile()

        #expect(scheduler.cancelledIDs == [orphan.id])
    }

    @Test func reconcileLeavesAnAlreadyPassedPendingReminderPendingAndOverdue() async {
        let (store, scheduler) = makeStore()
        let overdueReminder = store.add(text: "already due", fireDate: fixedNow.addingTimeInterval(-60))

        await store.reconcile()

        #expect(store.reminders.first(where: { $0.id == overdueReminder.id })?.status == .pending)
        #expect(store.overdue.map(\.id) == [overdueReminder.id])
        // Already scheduled by `add`; reconcile must not have cancelled it as though it were an
        // orphan just because its time has passed.
        #expect(!scheduler.cancelledIDs.contains(overdueReminder.id))
    }

    @Test func reconcileMarksNotificationsDeniedFromAPastDenial() async {
        let scheduler = FakeScheduler()
        scheduler.currentStatus = .denied
        let (store, _) = makeStore(scheduler: scheduler)
        #expect(!store.notificationsDenied)

        await store.reconcile()

        #expect(store.notificationsDenied)
    }

    // MARK: persistence

    @Test func remindersSurviveAReloadThroughJSONFileStore() {
        let fileURL = directory.appendingPathComponent("reminders.json")
        let firstFileStore = JSONFileStore<RemindersDocument>(url: fileURL)
        let store = RemindersStore(store: firstFileStore, scheduler: FakeScheduler(), now: { self.fixedNow }, calendar: calendar)
        let reminder = store.add(text: "remember this", fireDate: fixedNow.addingTimeInterval(300))
        store.markDone(id: UUID()) // no-op, just exercising the path
        store.flush()

        let secondFileStore = JSONFileStore<RemindersDocument>(url: fileURL)
        let reloaded = RemindersStore(store: secondFileStore, scheduler: FakeScheduler(), now: { self.fixedNow }, calendar: calendar)
        #expect(reloaded.reminders.map(\.id) == [reminder.id])
        #expect(reloaded.reminders.first?.text == "remember this")
    }

    @Test func aFutureSchemaVersionIsQuarantinedAndStartsEmpty() throws {
        let fileURL = directory.appendingPathComponent("reminders.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let future = RemindersDocument(version: 2, reminders: [])
        try JSONEncoder().encode(future).write(to: fileURL)

        let fileStore = JSONFileStore<RemindersDocument>(url: fileURL)
        let store = RemindersStore(store: fileStore, scheduler: FakeScheduler(), now: { self.fixedNow }, calendar: calendar)

        #expect(store.reminders.isEmpty)
        let quarantined = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .contains { $0.hasPrefix("reminders.corrupt-") }
        #expect(quarantined)
    }
}
