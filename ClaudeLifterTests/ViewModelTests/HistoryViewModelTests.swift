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
}
