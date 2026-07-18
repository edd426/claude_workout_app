import Foundation
@testable import ClaudeLifter

@MainActor
final class MockNotificationScheduler: NotificationScheduling {
    var authorizationRequestCount = 0
    var scheduledFireDates: [Date] = []
    var cancelCount = 0

    func requestAuthorizationIfNeeded() {
        authorizationRequestCount += 1
    }

    func scheduleRestCompleteNotification(at fireDate: Date) {
        scheduledFireDates.append(fireDate)
    }

    func cancelRestCompleteNotification() {
        cancelCount += 1
    }
}
