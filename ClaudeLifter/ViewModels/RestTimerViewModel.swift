import Foundation
import Observation
import AudioToolbox
import UIKit

/// Rest countdown driven by an absolute deadline rather than tick counting
/// (issue #77). Foreground ticks only *recompute* `endDate - now`, so time
/// spent suspended (phone locked between sets — the normal gym case) is fully
/// accounted for, and a scheduled local notification chimes at the deadline
/// even while the app is not running.
@Observable
@MainActor
final class RestTimerViewModel {
    private(set) var remainingSeconds: Int
    private(set) var isRunning = false
    private(set) var isExpired = false
    /// Absolute deadline the countdown is derived from. Nil until started.
    private(set) var endDate: Date?
    let totalSeconds: Int

    private let notificationScheduler: any NotificationScheduling
    private let now: () -> Date

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(remainingSeconds) / Double(totalSeconds)
    }

    init(
        durationSeconds: Int,
        notificationScheduler: any NotificationScheduling,
        now: @escaping () -> Date = { Date() }
    ) {
        self.totalSeconds = durationSeconds
        self.remainingSeconds = durationSeconds
        self.notificationScheduler = notificationScheduler
        self.now = now
    }

    func start() {
        let deadline = now().addingTimeInterval(TimeInterval(totalSeconds))
        endDate = deadline
        remainingSeconds = totalSeconds
        isRunning = true
        isExpired = false
        notificationScheduler.requestAuthorizationIfNeeded()
        notificationScheduler.scheduleRestCompleteNotification(at: deadline)
    }

    func skip() {
        remainingSeconds = 0
        isRunning = false
        endDate = nil
        notificationScheduler.cancelRestCompleteNotification()
    }

    func addTime(_ seconds: Int) {
        guard let current = endDate else { return }
        let newDeadline = current.addingTimeInterval(TimeInterval(seconds))
        endDate = newDeadline
        // Recompute first: a deadline moved into the past expires right away
        // (which also cancels the pending notification).
        updateRemaining(playsFeedbackOnExpiry: true)
        if isRunning {
            notificationScheduler.scheduleRestCompleteNotification(at: newDeadline)
        }
    }

    func subtractTime(_ seconds: Int) {
        addTime(-seconds)
    }

    /// Called on every foreground timer tick. Derives remaining time from the
    /// clock so missed ticks never stall the countdown.
    func tick() {
        guard isRunning else { return }
        updateRemaining(playsFeedbackOnExpiry: true)
    }

    /// Called when the app returns to the foreground (scenePhase → .active).
    /// If the deadline passed while suspended, completion fires immediately —
    /// without the in-app chime, since the local notification already sounded.
    func refreshFromClock() {
        guard isRunning else { return }
        updateRemaining(playsFeedbackOnExpiry: false)
    }

    private func updateRemaining(playsFeedbackOnExpiry: Bool) {
        guard let endDate else { return }
        let interval = endDate.timeIntervalSince(now())
        remainingSeconds = max(0, Int(interval.rounded(.up)))
        if remainingSeconds == 0 {
            expire(playsFeedback: playsFeedbackOnExpiry)
        }
    }

    private func expire(playsFeedback: Bool) {
        guard !isExpired else { return }
        isRunning = false
        isExpired = true
        notificationScheduler.cancelRestCompleteNotification()
        if playsFeedback {
            AudioServicesPlaySystemSound(1007)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
