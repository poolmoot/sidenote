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

    /// A custom date picked behind the clock (spec review fix): scheduling it would just fire a
    /// notification banner the instant it's created, so `add` must skip `scheduler.schedule`
    /// entirely for it — while still saving it and showing it as overdue right away.
    @Test func addWithAPastFireDateDoesNotScheduleButStillShowsAsOverdue() {
        let (store, scheduler) = makeStore()
        let reminder = store.add(text: "already late", fireDate: fixedNow.addingTimeInterval(-60))

        #expect(scheduler.scheduleCallCount == 0)
        #expect(scheduler.scheduled.isEmpty)
        #expect(store.reminders.map(\.id) == [reminder.id])
        #expect(store.overdue.map(\.id) == [reminder.id])
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

        // `clearUndo` doesn't just block the restore — since review fix #3, it also purges every
        // `.done` reminder outright, so the reminder is gone entirely rather than left `.done`.
        #expect(store.reminders.first(where: { $0.id == reminder.id }) == nil)
        #expect(!store.canUndoLastDone)
    }

    /// Spec §4.7: "Done" removes a reminder from the list for good — but only once the widget has
    /// actually closed and ⌘Z can no longer reach it. Before that, a done reminder is only
    /// *hidden* (kept in `reminders` so `undoLastDone` can restore it).
    @Test func clearUndoPurgesEveryDoneReminderAndPersists() {
        let (store, _) = makeStore()
        let done = store.add(text: "done", fireDate: fixedNow.addingTimeInterval(300))
        let stillPending = store.add(text: "still pending", fireDate: fixedNow.addingTimeInterval(600))
        store.markDone(id: done.id)
        #expect(store.reminders.map(\.id).contains(done.id))

        store.clearUndo()

        #expect(store.reminders.map(\.id) == [stillPending.id])
    }

    @Test func clearUndoWithNothingDoneDoesNotTouchPendingReminders() {
        let (store, _) = makeStore()
        let reminder = store.add(text: "pending", fireDate: fixedNow.addingTimeInterval(300))
        store.clearUndo()
        #expect(store.reminders.map(\.id) == [reminder.id])
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

    /// Snoozing an overdue reminder — the normal case — measures from now.
    @Test func snoozeMovesTheDateAndReschedules() {
        let (store, scheduler) = makeStore()
        let reminder = store.add(text: "buy milk", fireDate: fixedNow.addingTimeInterval(-300))
        #expect(scheduler.scheduleCallCount == 0)   // already overdue: nothing to schedule

        store.snooze(id: reminder.id)

        #expect(scheduler.scheduleCallCount == 1)
        let expectedFireDate = fixedNow.addingTimeInterval(10 * 60)
        #expect(store.reminders.first(where: { $0.id == reminder.id })?.fireDate == expectedFireDate)
        #expect(scheduler.scheduled[reminder.id]?.fireDate == expectedFireDate)
    }

    @Test func snoozeUsesACustomInterval() {
        let scheduler = FakeScheduler()
        let fileStore = JSONFileStore<RemindersDocument>(url: directory.appendingPathComponent("reminders.json"))
        let store = RemindersStore(store: fileStore, scheduler: scheduler, now: { self.fixedNow }, calendar: calendar, snoozeInterval: 60)
        let reminder = store.add(text: "buy milk", fireDate: fixedNow.addingTimeInterval(-300))

        store.snooze(id: reminder.id)

        #expect(store.reminders.first(where: { $0.id == reminder.id })?.fireDate == fixedNow.addingTimeInterval(60))
    }

    /// Settings › Reminders' snooze-length picker changes `snoozeInterval` live on the same store
    /// instance — it isn't just an init-time constant.
    @Test func snoozeIntervalIsSettableLiveAfterConstruction() {
        let (store, _) = makeStore()
        store.snoozeInterval = 30 * 60
        let reminder = store.add(text: "buy milk", fireDate: fixedNow.addingTimeInterval(-300))

        store.snooze(id: reminder.id)

        #expect(store.reminders.first(where: { $0.id == reminder.id })?.fireDate == fixedNow.addingTimeInterval(30 * 60))
    }

    @Test func chipsReflectTheConfiguredTonightAndTomorrowHours() {
        let (store, _) = makeStore()
        store.tonightHour = 23
        store.tomorrowHour = 6
        #expect(store.chips.first(where: { $0.id == "tonight" })?.time == .tonight(hour: 23))
        #expect(store.chips.first(where: { $0.id == "tomorrow" })?.time == .tomorrow(hour: 6))
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
        // Not cancelled as though it were an orphan just because its time has passed...
        #expect(!scheduler.cancelledIDs.contains(overdueReminder.id))
        // ...but not (re)scheduled either: `add` already skipped scheduling it (it was already
        // overdue when created), and `reconcile` must not schedule a past-due pending reminder
        // that has no request — that would just re-fire it on every relaunch (review fix #1).
        #expect(scheduler.scheduleCallCount == 0)
        #expect(scheduler.scheduled.isEmpty)
    }

    /// Review fix #1, tested directly against `reconcile()` rather than through `add` (which
    /// already refuses to schedule a past-due reminder itself): a pending reminder loaded from
    /// disk whose `fireDate` has already passed, with no outstanding request at all, must not get
    /// one from `reconcile()` — that would make an ignored reminder re-fire on every relaunch,
    /// since the scheduler clamps a past interval to a near-zero one rather than refusing it.
    @Test func reconcileDoesNotScheduleAPastDuePendingReminderThatHasNoRequest() async {
        let fileURL = directory.appendingPathComponent("reminders.json")
        let seedingFileStore = JSONFileStore<RemindersDocument>(url: fileURL)
        let overdueLeftover = Reminder(text: "overdue leftover", fireDate: fixedNow.addingTimeInterval(-60))
        seedingFileStore.save(RemindersDocument(reminders: [overdueLeftover]))
        seedingFileStore.flush()

        let scheduler = FakeScheduler()
        let loadingFileStore = JSONFileStore<RemindersDocument>(url: fileURL)
        let store = RemindersStore(store: loadingFileStore, scheduler: scheduler, now: { self.fixedNow }, calendar: calendar)

        await store.reconcile()

        #expect(scheduler.scheduleCallCount == 0)
        #expect(scheduler.scheduled.isEmpty)
        #expect(store.overdue.map(\.id) == [overdueLeftover.id])
    }

    /// Review fix #7b: a pending reminder that already has an outstanding request must not be
    /// scheduled again — `reconcile()` only fills in what's missing.
    @Test func reconcileDoesNotRescheduleAReminderThatAlreadyHasARequest() async {
        let (store, scheduler) = makeStore()
        let reminder = store.add(text: "buy milk", fireDate: fixedNow.addingTimeInterval(300))
        #expect(scheduler.scheduleCallCount == 1)

        await store.reconcile()

        #expect(scheduler.scheduleCallCount == 1)
    }

    @Test func reconcileMarksNotificationsDeniedFromAPastDenial() async {
        let scheduler = FakeScheduler()
        scheduler.currentStatus = .denied
        let (store, _) = makeStore(scheduler: scheduler)
        #expect(!store.notificationsDenied)

        await store.reconcile()

        #expect(store.notificationsDenied)
    }

    /// `notificationsDenied` must track the system's current status in both directions: granting
    /// permission (e.g. in System Settings) since the last check should clear a stale banner, not
    /// just set one.
    @Test func reconcileClearsNotificationsDeniedOncePermissionIsGranted() async {
        let scheduler = FakeScheduler()
        scheduler.currentStatus = .denied
        let (store, _) = makeStore(scheduler: scheduler)
        await store.reconcile()
        #expect(store.notificationsDenied)

        scheduler.currentStatus = .authorized
        await store.reconcile()

        #expect(!store.notificationsDenied)
    }

    // MARK: persistence

    @Test func remindersSurviveAReloadThroughJSONFileStore() {
        let fileURL = directory.appendingPathComponent("reminders.json")
        let firstFileStore = JSONFileStore<RemindersDocument>(url: fileURL)
        let store = RemindersStore(store: firstFileStore, scheduler: FakeScheduler(), now: { self.fixedNow }, calendar: calendar)
        let reminder = store.add(text: "remember this", fireDate: fixedNow.addingTimeInterval(300))
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

@MainActor
struct SnoozingAnUpcomingReminderTests {
    @Test func snoozingSomethingNotYetDuePushesItLaterNotCloser() throws {
        let clock = Date(timeIntervalSince1970: 1_700_000_000)
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = RemindersStore(
            store: JSONFileStore<RemindersDocument>(url: directory.appendingPathComponent("reminders.json")),
            scheduler: FakeScheduler(),
            now: { clock }
        )
        let eightHoursAway = clock.addingTimeInterval(8 * 3600)
        store.add(text: "dentist", fireDate: eightHoursAway)

        store.snooze(id: store.reminders[0].id)

        // 8 h + the snooze length, never "10 minutes from now".
        #expect(store.reminders[0].fireDate == eightHoursAway.addingTimeInterval(10 * 60))
    }
}
