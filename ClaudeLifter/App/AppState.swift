import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var isWorkoutActive: Bool = false
    var activeWorkoutId: UUID? = nil
    var activeWorkoutVM: ActiveWorkoutViewModel? = nil

    func startWorkout(id: UUID, vm: ActiveWorkoutViewModel) {
        activeWorkoutId = id
        activeWorkoutVM = vm
        isWorkoutActive = true
    }

    func endWorkout() {
        activeWorkoutId = nil
        activeWorkoutVM = nil
        isWorkoutActive = false
    }
}
