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

    // MARK: - Crash recovery (#75)

    /// The most recent in-progress workout with actual content, surfaced on
    /// the Home screen with a Resume/Discard prompt. Nil when there is
    /// nothing to recover.
    var resumableWorkout: Workout? = nil

    /// Detects a crash-orphaned or draft-saved in-progress workout
    /// (`completedAt == nil`) so Home can offer Resume / Discard. Empty
    /// ghost sessions are ignored — start-workout cleanup handles those.
    func checkForResumableWorkout() async {
        guard let workoutRepository else { return }
        do {
            let all = try await workoutRepository.fetchAll()
            resumableWorkout = all
                .filter { $0.completedAt == nil && !$0.isEmptyGhostSession }
                .max { $0.startedAt < $1.startedAt }
        } catch {
            // Non-fatal: Home still works without resume detection.
            resumableWorkout = nil
        }
    }

    /// Deletes exactly the surfaced draft — only ever called after the
    /// user's explicit Discard choice — then surfaces the next lingering
    /// draft, if any.
    func discardResumableWorkout() async {
        guard let workout = resumableWorkout, let workoutRepository else { return }
        do {
            try await workoutRepository.delete(workout)
            resumableWorkout = nil
            await checkForResumableWorkout()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum HomeViewModelError: Error {
    case noWorkoutRepository
}
