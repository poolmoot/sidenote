import Foundation
@testable import RemindersFeature

/// An in-memory `ReminderScheduler` for tests — never touches `UNUserNotificationCenter`. Records
/// every call so tests can assert exactly what `RemindersStore` asked it to do.
@MainActor
final class FakeScheduler: ReminderScheduler {
    private(set) var scheduled: [UUID: Reminder] = [:]
    private(set) var scheduleCallCount = 0
    private(set) var cancelledIDs: [UUID] = []
    private(set) var requestAuthorizationCallCount = 0

    var authorizationResult = true
    var currentStatus: ReminderAuthorizationStatus = .notDetermined

    func requestAuthorization() async -> Bool {
        requestAuthorizationCallCount += 1
        currentStatus = authorizationResult ? .authorized : .denied
        return authorizationResult
    }

    func authorizationStatus() async -> ReminderAuthorizationStatus {
        currentStatus
    }

    func schedule(_ reminder: Reminder) {
        scheduleCallCount += 1
        scheduled[reminder.id] = reminder
    }

    func cancel(id: UUID) {
        cancelledIDs.append(id)
        scheduled.removeValue(forKey: id)
    }

    func pendingIDs() async -> Set<UUID> {
        Set(scheduled.keys)
    }

    /// Test-setup only: simulates a notification request that already existed before a
    /// `RemindersStore` was constructed — e.g. left over from a previous launch — without going
    /// through `schedule(_:)` (which `scheduleCallCount` assertions rely on staying accurate).
    func preloadPendingRequest(for reminder: Reminder) {
        scheduled[reminder.id] = reminder
    }
}
