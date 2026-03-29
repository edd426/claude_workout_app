import Foundation
import Observation
import AudioToolbox
import UIKit

@Observable
@MainActor
final class RestTimerViewModel {
    var remainingSeconds: Int
    var isRunning = false
    var isExpired = false
    let totalSeconds: Int

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(remainingSeconds) / Double(totalSeconds)
    }

    init(durationSeconds: Int) {
        self.totalSeconds = durationSeconds
        self.remainingSeconds = durationSeconds
    }

    func start() {
        isRunning = true
        isExpired = false
    }

    func skip() {
        remainingSeconds = 0
        isRunning = false
    }

    func addTime(_ seconds: Int) {
        remainingSeconds += seconds
    }

    func subtractTime(_ seconds: Int) {
        remainingSeconds = max(0, remainingSeconds - seconds)
    }

    func tick() {
        guard isRunning, remainingSeconds > 0 else { return }
        remainingSeconds -= 1
        if remainingSeconds == 0 {
            isRunning = false
            isExpired = true
            AudioServicesPlaySystemSound(1007)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
