import Foundation
@testable import ClaudeLifter

final class MockWorkoutRepository: WorkoutRepository, @unchecked Sendable {
    var workouts: [Workout] = []
    var savedWorkouts: [Workout] = []
    var deletedWorkouts: [Workout] = []
    var lastSessionSetsResult: [WorkoutSet] = []
    var recentSetsResult: [WorkoutSet] = []
    var fetchAllCallCount = 0
    var saveCallCount = 0
    var errorToThrow: Error? = nil

    func fetchAll() async throws -> [Workout] {
        fetchAllCallCount += 1
        if let error = errorToThrow { throw error }
        return workouts
    }

    func fetch(id: UUID) async throws -> Workout? {
        if let error = errorToThrow { throw error }
        return workouts.first { $0.id == id }
    }

    func fetchByTemplate(id: UUID) async throws -> [Workout] {
        if let error = errorToThrow { throw error }
        return workouts.filter { $0.templateId == id }
    }

    func recentSets(for exerciseId: UUID, limit: Int) async throws -> [WorkoutSet] {
        if let error = errorToThrow { throw error }
        return Array(recentSetsResult.prefix(limit))
    }

    func lastSessionSets(for exerciseId: UUID) async throws -> [WorkoutSet] {
        if let error = errorToThrow { throw error }
        return lastSessionSetsResult
    }

    func save(_ workout: Workout) async throws {
        saveCallCount += 1
        if let error = errorToThrow { throw error }
        savedWorkouts.append(workout)
        if !workouts.contains(where: { $0.id == workout.id }) {
            workouts.append(workout)
        }
    }

    func delete(_ workout: Workout) async throws {
        if let error = errorToThrow { throw error }
        deletedWorkouts.append(workout)
        workouts.removeAll { $0.id == workout.id }
    }
}
