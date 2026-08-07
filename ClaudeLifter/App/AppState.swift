import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var isWorkoutActive: Bool = false
    var activeWorkoutId: UUID? = nil
    var activeWorkoutVM: ActiveWorkoutViewModel? = nil

    /// The receipt for the most recently finished workout, presented over Home.
    ///
    /// It lives here rather than on `ActiveWorkoutView` because `endWorkout()`
    /// tears that view down. Owning it at this level lets the workout end the
    /// instant its save commits, independently of whether the summary is shown
    /// or how it is dismissed (#123).
    var completedWorkoutSummary: WorkoutCompletionSummary? = nil

    func startWorkout(id: UUID, vm: ActiveWorkoutViewModel) {
        activeWorkoutId = id
        activeWorkoutVM = vm
        isWorkoutActive = true
        completedWorkoutSummary = nil
    }

    /// Leaves the active workout and, when there is one, publishes its receipt.
    /// Callers that discard a session pass no summary, which also clears any
    /// stale receipt still onscreen.
    func endWorkout(showing summary: WorkoutCompletionSummary? = nil) {
        activeWorkoutId = nil
        activeWorkoutVM = nil
        isWorkoutActive = false
        completedWorkoutSummary = summary
    }
}
