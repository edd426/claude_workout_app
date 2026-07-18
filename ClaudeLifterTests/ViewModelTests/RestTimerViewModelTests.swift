import Testing
import Foundation
@testable import ClaudeLifter

/// Mutable clock so tests can simulate suspension by jumping time.
@MainActor
private final class TestClock {
    var now: Date

    init(now: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self.now = now
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

@Suite("RestTimerViewModel Tests")
@MainActor
struct RestTimerViewModelTests {

    private func makeVM(
        duration: Int = 90
    ) -> (vm: RestTimerViewModel, scheduler: MockNotificationScheduler, clock: TestClock) {
        let clock = TestClock()
        let scheduler = MockNotificationScheduler()
        let vm = RestTimerViewModel(
            durationSeconds: duration,
            notificationScheduler: scheduler,
            now: { clock.now }
        )
        return (vm, scheduler, clock)
    }

    // MARK: - Basic lifecycle

    @Test("init sets correct duration")
    func initSetsDuration() {
        let (vm, _, _) = makeVM(duration: 90)
        #expect(vm.totalSeconds == 90)
        #expect(vm.remainingSeconds == 90)
        #expect(vm.isRunning == false)
    }

    @Test("start sets isRunning to true")
    func startSetsIsRunning() {
        let (vm, _, _) = makeVM()
        vm.start()
        #expect(vm.isRunning == true)
    }

    @Test("start records an absolute end date of now plus duration")
    func startRecordsEndDate() {
        let (vm, _, clock) = makeVM(duration: 90)
        vm.start()
        #expect(vm.endDate == clock.now.addingTimeInterval(90))
    }

    @Test("skip sets remainingSeconds to zero and stops timer")
    func skipSetsRemainingToZero() {
        let (vm, _, _) = makeVM()
        vm.start()
        vm.skip()
        #expect(vm.remainingSeconds == 0)
        #expect(vm.isRunning == false)
    }

    @Test("progress is 1.0 at start")
    func progressIsOneAtStart() {
        let (vm, _, _) = makeVM()
        vm.start()
        #expect(abs(vm.progress - 1.0) < 0.001)
    }

    @Test("progress is 0.0 when skipped")
    func progressIsZeroWhenSkipped() {
        let (vm, _, _) = makeVM()
        vm.start()
        vm.skip()
        #expect(abs(vm.progress - 0.0) < 0.001)
    }

    // MARK: - Clock-derived countdown (issue #77)

    @Test("tick derives remaining time from the clock, not tick counts")
    func tickDerivesRemainingFromClock() {
        let (vm, _, clock) = makeVM(duration: 90)
        vm.start()
        clock.advance(by: 1)
        vm.tick()
        #expect(vm.remainingSeconds == 89)
    }

    @Test("missed ticks do not stall the countdown — a large clock jump is fully accounted for")
    func clockJumpAccountedFor() {
        let (vm, _, clock) = makeVM(duration: 90)
        vm.start()
        // Simulate suspension: no ticks delivered for 60 seconds.
        clock.advance(by: 60)
        vm.tick()
        #expect(vm.remainingSeconds == 30)
    }

    @Test("clock jump past the deadline expires the timer on next tick")
    func clockJumpPastDeadlineExpires() {
        let (vm, _, clock) = makeVM(duration: 90)
        vm.start()
        clock.advance(by: 120)
        vm.tick()
        #expect(vm.remainingSeconds == 0)
        #expect(vm.isRunning == false)
        #expect(vm.isExpired == true)
    }

    @Test("tick exactly at deadline expires the timer")
    func tickAtDeadlineExpires() {
        let (vm, _, clock) = makeVM(duration: 1)
        vm.start()
        clock.advance(by: 1)
        vm.tick()
        #expect(vm.remainingSeconds == 0)
        #expect(vm.isRunning == false)
        #expect(vm.isExpired == true)
    }

    @Test("tick before start does nothing")
    func tickBeforeStartDoesNothing() {
        let (vm, _, clock) = makeVM(duration: 90)
        clock.advance(by: 10)
        vm.tick()
        #expect(vm.remainingSeconds == 90)
        #expect(vm.isExpired == false)
    }

    // MARK: - Foreground return (scenePhase)

    @Test("refreshFromClock mid-countdown updates remaining without expiring")
    func refreshMidCountdownUpdatesRemaining() {
        let (vm, _, clock) = makeVM(duration: 90)
        vm.start()
        clock.advance(by: 30)
        vm.refreshFromClock()
        #expect(vm.remainingSeconds == 60)
        #expect(vm.isExpired == false)
        #expect(vm.isRunning == true)
    }

    @Test("refreshFromClock after the deadline passed while suspended expires immediately")
    func refreshPastDeadlineExpiresImmediately() {
        let (vm, _, clock) = makeVM(duration: 90)
        vm.start()
        clock.advance(by: 200)
        vm.refreshFromClock()
        #expect(vm.remainingSeconds == 0)
        #expect(vm.isRunning == false)
        #expect(vm.isExpired == true)
    }

    @Test("expiry fires exactly once even if tick and refresh both observe the passed deadline")
    func expiryFiresOnce() {
        let (vm, scheduler, clock) = makeVM(duration: 90)
        vm.start()
        clock.advance(by: 200)
        vm.tick()
        vm.refreshFromClock()
        vm.tick()
        #expect(vm.isExpired == true)
        #expect(scheduler.cancelCount == 1)
    }

    // MARK: - Adjust buttons move the deadline

    @Test("addTime moves the deadline forward and updates remaining")
    func addTimeMovesDeadline() {
        let (vm, _, clock) = makeVM(duration: 90)
        vm.start()
        vm.addTime(15)
        #expect(vm.remainingSeconds == 105)
        #expect(vm.endDate == clock.now.addingTimeInterval(105))
    }

    @Test("subtractTime moves the deadline back and updates remaining")
    func subtractTimeMovesDeadline() {
        let (vm, _, clock) = makeVM(duration: 90)
        vm.start()
        vm.subtractTime(15)
        #expect(vm.remainingSeconds == 75)
        #expect(vm.endDate == clock.now.addingTimeInterval(75))
    }

    @Test("subtractTime past zero clamps remaining at zero and expires")
    func subtractTimeFloorAtZero() {
        let (vm, _, _) = makeVM(duration: 10)
        vm.start()
        vm.subtractTime(30)
        #expect(vm.remainingSeconds == 0)
        #expect(vm.isExpired == true)
        #expect(vm.isRunning == false)
    }

    // MARK: - Local notification scheduling

    @Test("start requests notification authorization")
    func startRequestsAuthorization() {
        let (vm, scheduler, _) = makeVM()
        vm.start()
        #expect(scheduler.authorizationRequestCount == 1)
    }

    @Test("start schedules a notification at the end date")
    func startSchedulesNotificationAtEndDate() {
        let (vm, scheduler, clock) = makeVM(duration: 90)
        vm.start()
        #expect(scheduler.scheduledFireDates == [clock.now.addingTimeInterval(90)])
    }

    @Test("skip cancels the pending notification")
    func skipCancelsNotification() {
        let (vm, scheduler, _) = makeVM()
        vm.start()
        vm.skip()
        #expect(scheduler.cancelCount == 1)
    }

    @Test("foreground expiry cancels the pending notification")
    func foregroundExpiryCancelsNotification() {
        let (vm, scheduler, clock) = makeVM(duration: 1)
        vm.start()
        clock.advance(by: 1)
        vm.tick()
        #expect(scheduler.cancelCount == 1)
    }

    @Test("addTime reschedules the notification at the new deadline")
    func addTimeReschedulesNotification() {
        let (vm, scheduler, clock) = makeVM(duration: 90)
        vm.start()
        vm.addTime(15)
        #expect(scheduler.scheduledFireDates.last == clock.now.addingTimeInterval(105))
        #expect(scheduler.scheduledFireDates.count == 2)
    }

    @Test("subtractTime reschedules the notification at the new deadline")
    func subtractTimeReschedulesNotification() {
        let (vm, scheduler, clock) = makeVM(duration: 90)
        vm.start()
        vm.subtractTime(15)
        #expect(scheduler.scheduledFireDates.last == clock.now.addingTimeInterval(75))
        #expect(scheduler.scheduledFireDates.count == 2)
    }

    @Test("subtractTime past zero cancels the notification instead of rescheduling")
    func subtractPastZeroCancelsNotification() {
        let (vm, scheduler, _) = makeVM(duration: 10)
        vm.start()
        vm.subtractTime(30)
        #expect(scheduler.cancelCount == 1)
        // Only the schedule from start(); no reschedule for an already-passed deadline.
        #expect(scheduler.scheduledFireDates.count == 1)
    }
}
