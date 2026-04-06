import Foundation
@testable import ClaudeLifter

@MainActor
final class MockWorkoutRepository: WorkoutRepository {
    var workouts: [Workout] = []
    var savedWorkouts: [Workout] = []
    var deletedWorkouts: [Workout] = []
    var lastSessionSetsResult: [WorkoutSet] = []
    var recentSetsResult: [WorkoutSet] = []
    var lastWorkoutDateResult: Date? = nil
    var fetchAllCallCount = 0
    var saveCallCount = 0
    var errorToThrow: Error? = nil
    var fetchByDateRangeCallCount = 0
    var lastDateRangeFrom: Date?
    var lastDateRangeTo: Date?

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

    func lastWorkoutDate(for exerciseId: UUID) async throws -> Date? {
        if let error = errorToThrow { throw error }
        return lastWorkoutDateResult
    }

    func save(_ workout: Workout) async throws {
        saveCallCount += 1
        if let error = errorToThrow { throw error }
        savedWorkouts.append(workout)
        if !workouts.contains(where: { $0.id == workout.id }) {
            workouts.append(workout)
        }
    }

    func fetchPending() async throws -> [Workout] {
        if let error = errorToThrow { throw error }
        return workouts.filter { $0.syncStatus == .pending }
    }

    func fetchByDateRange(from: Date, to: Date) async throws -> [Workout] {
        fetchByDateRangeCallCount += 1
        lastDateRangeFrom = from
        lastDateRangeTo = to
        if let error = errorToThrow { throw error }
        return workouts.filter { $0.startedAt >= from && $0.startedAt <= to }
    }

    func delete(_ workout: Workout) async throws {
        if let error = errorToThrow { throw error }
        deletedWorkouts.append(workout)
        workouts.removeAll { $0.id == workout.id }
    }
}
