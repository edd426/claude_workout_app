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

    @Test("selectFilter adds to activeFilters dict")
    func selectFilterAddsToActiveFilters() {
        let repo = MockExerciseRepository()
        let vm = ExerciseLibraryViewModel(exerciseRepository: repo)

        vm.selectFilter(category: "equipment", value: "barbell")

        #expect(vm.activeFilters["equipment"] == "barbell")
    }

    @Test("selectFilter with same category replaces existing value")
    func selectFilterReplacesSameCategory() {
        let vm = ExerciseLibraryViewModel(exerciseRepository: MockExerciseRepository())
        vm.selectFilter(category: "equipment", value: "barbell")
        vm.selectFilter(category: "equipment", value: "dumbbell")

        #expect(vm.activeFilters["equipment"] == "dumbbell")
        #expect(vm.activeFilters.count == 1)
    }

    @Test("multiple filters can be active simultaneously")
    func multipleFiltersCanBeActive() {
        let vm = ExerciseLibraryViewModel(exerciseRepository: MockExerciseRepository())
        vm.selectFilter(category: "equipment", value: "barbell")
        vm.selectFilter(category: "level", value: "intermediate")

        #expect(vm.activeFilters.count == 2)
        #expect(vm.activeFilters["equipment"] == "barbell")
        #expect(vm.activeFilters["level"] == "intermediate")
    }

    @Test("removeFilter removes only that category")
    func removeFilterRemovesOnlyThatCategory() {
        let vm = ExerciseLibraryViewModel(exerciseRepository: MockExerciseRepository())
        vm.selectFilter(category: "equipment", value: "barbell")
        vm.selectFilter(category: "level", value: "intermediate")

        vm.removeFilter(category: "equipment")

        #expect(vm.activeFilters["equipment"] == nil)
        #expect(vm.activeFilters["level"] == "intermediate")
    }

    @Test("clearFilters empties activeFilters")
    func clearFiltersEmptiesAllFilters() {
        let vm = ExerciseLibraryViewModel(exerciseRepository: MockExerciseRepository())
        vm.selectFilter(category: "equipment", value: "barbell")
        vm.selectFilter(category: "level", value: "intermediate")

        vm.clearFilters()

        #expect(vm.activeFilters.isEmpty)
    }

    @Test("loadExercises with multiple filters applies AND logic")
    func loadExercisesWithMultipleFiltersAppliesAndLogic() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let barbellCompound = TestFixtures.makeExercise(name: "Bench Press", level: "intermediate", equipment: "barbell")
        let barbellTag = ExerciseTag(category: "equipment", value: "barbell")
        let levelTag = ExerciseTag(category: "level", value: "intermediate")
        context.insert(barbellTag)
        context.insert(levelTag)
        barbellCompound.tags.append(contentsOf: [barbellTag, levelTag])
        context.insert(barbellCompound)

        let dumbbellExercise = TestFixtures.makeExercise(name: "DB Curl", level: "beginner", equipment: "dumbbell")
        let dumbTag = ExerciseTag(category: "equipment", value: "dumbbell")
        let beginnerTag = ExerciseTag(category: "level", value: "beginner")
        context.insert(dumbTag)
        context.insert(beginnerTag)
        dumbbellExercise.tags.append(contentsOf: [dumbTag, beginnerTag])
        context.insert(dumbbellExercise)

        try context.save()

        let repo = MockExerciseRepository()
        repo.exercises = [barbellCompound, dumbbellExercise]
        let vm = ExerciseLibraryViewModel(exerciseRepository: repo)
        vm.selectFilter(category: "equipment", value: "barbell")
        vm.selectFilter(category: "level", value: "intermediate")

        await vm.loadExercises()

        #expect(vm.exercises.count == 1)
        #expect(vm.exercises.first?.name == "Bench Press")
    }

    @Test("loadExercises with no filters returns all exercises")
    func loadExercisesWithNoFiltersReturnsAll() async throws {
        let repo = MockExerciseRepository()
        repo.exercises = [
            TestFixtures.makeExercise(name: "Bench Press"),
            TestFixtures.makeExercise(name: "Squat")
        ]
        let vm = ExerciseLibraryViewModel(exerciseRepository: repo)

        await vm.loadExercises()

        #expect(vm.exercises.count == 2)
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
