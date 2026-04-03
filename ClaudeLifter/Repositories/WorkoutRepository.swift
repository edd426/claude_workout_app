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
    /// Returns the startedAt date of the most recent workout that contained the given exercise.
    func lastWorkoutDate(for exerciseId: UUID) async throws -> Date?
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
        // SwiftData cannot filter through relationship chains in #Predicate, so we fetch
        // recent workouts with a fetchLimit instead of loading all of history.
        var descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        // Cap at 50 recent workouts — enough for any practical limit query.
        descriptor.fetchLimit = 50
        let workouts = try context.fetch(descriptor)
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
        // Fetch only the most recent 50 workouts to bound memory usage.
        var descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        let workouts = try context.fetch(descriptor)
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

    func lastWorkoutDate(for exerciseId: UUID) async throws -> Date? {
        // Fetch recent workouts sorted descending; find the first that contains the exercise.
        var descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        let workouts = try context.fetch(descriptor)
        for workout in workouts {
            if workout.exercises.contains(where: { $0.exercise?.id == exerciseId }) {
                return workout.startedAt
            }
        }
        return nil
    }

    func fetchPending() async throws -> [Workout] {
        // SwiftData #Predicate cannot traverse enum .rawValue at runtime,
        // so we use in-memory filtering. Pending workouts are always recent
        // (created since last sync), so this set stays small in practice.
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
