import Foundation
import SwiftData

@MainActor
protocol WorkoutRepository {
    func fetchAll() async throws -> [Workout]
    func fetch(id: UUID) async throws -> Workout?
    func fetchByTemplate(id: UUID) async throws -> [Workout]
    /// Returns completed sets for the given exercise from the most recent workouts,
    /// sorted by workout date descending then set order ascending within each workout.
    func recentSets(for exerciseId: UUID, limit: Int) async throws -> [WorkoutSet]
    /// Returns completed sets from the single most recent workout containing the exercise.
    func lastSessionSets(for exerciseId: UUID) async throws -> [WorkoutSet]
    func fetchPending() async throws -> [Workout]
    func fetchByDateRange(from: Date, to: Date) async throws -> [Workout]
    func save(_ workout: Workout) async throws
    func delete(_ workout: Workout) async throws
}

@MainActor
final class SwiftDataWorkoutRepository: WorkoutRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() async throws -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(id: UUID) async throws -> Workout? {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func fetchByTemplate(id: UUID) async throws -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.templateId == id },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func recentSets(for exerciseId: UUID, limit: Int) async throws -> [WorkoutSet] {
        let workouts = try context.fetch(FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))
        var results: [WorkoutSet] = []
        for workout in workouts {
            for we in workout.exercises {
                if we.exercise?.id == exerciseId {
                    let completed = we.sets.filter { $0.isCompleted }.sorted { $0.order < $1.order }
                    results.append(contentsOf: completed)
                    if results.count >= limit { break }
                }
            }
            if results.count >= limit { break }
        }
        return Array(results.prefix(limit))
    }

    func lastSessionSets(for exerciseId: UUID) async throws -> [WorkoutSet] {
        let workouts = try context.fetch(FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))
        for workout in workouts {
            for we in workout.exercises {
                if we.exercise?.id == exerciseId {
                    let completed = we.sets.filter { $0.isCompleted }.sorted { $0.order < $1.order }
                    if !completed.isEmpty {
                        return completed
                    }
                }
            }
        }
        return []
    }

    func fetchPending() async throws -> [Workout] {
        let all = try context.fetch(FetchDescriptor<Workout>())
        return all.filter { $0.syncStatus == .pending }
    }

    func fetchByDateRange(from: Date, to: Date) async throws -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.startedAt >= from && $0.startedAt <= to },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func save(_ workout: Workout) async throws {
        context.insert(workout)
        try context.save()
    }

    func delete(_ workout: Workout) async throws {
        context.delete(workout)
        try context.save()
    }
}
