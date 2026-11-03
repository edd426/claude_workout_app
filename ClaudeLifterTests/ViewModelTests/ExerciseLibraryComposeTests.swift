import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

/// Search and filter chips combine with AND; changing one never clears the
/// other (#155, UI-P10).
@Suite("Exercise library search and filters compose (#155)")
@MainActor
struct ExerciseLibraryComposeTests {

    /// Keeps the container alive for the tags' lifetime.
    struct Library {
        let container: ModelContainer
        let repository: MockExerciseRepository
        let viewModel: ExerciseLibraryViewModel
    }

    private func makeLibrary() throws -> Library {
        let container = try makeTestContainer()
        let context = container.mainContext
        func exercise(_ name: String, equipment: String) -> Exercise {
            let exercise = TestFixtures.makeExercise(name: name, equipment: equipment)
            let tag = ExerciseTag(category: "equipment", value: equipment)
            context.insert(tag)
            exercise.tags.append(tag)
            context.insert(exercise)
            return exercise
        }
        let repository = MockExerciseRepository()
        repository.exercises = [
            exercise("Machine Bicep Curl", equipment: "machine"),
            exercise("Dumbbell Bicep Curl", equipment: "dumbbell"),
            exercise("Leg Press", equipment: "machine"),
            exercise("Seated Cable Rows", equipment: "cable"),
            exercise("Upright Row", equipment: "barbell"),
            exercise("Backward Medicine Ball Throw", equipment: "medicine ball"),
            exercise("Pull-Up", equipment: "body only"),
        ]
        try context.save()
        return Library(
            container: container,
            repository: repository,
            viewModel: ExerciseLibraryViewModel(exerciseRepository: repository)
        )
    }

    private func names(_ vm: ExerciseLibraryViewModel) -> Set<String> {
        Set(vm.exercises.map(\.name))
    }

    @Test("A query typed after a filter keeps the filter")
    func queryAfterFilter() async throws {
        let library = try makeLibrary()
        let vm = library.viewModel
        vm.selectFilter(category: "equipment", value: "machine")
        await vm.loadExercises()

        vm.searchQuery = "curl"
        await vm.performSearch()

        #expect(names(vm) == ["Machine Bicep Curl"])
        #expect(vm.activeFilters["equipment"] == "machine")
    }

    @Test("A filter picked after a query keeps the query")
    func filterAfterQuery() async throws {
        let library = try makeLibrary()
        let vm = library.viewModel
        vm.searchQuery = "curl"
        await vm.performSearch()
        #expect(names(vm) == ["Machine Bicep Curl", "Dumbbell Bicep Curl"])

        vm.selectFilter(category: "equipment", value: "dumbbell")
        await vm.loadExercises()

        #expect(names(vm) == ["Dumbbell Bicep Curl"])
        #expect(vm.searchQuery == "curl")
    }

    @Test("Removing the filter keeps the query")
    func removingFilterKeepsQuery() async throws {
        let library = try makeLibrary()
        let vm = library.viewModel
        vm.searchQuery = "curl"
        vm.selectFilter(category: "equipment", value: "machine")
        await vm.loadExercises()

        vm.removeFilter(category: "equipment")
        await vm.loadExercises()

        #expect(names(vm) == ["Machine Bicep Curl", "Dumbbell Bicep Curl"])
    }

    @Test("Clearing the query keeps the filter")
    func clearingQueryKeepsFilter() async throws {
        let library = try makeLibrary()
        let vm = library.viewModel
        vm.searchQuery = "curl"
        vm.selectFilter(category: "equipment", value: "machine")
        await vm.loadExercises()

        vm.searchQuery = ""
        await vm.performSearch()

        #expect(names(vm) == ["Machine Bicep Curl", "Leg Press"])
    }

    @Test("Search matches the start of a word, not any substring")
    func wordPrefixSearch() async throws {
        let library = try makeLibrary()
        let vm = library.viewModel

        vm.searchQuery = "row"
        await vm.performSearch()

        #expect(names(vm) == ["Seated Cable Rows", "Upright Row"])
    }

    @Test("A query with no match reports what was searched")
    func emptyResultDescribesCriteria() async throws {
        let library = try makeLibrary()
        let vm = library.viewModel
        vm.searchQuery = "row"
        vm.selectFilter(category: "equipment", value: "machine")
        await vm.loadExercises()

        #expect(vm.exercises.isEmpty)
        #expect(vm.criteriaDescription == "“row” · Equipment: Machine")
    }

    @Test("Search words may run together across a hyphen", arguments: ["pullup", "pull up", "pull-up", "PULL"])
    func joinedWords(query: String) {
        #expect(ExerciseSearch.matches(name: "Pull-Up", query: query))
    }

    @Test("Every query word must match", arguments: [
        ("bicep curl", "Machine Bicep Curl", true),
        ("curl machine", "Machine Bicep Curl", true),
        ("curl leg", "Machine Bicep Curl", false),
        ("row", "Backward Medicine Ball Throw", false),
        ("", "Leg Press", true),
    ])
    func allWordsMatch(query: String, name: String, expected: Bool) {
        #expect(ExerciseSearch.matches(name: name, query: query) == expected)
    }
}
