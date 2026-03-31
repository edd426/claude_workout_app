import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@Suite("CreateExerciseViewModel Tests")
@MainActor
struct CreateExerciseViewModelTests {

    @Test("initial state has empty fields")
    func initialStateHasEmptyFields() {
        let vm = CreateExerciseViewModel()
        #expect(vm.name.isEmpty)
        #expect(vm.equipment.isEmpty)
        #expect(vm.primaryMuscles.isEmpty)
        #expect(vm.level.isEmpty)
        #expect(vm.mechanic.isEmpty)
        #expect(vm.force.isEmpty)
        #expect(vm.notes.isEmpty)
    }

    @Test("canSave is false when name is empty")
    func canSaveIsFalseWhenNameEmpty() {
        let vm = CreateExerciseViewModel()
        vm.name = ""
        #expect(vm.canSave == false)
    }

    @Test("canSave is false when name is only whitespace")
    func canSaveIsFalseWhenNameIsWhitespace() {
        let vm = CreateExerciseViewModel()
        vm.name = "   "
        #expect(vm.canSave == false)
    }

    @Test("canSave is true when name is non-empty")
    func canSaveIsTrueWhenNameNonEmpty() {
        let vm = CreateExerciseViewModel()
        vm.name = "Cable Fly"
        #expect(vm.canSave == true)
    }

    @Test("save creates exercise with isCustom true")
    func saveCreatesCustomExercise() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataExerciseRepository(context: context)
        let vm = CreateExerciseViewModel()
        vm.name = "Cable Fly"
        vm.equipment = "cable"

        try await vm.save(using: repo)

        let all = try await repo.fetchAll()
        #expect(all.count == 1)
        #expect(all.first?.isCustom == true)
        #expect(all.first?.name == "Cable Fly")
    }

    @Test("save creates tags for non-empty fields")
    func saveCreatesTagsForNonEmptyFields() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataExerciseRepository(context: context)
        let vm = CreateExerciseViewModel()
        vm.name = "Cable Fly"
        vm.equipment = "cable"
        vm.level = "intermediate"
        vm.mechanic = "isolation"
        vm.force = "push"

        try await vm.save(using: repo)

        let exercise = try await repo.fetchAll()
        let tags = exercise.first?.tags ?? []
        let categories = Set(tags.map(\.category))
        #expect(categories.contains("equipment"))
        #expect(categories.contains("level"))
        #expect(categories.contains("mechanic"))
        #expect(categories.contains("force"))
    }

    @Test("save creates primaryMuscle tags for each muscle")
    func saveCreatesPrimaryMuscleTags() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataExerciseRepository(context: context)
        let vm = CreateExerciseViewModel()
        vm.name = "Wide Grip Pull-Up"
        vm.primaryMuscles = ["back", "biceps"]

        try await vm.save(using: repo)

        let exercises = try await repo.fetchAll()
        let muscleTags = exercises.first?.tags.filter { $0.category == "muscle_group" } ?? []
        let muscles = Set(muscleTags.map(\.value))
        #expect(muscles.contains("back"))
        #expect(muscles.contains("biceps"))
    }

    @Test("save throws when name is empty")
    func saveThrowsWhenNameEmpty() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataExerciseRepository(context: context)
        let vm = CreateExerciseViewModel()
        vm.name = ""

        await #expect(throws: (any Error).self) {
            try await vm.save(using: repo)
        }
    }
}
