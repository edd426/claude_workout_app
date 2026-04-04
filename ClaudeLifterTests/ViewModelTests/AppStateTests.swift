import Testing
import Foundation
@testable import ClaudeLifter

@Suite("AppState Tests")
@MainActor
struct AppStateTests {

    private func makeDummyVM() -> ActiveWorkoutViewModel {
        ActiveWorkoutViewModel(
            adHocName: "Test",
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService()
        )
    }

    @Test("initial state has no active workout")
    func initialStateHasNoActiveWorkout() {
        let state = AppState()
        #expect(state.isWorkoutActive == false)
        #expect(state.activeWorkoutId == nil)
        #expect(state.activeWorkoutVM == nil)
    }

    @Test("startWorkout sets isWorkoutActive, activeWorkoutId, and activeWorkoutVM")
    func startWorkoutSetsState() {
        let state = AppState()
        let id = UUID()
        let vm = makeDummyVM()

        state.startWorkout(id: id, vm: vm)

        #expect(state.isWorkoutActive == true)
        #expect(state.activeWorkoutId == id)
        #expect(state.activeWorkoutVM != nil)
    }

    @Test("endWorkout clears isWorkoutActive, activeWorkoutId, and activeWorkoutVM")
    func endWorkoutClearsState() {
        let state = AppState()
        state.startWorkout(id: UUID(), vm: makeDummyVM())

        state.endWorkout()

        #expect(state.isWorkoutActive == false)
        #expect(state.activeWorkoutId == nil)
        #expect(state.activeWorkoutVM == nil)
    }
}
