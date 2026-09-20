import UserNotifications
import RemindersFeature

/// Handles the two things a delivered reminder notification can do (spec §3.5): the **Done** /
/// **Snooze** actions on the notification itself, and clicking the notification body, which opens
/// the Reminders widget. Kept as its own small type (rather than folded into `AppEnvironment`)
/// because `UNUserNotificationCenterDelegate` methods are called by the system, not by us, and
/// having a dedicated `NSObject` subclass for it is the standard shape for that.
@MainActor
final class NotificationDelegate: NSObject, @MainActor UNUserNotificationCenterDelegate {
    private let store: RemindersStore
    private let onOpenReminders: () -> Void

    init(store: RemindersStore, onOpenReminders: @escaping () -> Void) {
        self.store = store
        self.onOpenReminders = onOpenReminders
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let id = UUID(uuidString: response.notification.request.identifier) else { return }

        switch response.actionIdentifier {
        case ReminderNotification.doneActionIdentifier:
            store.markDone(id: id)
        case ReminderNotification.snoozeActionIdentifier:
            store.snooze(id: id)
        case UNNotificationDefaultActionIdentifier:
            // The user clicked the notification body itself, rather than an action button.
            onOpenReminders()
        default:
            break
        }
    }

    /// Shows the notification even while the app is frontmost (it has `LSUIElement = YES` and no
    /// normal window, so the system would otherwise assume it's "active" and suppress the banner).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
