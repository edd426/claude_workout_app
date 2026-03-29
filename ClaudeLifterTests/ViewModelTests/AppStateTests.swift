import Testing
import Foundation
@testable import ClaudeLifter

@Suite("AppState Tests")
@MainActor
struct AppStateTests {

    @Test("initial state has no active workout")
    func initialStateHasNoActiveWorkout() {
        let state = AppState()
        #expect(state.isWorkoutActive == false)
        #expect(state.activeWorkoutId == nil)
    }

    @Test("startWorkout sets isWorkoutActive and activeWorkoutId")
    func startWorkoutSetsState() {
        let state = AppState()
        let id = UUID()

        state.startWorkout(id: id)

        #expect(state.isWorkoutActive == true)
        #expect(state.activeWorkoutId == id)
    }

    @Test("endWorkout clears isWorkoutActive and activeWorkoutId")
    func endWorkoutClearsState() {
        let state = AppState()
        state.startWorkout(id: UUID())

        state.endWorkout()

        #expect(state.isWorkoutActive == false)
        #expect(state.activeWorkoutId == nil)
    }
}
