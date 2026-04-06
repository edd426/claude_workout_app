import Foundation

// MARK: - ToolContext

// @unchecked Sendable because Workout (@Model) is not Sendable, but ToolContext
// is only used on the MainActor within ChatViewModel.
struct ToolContext: @unchecked Sendable {
    let exerciseRepository: any ExerciseRepository
    let workoutRepository: any WorkoutRepository
    let templateRepository: any TemplateRepository
    /// The active workout session, if any. Used by add/remove exercise tools.
    let activeWorkout: Workout?
    /// Callback to start a workout from a template. Provided by ChatViewModel when AppState is available.
    var onStartWorkout: (@MainActor @Sendable (WorkoutTemplate) async -> Void)?
}
