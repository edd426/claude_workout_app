import Foundation
import Observation

@Observable
@MainActor
final class HomeViewModel {
    var templates: [WorkoutTemplate] = []
    var isLoading = false
    var errorMessage: String? = nil

    private let templateRepository: any TemplateRepository
    private let workoutRepository: (any WorkoutRepository)?

    init(templateRepository: any TemplateRepository, workoutRepository: (any WorkoutRepository)? = nil) {
        self.templateRepository = templateRepository
        self.workoutRepository = workoutRepository
    }

    func loadTemplates() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            templates = try await templateRepository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createAdHocWorkout() async throws -> Workout {
        guard let workoutRepository else {
            throw HomeViewModelError.noWorkoutRepository
        }
        let workout = Workout(name: "Quick Workout", startedAt: .now, templateId: nil)
        try await workoutRepository.save(workout)
        return workout
    }
}

enum HomeViewModelError: Error {
    case noWorkoutRepository
}
