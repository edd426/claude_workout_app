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

    /// Edits a set on a **past** workout (#117).
    ///
    /// History edits used to be written straight to the model by the detail
    /// view, so they persisted locally and were never re-queued for sync — the
    /// local record silently diverged from the mirror. Every edit goes through
    /// here instead, mirroring the rule `ActiveWorkoutViewModel` states for the
    /// live session: views never write to WorkoutSet directly.
    ///
    /// `nil` is a legitimate value, not a failed parse: a nil weight is how a
    /// bodyweight set is recorded, and the old `if let value = Double(text)`
    /// made it unreachable.
    ///
    /// Deliberately *not* routed through `ActiveWorkoutViewModel.persistMutation`
    /// — that early-returns on a finished workout and its `saveDraft()` deletes
    /// records it judges empty, which is the wrong semantics for a completed
    /// session.
    func updateSet(_ set: WorkoutSet, weight: Double?, in workout: Workout) async {
        guard set.weight != weight else { return }
        set.weight = weight
        await persist(workout)
    }

    func updateSet(_ set: WorkoutSet, reps: Int?, in workout: Workout) async {
        guard set.reps != reps else { return }
        set.reps = reps
        await persist(workout)
    }

    private func persist(_ workout: Workout) async {
        workout.recordChange()
        do {
            try await workoutRepository.save(workout)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateWorkout(_ workout: Workout) async {
        // History edits mutate nested sets/exercises directly in the detail
        // view; without recordChange() here the edit never bumped the parent
        // Workout's lastModified nor re-queued it as .pending, so it was
        // invisible to sync last-write-wins (#76).
        workout.recordChange()
        do {
            try await workoutRepository.save(workout)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
