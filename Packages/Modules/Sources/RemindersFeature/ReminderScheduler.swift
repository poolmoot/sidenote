import Foundation
import UserNotifications
import os
import AppInfo

/// The notification category and action identifiers reminders are scheduled and responded to
/// under (spec §4.7). Shared between the scheduler (which registers the category) and whatever
/// handles `UNUserNotificationCenterDelegate` callbacks (which reads the action identifiers back
/// out), so the two can never drift apart.
public enum ReminderNotification {
    public static let categoryIdentifier = "REMINDER"
    public static let doneActionIdentifier = "DONE"
    public static let snoozeActionIdentifier = "SNOOZE"
}

/// Whether the user has granted permission to show notifications, without prompting for it.
/// Distinct from "not yet asked" so the UI only shows a "notifications are off" banner (spec §6)
/// for an actual denial, not for a reminder that hasn't requested permission yet.
public enum ReminderAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

/// Wraps `UNUserNotificationCenter` behind a protocol so `RemindersStore` can be tested with an
/// in-memory fake and never touches the real notification center in tests. Spec §4.7.
@MainActor
public protocol ReminderScheduler: AnyObject {
    /// Prompts for permission if not yet determined. Returns whether notifications are authorized
    /// after the request resolves.
    func requestAuthorization() async -> Bool
    /// The current authorization state, without prompting.
    func authorizationStatus() async -> ReminderAuthorizationStatus
    /// Schedules (replacing any existing request for the same reminder) one notification request,
    /// identifier = `reminder.id.uuidString`. Fire-and-forget: a scheduling failure is logged by
    /// the implementation and never thrown, so it can never block saving the reminder (spec §6).
    func schedule(_ reminder: Reminder)
    /// Cancels the pending request for `id`, if any. A no-op if there isn't one.
    func cancel(id: UUID)
    /// The reminder IDs that currently have an outstanding pending request.
    func pendingIDs() async -> Set<UUID>
}

/// The real `UNUserNotificationCenter`-backed scheduler.
@MainActor
public final class UNReminderScheduler: ReminderScheduler {
    private let center: UNUserNotificationCenter
    private let logger: Logger

    public init(
        center: UNUserNotificationCenter = .current(),
        logger: Logger = AppIdentity.current.logger("reminders")
    ) {
        self.center = center
        self.logger = logger
        let done = UNNotificationAction(identifier: ReminderNotification.doneActionIdentifier, title: "Done", options: [])
        let snooze = UNNotificationAction(identifier: ReminderNotification.snoozeActionIdentifier, title: "Snooze", options: [])
        let category = UNNotificationCategory(
            identifier: ReminderNotification.categoryIdentifier,
            actions: [done, snooze],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    public func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("Notification authorization request failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    public func authorizationStatus() async -> ReminderAuthorizationStatus {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    public func schedule(_ reminder: Reminder) {
        let content = UNMutableNotificationContent()
        content.title = reminder.text
        content.categoryIdentifier = ReminderNotification.categoryIdentifier
        content.sound = .default

        // A trigger interval must be positive; a reminder due right now (or already overdue by
        // the time this runs) still gets a request, firing as soon as the system allows.
        let interval = max(reminder.fireDate.timeIntervalSinceNow, 0.001)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: reminder.id.uuidString, content: content, trigger: trigger)

        let logger = self.logger
        center.add(request) { error in
            if let error {
                logger.error("Failed to schedule reminder \(reminder.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    public func cancel(id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    public func pendingIDs() async -> Set<UUID> {
        let requests = await center.pendingNotificationRequests()
        return Set(requests.compactMap { UUID(uuidString: $0.identifier) })
    }
}
