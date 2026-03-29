import Foundation
import SwiftData

@MainActor
final class DependencyContainer {
    let workoutRepository: any WorkoutRepository
    let templateRepository: any TemplateRepository
    let exerciseRepository: any ExerciseRepository
    let autoFillService: any AutoFillServiceProtocol

    init(modelContext: ModelContext) {
        self.workoutRepository = SwiftDataWorkoutRepository(context: modelContext)
        self.templateRepository = SwiftDataTemplateRepository(context: modelContext)
        self.exerciseRepository = SwiftDataExerciseRepository(context: modelContext)
        self.autoFillService = AutoFillService(workoutRepository: SwiftDataWorkoutRepository(context: modelContext))
    }
}
