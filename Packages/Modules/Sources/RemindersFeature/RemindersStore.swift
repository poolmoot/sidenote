import Foundation
import Observation
import os
import Persistence
import AppInfo

/// Backs the Reminders widget: text reminders scheduled as macOS notifications, persisted across
/// launches and reconciled against the system's notification requests on launch (spec §3.5, §4.7).
@MainActor
@Observable
public final class RemindersStore {
    /// Every reminder, pending and done, in no particular order. Most callers want `overdue` or
    /// `upcoming` instead.
    public private(set) var reminders: [Reminder]
    /// Pending reminders whose `fireDate` has passed, soonest first.
    public private(set) var overdue: [Reminder] = []
    /// Pending reminders still to come, soonest first.
    public private(set) var upcoming: [Reminder] = []
    /// True once a request for permission has resolved to "denied" — either just now or found by
    /// `reconcile()` on launch. Drives the inline banner from spec §6. Never true just because
    /// permission hasn't been asked for yet.
    public private(set) var notificationsDenied = false

    @ObservationIgnored private let store: JSONFileStore<RemindersDocument>
    @ObservationIgnored private let scheduler: any ReminderScheduler
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let snoozeInterval: TimeInterval
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private var hasRequestedAuthorization = false
    /// The reminder most recently marked done, kept for a single level of undo (spec §3.5: "Done
    /// reminders are removed (⌘Z undo while the widget is open)") — same shape as Notes' delete
    /// undo. Cleared by `clearUndo()`, which the widget calls when it closes, so ⌘Z never reaches
    /// back past the last time the widget was open.
    @ObservationIgnored private var lastDone: Reminder?
    /// The single outstanding wake-up for the soonest pending reminder (spec §4.7's "one
    /// non-repeating timer"). Re-armed by `recompute()` whenever the reminder set changes;
    /// cancelled outright when nothing is pending. This is the only timer this store owns — no
    /// periodic polling.
    @ObservationIgnored private var wakeTask: Task<Void, Never>?

    public init(
        store: JSONFileStore<RemindersDocument>,
        scheduler: any ReminderScheduler,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        snoozeInterval: TimeInterval = 10 * 60,
        logger: Logger = AppIdentity.current.logger("reminders")
    ) {
        self.store = store
        self.scheduler = scheduler
        self.now = now
        self.calendar = calendar
        self.snoozeInterval = snoozeInterval
        self.logger = logger
        // A document from a future, unrecognized schema is quarantined rather than accepted as
        // though it were version 1 — see `JSONFileStore.load(isValid:)`.
        reminders = (store.load(isValid: { $0.version == 1 }) ?? RemindersDocument()).reminders
        recompute()
    }

    /// The soonest `fireDate` among pending reminders (overdue included), or `nil` if none are
    /// pending. `overdue` is always sorted ascending same as `upcoming`, and every overdue
    /// `fireDate` is `<= now`, i.e. earlier than every upcoming one — so its first element, when
    /// there is one, is always the global minimum.
    public var nextDueDate: Date? { overdue.first?.fireDate ?? upcoming.first?.fireDate }

    /// Adds a reminder, saves it, and schedules its notification. Requests notification
    /// permission the first time this is called (spec §3.5) — but scheduling and persistence
    /// never wait on that request, and happen the same whether it's granted or denied (spec §6).
    @discardableResult
    public func add(text: String, fireDate: Date) -> Reminder {
        let reminder = Reminder(text: text, fireDate: fireDate)
        reminders.append(reminder)
        scheduler.schedule(reminder)
        persist()
        recompute()
        requestAuthorizationIfNeeded()
        return reminder
    }

    /// Marks `id` done and cancels its notification request. Spec §3.5: done reminders drop out
    /// of the list (the widget offers a single-level ⌘Z, same shape as Notes' delete undo, but
    /// that's the view's concern, not the store's).
    public func markDone(id: UUID) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        lastDone = reminders[index]
        reminders[index].status = .done
        scheduler.cancel(id: id)
        persist()
        recompute()
    }

    /// Whether `undoLastDone()` would currently restore something.
    public var canUndoLastDone: Bool { lastDone != nil }

    /// Restores the most recently done reminder to pending and reschedules its notification. A
    /// no-op when there's nothing to restore, including after `clearUndo()`.
    public func undoLastDone() {
        guard let lastDone else { return }
        self.lastDone = nil
        guard let index = reminders.firstIndex(where: { $0.id == lastDone.id }) else { return }
        reminders[index].status = .pending
        scheduler.schedule(reminders[index])
        persist()
        recompute()
    }

    /// Drops the single-level undo. Called when the widget closes (spec §3.5).
    public func clearUndo() {
        lastDone = nil
    }

    /// Pushes `id`'s `fireDate` to `now + snoozeInterval` and reschedules it. A no-op if `id`
    /// isn't a pending reminder.
    public func snooze(id: UUID) {
        guard let index = reminders.firstIndex(where: { $0.id == id }), reminders[index].status == .pending else { return }
        reminders[index].fireDate = now().addingTimeInterval(snoozeInterval)
        scheduler.schedule(reminders[index])
        persist()
        recompute()
    }

    /// Removes `id` outright and cancels its notification request.
    public func remove(id: UUID) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders.remove(at: index)
        scheduler.cancel(id: id)
        persist()
        recompute()
    }

    /// Reconciles in-app state with the system's actual notification requests (spec §4.7): any
    /// pending reminder missing a request gets one scheduled; any request with no matching
    /// pending reminder is cancelled; a pending reminder whose time has already passed is left
    /// alone (it just shows as overdue — `recompute()` already handles that from the clock).
    /// Also refreshes `notificationsDenied` from the system's actual authorization state, so a
    /// denial from a previous launch still shows the banner without re-prompting.
    public func reconcile() async {
        let pendingReminders = reminders.filter { $0.status == .pending }
        let pendingReminderIDs = Set(pendingReminders.map(\.id))
        let scheduledIDs = await scheduler.pendingIDs()

        for reminder in pendingReminders where !scheduledIDs.contains(reminder.id) {
            scheduler.schedule(reminder)
        }
        for orphanID in scheduledIDs.subtracting(pendingReminderIDs) {
            scheduler.cancel(id: orphanID)
        }

        if await scheduler.authorizationStatus() == .denied {
            notificationsDenied = true
        }
    }

    /// Writes any pending change synchronously. Called on fold and at app termination.
    public func flush() {
        store.flush()
    }

    private func requestAuthorizationIfNeeded() {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        Task { [scheduler] in
            let granted = await scheduler.requestAuthorization()
            if !granted {
                self.notificationsDenied = true
            }
        }
    }

    /// Recomputes `overdue`/`upcoming` from the clock and re-arms `wakeTask` for the soonest
    /// pending reminder, so the split (and anything derived from it, like the widget's badge)
    /// updates itself the moment a reminder becomes due — without polling.
    private func recompute() {
        let pendingSorted = reminders
            .filter { $0.status == .pending }
            .sorted { $0.fireDate < $1.fireDate }
        let currentMoment = now()
        overdue = pendingSorted.filter { $0.fireDate <= currentMoment }
        upcoming = pendingSorted.filter { $0.fireDate > currentMoment }
        rearmWakeTask()
    }

    private func rearmWakeTask() {
        wakeTask?.cancel()
        guard let nextFireDate = upcoming.first?.fireDate else {
            wakeTask = nil
            return
        }
        let interval = max(nextFireDate.timeIntervalSince(now()), 0)
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            self?.recompute()
        }
    }

    private func persist() {
        store.save(RemindersDocument(reminders: reminders))
    }
}
