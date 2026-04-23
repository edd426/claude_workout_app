import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

/// Regression tests for Phase 3 — verify that repository methods never
/// load unbounded result sets into memory. Issue #71 (SIGKILL after ~60
/// minutes on device) was caused by `fetchAll()` being used inside hot
/// query paths. These tests lock in the fix by inserting far more rows
/// than any normal user would have and asserting the bounded query still
/// returns in a reasonable time AND respects its `limit` cap.
///
/// Using the real `SwiftDataWorkoutRepository` (not a mock) so that any
/// future regression to `fetchAll()` shows up here.
@Suite("Pagination Bounds Tests")
@MainActor
struct PaginationBoundsTests {

    /// recentSets should cap at the provided limit even when far more
    /// candidate sets exist. Previously failing when #71 was in flight
    /// because the code fetched every workout and every set.
    @Test("recentSets honors limit on a large history")
    func recentSetsHonorsLimit() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Bench", isCustom: false)
        context.insert(exercise)

        // Seed 200 workouts, each with 3 completed sets of the same exercise.
        // That's 600 candidate sets for a single exerciseId — well above any
        // realistic user. If the repository ever regresses to fetching all
        // of them, the query slows dramatically and this test times out.
        let now = Date()
        for i in 0..<200 {
            let workout = Workout(
                name: "Session \(i)",
                startedAt: now.addingTimeInterval(-Double(i) * 3600)
            )
            let we = WorkoutExercise(order: 0, exercise: exercise)
            for s in 0..<3 {
                let set = WorkoutSet(order: s, weight: 80, weightUnit: .kg, reps: 8)
                set.isCompleted = true
                we.sets.append(set)
            }
            workout.exercises.append(we)
            context.insert(workout)
        }
        try context.save()

        let repo = SwiftDataWorkoutRepository(context: context)
        let start = Date()
        let sets = try await repo.recentSets(for: exercise.id, limit: 10)
        let elapsed = Date().timeIntervalSince(start)

        #expect(sets.count == 10)
        #expect(elapsed < 1.0, "recentSets took \(elapsed)s on 200 workouts — regression to unbounded fetch?")
        withExtendedLifetime(container) {}
    }

    /// lastSessionSets should return just the most-recent session's sets
    /// and not grow with history size. Bounds matter because the method is
    /// called by AutoFillService every time the user starts a workout.
    @Test("lastSessionSets returns only the most recent session's sets")
    func lastSessionSetsBounded() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Deadlift", isCustom: false)
        context.insert(exercise)

        // 30 historical sessions, each with 5 completed sets (150 candidates).
        let now = Date()
        for i in 0..<30 {
            let workout = Workout(
                name: "DL \(i)",
                startedAt: now.addingTimeInterval(-Double(i) * 86_400)
            )
            let we = WorkoutExercise(order: 0, exercise: exercise)
            for s in 0..<5 {
                let set = WorkoutSet(order: s, weight: 100, weightUnit: .kg, reps: 5)
                set.isCompleted = true
                we.sets.append(set)
            }
            workout.exercises.append(we)
            context.insert(workout)
        }
        try context.save()

        let repo = SwiftDataWorkoutRepository(context: context)
        let sets = try await repo.lastSessionSets(for: exercise.id)
        #expect(sets.count == 5,
                "lastSessionSets must return only the most recent session's sets, got \(sets.count)")
        withExtendedLifetime(container) {}
    }

    /// fetchByDateRange should return only workouts within the given range,
    /// even when the total workout count is large. Used by calendar and
    /// charts which are hot paths.
    @Test("fetchByDateRange bounds results to the window")
    func fetchByDateRangeBounded() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let base = Date()
        // 100 workouts spanning 100 days in the past.
        for i in 0..<100 {
            let workout = Workout(
                name: "W \(i)",
                startedAt: base.addingTimeInterval(-Double(i) * 86_400)
            )
            context.insert(workout)
        }
        try context.save()

        let repo = SwiftDataWorkoutRepository(context: context)
        // Ask for only the last 7 days.
        let from = base.addingTimeInterval(-7 * 86_400)
        let within = try await repo.fetchByDateRange(from: from, to: base)
        #expect(within.count <= 8,
                "Expected ≤8 workouts in last 7 days, got \(within.count) — predicate broken?")
        withExtendedLifetime(container) {}
    }
}
