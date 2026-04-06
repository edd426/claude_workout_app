import Foundation
import Observation

@Observable
@MainActor
final class HistoryViewModel {
    var workouts: [Workout] = []
    var isLoading = false
    var errorMessage: String? = nil

    var completedWorkouts: [Workout] {
        workouts.filter { $0.completedAt != nil && !$0.exercises.isEmpty }
    }

    private let workoutRepository: any WorkoutRepository
    private static let windowDays = 90
    private var daysLoaded = 0

    init(workoutRepository: any WorkoutRepository) {
        self.workoutRepository = workoutRepository
    }

    func loadWorkouts() async {
        isLoading = true
        errorMessage = nil
        daysLoaded = Self.windowDays
        defer { isLoading = false }
        do {
            let from = Calendar.current.date(byAdding: .day, value: -Self.windowDays, to: Date()) ?? Date()
            let all = try await workoutRepository.fetchByDateRange(from: from, to: Date())
            workouts = all.sorted { $0.startedAt > $1.startedAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadOlder() async {
        let newDays = daysLoaded + Self.windowDays
        let from = Calendar.current.date(byAdding: .day, value: -newDays, to: Date()) ?? Date()
        let to = Calendar.current.date(byAdding: .day, value: -daysLoaded, to: Date()) ?? Date()
        do {
            let older = try await workoutRepository.fetchByDateRange(from: from, to: to)
            workouts.append(contentsOf: older)
            workouts.sort { $0.startedAt > $1.startedAt }
            daysLoaded = newDays
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
