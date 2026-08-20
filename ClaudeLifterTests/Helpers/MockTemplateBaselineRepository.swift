import Foundation
@testable import ClaudeLifter

@MainActor
final class MockTemplateBaselineRepository: TemplateBaselineRepository {
    var baselines: [WorkoutTemplateBaseline] = []
    var entries: [WorkoutExerciseBaseline] = []
    var saveCallCount = 0
    var deletedWorkoutIds: [UUID] = []
    var errorToThrow: Error?

    func fetchBaseline(workoutId: UUID) async throws -> WorkoutTemplateBaseline? {
        if let errorToThrow { throw errorToThrow }
        return baselines.first { $0.workoutId == workoutId }
    }

    func fetchEntries(workoutId: UUID) async throws -> [WorkoutExerciseBaseline] {
        if let errorToThrow { throw errorToThrow }
        return entries
            .filter { $0.workoutId == workoutId }
            .sorted { $0.plannedOrder < $1.plannedOrder }
    }

    func save(
        _ baseline: WorkoutTemplateBaseline,
        entries newEntries: [WorkoutExerciseBaseline]
    ) async throws {
        saveCallCount += 1
        if let errorToThrow { throw errorToThrow }
        baselines.append(baseline)
        entries.append(contentsOf: newEntries)
    }

    func delete(workoutId: UUID) async throws {
        if let errorToThrow { throw errorToThrow }
        deletedWorkoutIds.append(workoutId)
        baselines.removeAll { $0.workoutId == workoutId }
        entries.removeAll { $0.workoutId == workoutId }
    }
}
