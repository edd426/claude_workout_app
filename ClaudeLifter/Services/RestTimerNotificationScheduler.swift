import Foundation
import UserNotifications

/// Abstraction over UNUserNotificationCenter so the rest timer can schedule
/// its "rest complete" chime while the phone is locked (issue #77) and tests
/// can verify scheduling without touching the real notification center
/// (which cannot be instantiated in unit tests).
@MainActor
protocol NotificationScheduling: AnyObject {
    /// Requests notification authorization if it has not been determined yet.
    /// Called lazily on first timer use — not at app launch.
    func requestAuthorizationIfNeeded()
    /// Schedules (or replaces) the single rest-complete notification to fire
    /// at the given deadline.
    func scheduleRestCompleteNotification(at fireDate: Date)
    /// Cancels any pending rest-complete notification and clears a delivered
    /// one from Notification Center.
    func cancelRestCompleteNotification()
}

/// Production implementation backed by UNUserNotificationCenter. All calls
/// are fire-and-forget: the rest timer must never block on notification IO.
@MainActor
final class UserNotificationScheduler: NotificationScheduling {
    static let notificationIdentifier = "com.claudelifter.restTimerComplete"

    func requestAuthorizationIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func scheduleRestCompleteNotification(at fireDate: Date) {
        let interval = fireDate.timeIntervalSinceNow
        // A trigger interval must be > 0; a deadline already passed (or about
        // to) will be handled by the in-foreground expiry path instead.
        guard interval > 0 else { return }

        Task {
            let content = UNMutableNotificationContent()
            content.title = "Rest complete"
            content.body = "Time for your next set."
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.notificationIdentifier,
                content: content,
                trigger: trigger
            )
            // Adding with the same identifier replaces any pending request,
            // so +15s/-15s adjustments move the scheduled chime.
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    func cancelRestCompleteNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
    }
}
