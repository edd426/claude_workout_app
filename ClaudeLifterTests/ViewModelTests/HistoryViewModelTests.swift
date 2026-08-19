import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@Suite("HistoryViewModel Tests")
@MainActor
struct HistoryViewModelTests {

    @Test("loadWorkouts populates workouts sorted by date descending")
    func loadWorkoutsPopulatesDescending() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let older = TestFixtures.makeWorkout(name: "Day 1", startedAt: Date(timeIntervalSinceNow: -7200))
        let newer = TestFixtures.makeWorkout(name: "Day 2", startedAt: Date(timeIntervalSinceNow: -3600))
        context.insert(older)
        context.insert(newer)
        try context.save()

        let repo = MockWorkoutRepository()
        repo.workouts = [older, newer]
        let vm = HistoryViewModel(workoutRepository: repo)

        await vm.loadWorkouts()

        #expect(vm.workouts.count == 2)
        #expect(vm.workouts.first?.name == "Day 2")
    }

    @Test("loadWorkouts with error sets errorMessage")
    func loadWorkoutsWithErrorSetsMessage() async {
        let repo = MockWorkoutRepository()
        repo.errorToThrow = NSError(domain: "test", code: 1)
        let vm = HistoryViewModel(workoutRepository: repo)

        await vm.loadWorkouts()

        #expect(vm.errorMessage != nil)
    }

    @Test("completedWorkouts filters out incomplete workouts")
    func completedWorkoutsFiltersIncomplete() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let complete = TestFixtures.makeWorkout(name: "Done", completedAt: Date())
        let we = WorkoutExercise(order: 0, exercise: TestFixtures.makeExercise())
        complete.exercises.append(we)
        let incomplete = TestFixtures.makeWorkout(name: "In progress", completedAt: nil)
        context.insert(complete)
        context.insert(incomplete)
        try context.save()

        let repo = MockWorkoutRepository()
        repo.workouts = [complete, incomplete]
        let vm = HistoryViewModel(workoutRepository: repo)

        await vm.loadWorkouts()

        #expect(vm.completedWorkouts.count == 1)
        #expect(vm.completedWorkouts.first?.name == "Done")
    }

    @Test("deleteWorkout removes workout and refreshes list")
    func deleteWorkoutRemovesAndRefreshes() async {
        let workout1 = TestFixtures.makeWorkout(name: "Push Day")
        let workout2 = TestFixtures.makeWorkout(name: "Pull Day")
        let repo = MockWorkoutRepository()
        repo.workouts = [workout1, workout2]
        let vm = HistoryViewModel(workoutRepository: repo)
        await vm.loadWorkouts()
        #expect(vm.workouts.count == 2)

        await vm.deleteWorkout(workout1)

        #expect(vm.workouts.count == 1)
        #expect(vm.workouts.first?.name == "Pull Day")
        #expect(repo.deletedWorkouts.count == 1)
        #expect(repo.deletedWorkouts.first?.id == workout1.id)
    }

    @Test("deleteWorkout with error sets errorMessage")
    func deleteWorkoutWithErrorSetsMessage() async {
        let workout = TestFixtures.makeWorkout(name: "Push Day")
        let repo = MockWorkoutRepository()
        repo.workouts = [workout]
        let vm = HistoryViewModel(workoutRepository: repo)
        await vm.loadWorkouts()

        repo.errorToThrow = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Delete failed"])
        await vm.deleteWorkout(workout)

        #expect(vm.errorMessage != nil)
        #expect(vm.workouts.count == 1)
    }

    @Test("updateWorkout saves changes via repository")
    func updateWorkoutSavesViaRepository() async {
        let workout = TestFixtures.makeWorkout(name: "Push Day")
        let repo = MockWorkoutRepository()
        repo.workouts = [workout]
        let vm = HistoryViewModel(workoutRepository: repo)
        await vm.loadWorkouts()

        workout.name = "Updated Push Day"
        await vm.updateWorkout(workout)

        #expect(repo.saveCallCount == 1)
        #expect(repo.savedWorkouts.first?.name == "Updated Push Day")
    }

    @Test("updateWorkout marks workout pending and bumps lastModified before saving")
    func updateWorkoutMarksPendingAndBumpsLastModified() async {
        let workout = TestFixtures.makeWorkout(name: "Push Day")
        workout.syncStatus = .synced
        workout.lastModified = .distantPast
        let repo = MockWorkoutRepository()
        repo.workouts = [workout]
        let vm = HistoryViewModel(workoutRepository: repo)
        await vm.loadWorkouts()

        await vm.updateWorkout(workout)

        #expect(workout.syncStatus == .pending, "History edits must re-queue the workout for sync")
        #expect(workout.lastModified > .distantPast, "History edits must bump lastModified for LWW")
        #expect(repo.saveCallCount == 1)
    }

    @Test("updateWorkout with error sets errorMessage")
    func updateWorkoutWithErrorSetsMessage() async {
        let workout = TestFixtures.makeWorkout(name: "Push Day")
        let repo = MockWorkoutRepository()
        repo.workouts = [workout]
        let vm = HistoryViewModel(workoutRepository: repo)
        await vm.loadWorkouts()

        repo.errorToThrow = NSError(domain: "test", code: 99, userInfo: [NSLocalizedDescriptionKey: "Save failed"])
        await vm.updateWorkout(workout)

        #expect(vm.errorMessage != nil)
    }

    // MARK: - Date Range Tests

    @Test("loadWorkouts uses fetchByDateRange instead of fetchAll")
    func testLoadWorkoutsUsesDateRange() async {
        let repo = MockWorkoutRepository()
        repo.workouts = [TestFixtures.makeWorkout(name: "Push Day")]
        let vm = HistoryViewModel(workoutRepository: repo)

        await vm.loadWorkouts()

        #expect(repo.fetchAllCallCount == 0, "Should not call fetchAll")
        #expect(repo.fetchByDateRangeCallCount == 1, "Should call fetchByDateRange")
        // Should request ~90 days back
        let expectedFrom = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        let actualFrom = try! #require(repo.lastDateRangeFrom)
        let diff = abs(actualFrom.timeIntervalSince(expectedFrom))
        #expect(diff < 5, "From date should be ~90 days ago")
    }

    @Test("loadOlder extends date range further back")
    func testLoadOlderExtendsDateRange() async {
        let repo = MockWorkoutRepository()
        let vm = HistoryViewModel(workoutRepository: repo)

        await vm.loadWorkouts()
        let firstCallCount = repo.fetchByDateRangeCallCount

        await vm.loadOlder()

        #expect(repo.fetchByDateRangeCallCount == firstCallCount + 1)
        // Should now reach 180 days back
        let expectedFrom = Calendar.current.date(byAdding: .day, value: -180, to: Date())!
        let actualFrom = try! #require(repo.lastDateRangeFrom)
        let diff = abs(actualFrom.timeIntervalSince(expectedFrom))
        #expect(diff < 5, "From date should be ~180 days ago after loadOlder")
    }

    // MARK: - #69: Empty workout filtering

    @Test("completedWorkouts filters out workouts with no exercises")
    func completedWorkouts_filtersEmptyWorkouts() async throws {
        let withExercises = TestFixtures.makeWorkout(name: "Push Day", completedAt: Date())
        let we = WorkoutExercise(order: 0, exercise: TestFixtures.makeExercise())
        withExercises.exercises.append(we)

        let empty = TestFixtures.makeWorkout(name: "Empty Quick", completedAt: Date())
        // empty has no exercises

        let repo = MockWorkoutRepository()
        repo.workouts = [withExercises, empty]
        let vm = HistoryViewModel(workoutRepository: repo)

        await vm.loadWorkouts()

        #expect(vm.completedWorkouts.count == 1, "Empty workouts should be filtered from history")
        #expect(vm.completedWorkouts.first?.name == "Push Day")
    }

    // MARK: - Editing a past workout (#117)
    //
    // The detail view wrote `set.weight` straight to the model on every
    // keystroke, so the edit persisted locally but never re-queued the parent
    // workout for sync — history silently diverged from the mirror. It also
    // could not clear a value, because `Double("")` is nil and the write was
    // behind `if let`.

    @MainActor
    private func makeEditableWorkout() throws -> (ModelContainer, Workout, WorkoutSet, MockWorkoutRepository) {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)
        let workout = TestFixtures.makeWorkout(name: "Push Day")
        context.insert(workout)
        let we = TestFixtures.makeWorkoutExercise(exercise: exercise, in: context)
        workout.exercises.append(we)
        try context.save()
        workout.syncStatus = .synced
        let set = we.sets.sorted(by: { $0.order < $1.order })[0]
        return (container, workout, set, MockWorkoutRepository())
    }

    @Test("Editing a past set re-queues the workout for sync")
    func editingPastSetRequeuesForSync() async throws {
        let (container, workout, set, repo) = try makeEditableWorkout()
        let vm = HistoryViewModel(workoutRepository: repo)
        let before = workout.lastModified

        await vm.updateSet(set, weight: 72.5, in: workout)

        #expect(set.weight == 72.5)
        #expect(workout.syncStatus == .pending, "an edit the server never hears about is a silent divergence")
        #expect(workout.lastModified > before)
        #expect(repo.savedWorkouts.contains { $0.id == workout.id })
        withExtendedLifetime(container) {}
    }

    @Test("A cleared weight becomes nil, which is how bodyweight is recorded")
    func clearingWeightStoresNil() async throws {
        let (container, workout, set, repo) = try makeEditableWorkout()
        let vm = HistoryViewModel(workoutRepository: repo)

        await vm.updateSet(set, weight: nil, in: workout)

        #expect(set.weight == nil)
        #expect(workout.syncStatus == .pending)
        withExtendedLifetime(container) {}
    }

    @Test("Editing reps re-queues the workout, and reps can be cleared")
    func editingRepsRequeuesAndClears() async throws {
        let (container, workout, set, repo) = try makeEditableWorkout()
        let vm = HistoryViewModel(workoutRepository: repo)

        await vm.updateSet(set, reps: 12, in: workout)
        #expect(set.reps == 12)
        #expect(workout.syncStatus == .pending)

        workout.syncStatus = .synced
        await vm.updateSet(set, reps: nil, in: workout)
        #expect(set.reps == nil)
        #expect(workout.syncStatus == .pending)
        withExtendedLifetime(container) {}
    }

    @Test("An unchanged value does not re-queue the workout")
    func unchangedValueDoesNotRequeue() async throws {
        let (container, workout, set, repo) = try makeEditableWorkout()
        let vm = HistoryViewModel(workoutRepository: repo)
        let existing = set.weight

        await vm.updateSet(set, weight: existing, in: workout)

        #expect(workout.syncStatus == .synced, "a no-op edit must not churn sync state")
        #expect(repo.savedWorkouts.isEmpty)
        withExtendedLifetime(container) {}
    }

    @Test("A failing save surfaces an error instead of failing silently")
    func failingSaveSurfacesError() async throws {
        let (container, workout, set, repo) = try makeEditableWorkout()
        repo.errorToThrow = NSError(domain: "test", code: 117)
        let vm = HistoryViewModel(workoutRepository: repo)

        await vm.updateSet(set, weight: 80, in: workout)

        #expect(vm.errorMessage != nil)
        withExtendedLifetime(container) {}
    }
}
