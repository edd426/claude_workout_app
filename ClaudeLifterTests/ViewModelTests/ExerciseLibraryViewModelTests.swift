import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@Suite("ExerciseLibraryViewModel Tests")
@MainActor
struct ExerciseLibraryViewModelTests {

    @Test("loadExercises populates exercises")
    func loadExercisesPopulatesExercises() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let ex1 = TestFixtures.makeExercise(name: "Bench Press")
        let ex2 = TestFixtures.makeExercise(name: "Squat")
        context.insert(ex1)
        context.insert(ex2)
        try context.save()

        let repo = MockExerciseRepository()
        repo.exercises = [ex1, ex2]
        let vm = ExerciseLibraryViewModel(exerciseRepository: repo)

        await vm.loadExercises()

        #expect(vm.exercises.count == 2)
    }

    @Test("search updates exercises with results")
    func searchUpdatesExercises() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let ex = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(ex)
        try context.save()

        let repo = MockExerciseRepository()
        repo.exercises = [ex]
        let vm = ExerciseLibraryViewModel(exerciseRepository: repo)

        await vm.loadExercises()
        vm.searchQuery = "Bench"
        await vm.performSearch()

        #expect(repo.searchCallCount == 1)
        #expect(repo.lastSearchQuery == "Bench")
    }

    @Test("empty search query reloads all exercises")
    func emptySearchQueryReloadsAll() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let ex = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(ex)
        try context.save()

        let repo = MockExerciseRepository()
        repo.exercises = [ex]
        let vm = ExerciseLibraryViewModel(exerciseRepository: repo)

        await vm.loadExercises()
        vm.searchQuery = ""
        await vm.performSearch()

        #expect(vm.exercises.count == 1)
    }

    @Test("selectFilter updates selectedCategory and selectedValue")
    func selectFilterUpdatesState() {
        let repo = MockExerciseRepository()
        let vm = ExerciseLibraryViewModel(exerciseRepository: repo)

        vm.selectFilter(category: "equipment", value: "barbell")

        #expect(vm.selectedCategory == "equipment")
        #expect(vm.selectedValue == "barbell")
    }

    @Test("clearFilter resets selection")
    func clearFilterResetsSelection() {
        let vm = ExerciseLibraryViewModel(exerciseRepository: MockExerciseRepository())
        vm.selectFilter(category: "equipment", value: "barbell")

        vm.clearFilter()

        #expect(vm.selectedCategory == nil)
        #expect(vm.selectedValue == nil)
    }

    @Test("loadExercises with error sets errorMessage")
    func loadExercisesWithErrorSetsMessage() async {
        let repo = MockExerciseRepository()
        repo.errorToThrow = NSError(domain: "test", code: 1)
        let vm = ExerciseLibraryViewModel(exerciseRepository: repo)

        await vm.loadExercises()

        #expect(vm.errorMessage != nil)
    }
}
