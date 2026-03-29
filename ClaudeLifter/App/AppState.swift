import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var isWorkoutActive: Bool = false
    var activeWorkoutId: UUID? = nil

    func startWorkout(id: UUID) {
        activeWorkoutId = id
        isWorkoutActive = true
    }

    func endWorkout() {
        activeWorkoutId = nil
        isWorkoutActive = false
    }
}
