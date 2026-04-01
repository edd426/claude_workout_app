import Foundation
import Observation

@Observable
@MainActor
final class HistoryViewModel {
    var workouts: [Workout] = []
    var isLoading = false
    var errorMessage: String? = nil

    var completedWorkouts: [Workout] {
        workouts.filter { $0.completedAt != nil }
    }

    private let workoutRepository: any WorkoutRepository

    init(workoutRepository: any WorkoutRepository) {
        self.workoutRepository = workoutRepository
    }

    func loadWorkouts() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let all = try await workoutRepository.fetchAll()
            workouts = all.sorted { $0.startedAt > $1.startedAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteWorkout(_ workout: Workout) async {
        do {
            try await workoutRepository.delete(workout)
            workouts.removeAll { $0.id == workout.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateWorkout(_ workout: Workout) async {
        do {
            try await workoutRepository.save(workout)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
