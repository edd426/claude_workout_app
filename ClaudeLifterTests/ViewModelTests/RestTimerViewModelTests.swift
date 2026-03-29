import Testing
import Foundation
@testable import ClaudeLifter

@Suite("RestTimerViewModel Tests")
@MainActor
struct RestTimerViewModelTests {

    @Test("init sets correct duration")
    func initSetsDuration() {
        let vm = RestTimerViewModel(durationSeconds: 90)
        #expect(vm.totalSeconds == 90)
        #expect(vm.remainingSeconds == 90)
        #expect(vm.isRunning == false)
    }

    @Test("start sets isRunning to true")
    func startSetsIsRunning() {
        let vm = RestTimerViewModel(durationSeconds: 90)
        vm.start()
        #expect(vm.isRunning == true)
    }

    @Test("skip sets remainingSeconds to zero and stops timer")
    func skipSetsRemainingToZero() {
        let vm = RestTimerViewModel(durationSeconds: 90)
        vm.start()
        vm.skip()
        #expect(vm.remainingSeconds == 0)
        #expect(vm.isRunning == false)
    }

    @Test("addTime increases remainingSeconds by amount")
    func addTimeIncreasesRemaining() {
        let vm = RestTimerViewModel(durationSeconds: 90)
        vm.start()
        vm.addTime(15)
        #expect(vm.remainingSeconds == 105)
    }

    @Test("subtractTime decreases remainingSeconds but not below zero")
    func subtractTimeDecreasesRemaining() {
        let vm = RestTimerViewModel(durationSeconds: 90)
        vm.start()
        vm.subtractTime(15)
        #expect(vm.remainingSeconds == 75)
    }

    @Test("subtractTime does not go below zero")
    func subtractTimeFloorAtZero() {
        let vm = RestTimerViewModel(durationSeconds: 10)
        vm.start()
        vm.subtractTime(30)
        #expect(vm.remainingSeconds == 0)
    }

    @Test("progress is 1.0 at start")
    func progressIsOneAtStart() {
        let vm = RestTimerViewModel(durationSeconds: 90)
        vm.start()
        #expect(abs(vm.progress - 1.0) < 0.001)
    }

    @Test("progress is 0.0 when skipped")
    func progressIsZeroWhenSkipped() {
        let vm = RestTimerViewModel(durationSeconds: 90)
        vm.start()
        vm.skip()
        #expect(abs(vm.progress - 0.0) < 0.001)
    }

    @Test("tick decrements remainingSeconds")
    func tickDecrementsRemaining() {
        let vm = RestTimerViewModel(durationSeconds: 90)
        vm.start()
        vm.tick()
        #expect(vm.remainingSeconds == 89)
    }

    @Test("tick at zero sets isRunning false and isExpired true")
    func tickAtZeroExpires() {
        let vm = RestTimerViewModel(durationSeconds: 1)
        vm.start()
        vm.tick()
        #expect(vm.remainingSeconds == 0)
        #expect(vm.isRunning == false)
        #expect(vm.isExpired == true)
    }
}
