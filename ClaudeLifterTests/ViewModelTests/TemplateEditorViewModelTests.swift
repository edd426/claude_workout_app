import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@Suite("TemplateEditorViewModel Tests")
@MainActor
struct TemplateEditorViewModelTests {

    @Test("init with nil creates new template with empty name")
    func initWithNilCreatesNew() {
        let repo = MockTemplateRepository()
        let vm = TemplateEditorViewModel(template: nil, templateRepository: repo)

        #expect(vm.name.isEmpty)
        #expect(vm.exercises.isEmpty)
        #expect(vm.isNew == true)
    }

    @Test("init with existing template loads its data")
    func initWithExistingLoadsData() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let template = TestFixtures.makeTemplate(name: "Push Day")
        context.insert(template)
        try context.save()

        let repo = MockTemplateRepository()
        let vm = TemplateEditorViewModel(template: template, templateRepository: repo)

        #expect(vm.name == "Push Day")
        #expect(vm.isNew == false)
    }

    @Test("save with empty name sets validationError")
    func saveWithEmptyNameSetsValidationError() async {
        let repo = MockTemplateRepository()
        let vm = TemplateEditorViewModel(template: nil, templateRepository: repo)
        vm.name = ""

        await vm.save()

        #expect(vm.validationError != nil)
        #expect(repo.saveCallCount == 0)
    }

    @Test("save with valid name calls repository")
    func saveWithValidNameCallsRepository() async {
        let repo = MockTemplateRepository()
        let vm = TemplateEditorViewModel(template: nil, templateRepository: repo)
        vm.name = "Leg Day"

        await vm.save()

        #expect(repo.saveCallCount == 1)
        #expect(vm.isSaved == true)
    }

    @Test("addExercise appends to exercises")
    func addExerciseAppendsToList() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)
        try context.save()

        let repo = MockTemplateRepository()
        let vm = TemplateEditorViewModel(template: nil, templateRepository: repo)

        vm.addExercise(exercise)

        #expect(vm.exercises.count == 1)
        #expect(vm.exercises.first?.exercise?.name == "Bench Press")
    }

    @Test("removeExercise removes from exercises")
    func removeExerciseRemovesFromList() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = TestFixtures.makeExercise(name: "Squat")
        context.insert(exercise)
        try context.save()

        let repo = MockTemplateRepository()
        let vm = TemplateEditorViewModel(template: nil, templateRepository: repo)
        vm.addExercise(exercise)

        vm.removeExercise(at: IndexSet(integer: 0))

        #expect(vm.exercises.isEmpty)
    }

    @Test("canSave is false when name is empty or whitespace")
    func canSaveIsFalseForEmptyName() {
        let repo = MockTemplateRepository()
        let vm = TemplateEditorViewModel(template: nil, templateRepository: repo)
        vm.name = ""
        #expect(vm.canSave == false)
        vm.name = "   "
        #expect(vm.canSave == false)
    }

    @Test("canSave is true when name has non-whitespace characters")
    func canSaveIsTrueForValidName() {
        let repo = MockTemplateRepository()
        let vm = TemplateEditorViewModel(template: nil, templateRepository: repo)
        vm.name = "Push Day"
        #expect(vm.canSave == true)
    }

    @Test("moveExercise reorders exercises")
    func moveExerciseReordersExercises() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exA = TestFixtures.makeExercise(name: "A")
        let exB = TestFixtures.makeExercise(name: "B")
        let exC = TestFixtures.makeExercise(name: "C")
        context.insert(exA)
        context.insert(exB)
        context.insert(exC)
        try context.save()

        let repo = MockTemplateRepository()
        let vm = TemplateEditorViewModel(template: nil, templateRepository: repo)
        vm.addExercise(exA)
        vm.addExercise(exB)
        vm.addExercise(exC)

        vm.moveExercise(from: IndexSet(integer: 0), to: 2)

        #expect(vm.exercises[0].exercise?.name == "B")
        #expect(vm.exercises[1].exercise?.name == "A")
    }

    // MARK: - Issue #21: existing-template exercise sync

    @Test("save on existing template syncs added exercises")
    func saveOnExistingTemplateSyncsAddedExercises() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let existingExercise = TestFixtures.makeExercise(name: "Squat")
        let newExercise = TestFixtures.makeExercise(name: "Leg Press")
        context.insert(existingExercise)
        context.insert(newExercise)

        let template = TestFixtures.makeTemplate(name: "Leg Day")
        context.insert(template)
        let te = TemplateExercise(order: 0, exercise: existingExercise, defaultSets: 3, defaultReps: 8)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let repo = MockTemplateRepository()
        let vm = TemplateEditorViewModel(template: template, templateRepository: repo)

        vm.addExercise(newExercise)
        await vm.save()

        #expect(repo.saveCallCount == 1)
        let saved = try #require(repo.savedTemplates.first)
        #expect(saved.exercises.count == 2)
    }

    @Test("save on existing template syncs removed exercises")
    func saveOnExistingTemplateSyncsRemovedExercises() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exA = TestFixtures.makeExercise(name: "Bench Press")
        let exB = TestFixtures.makeExercise(name: "Incline Press")
        context.insert(exA)
        context.insert(exB)

        let template = TestFixtures.makeTemplate(name: "Push Day")
        context.insert(template)
        let teA = TemplateExercise(order: 0, exercise: exA, defaultSets: 3, defaultReps: 8)
        let teB = TemplateExercise(order: 1, exercise: exB, defaultSets: 3, defaultReps: 10)
        context.insert(teA)
        context.insert(teB)
        template.exercises.append(teA)
        template.exercises.append(teB)
        try context.save()

        let repo = MockTemplateRepository()
        let vm = TemplateEditorViewModel(template: template, templateRepository: repo)

        vm.removeExercise(at: IndexSet(integer: 1))
        await vm.save()

        #expect(repo.saveCallCount == 1)
        let saved = try #require(repo.savedTemplates.first)
        #expect(saved.exercises.count == 1)
        #expect(saved.exercises.first?.exercise?.name == "Bench Press")
    }

    @Test("save on new template with multiple exercises persists all")
    func saveOnNewTemplateWithMultipleExercisesAll() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exA = TestFixtures.makeExercise(name: "Deadlift")
        let exB = TestFixtures.makeExercise(name: "Romanian Deadlift")
        let exC = TestFixtures.makeExercise(name: "Leg Curl")
        context.insert(exA)
        context.insert(exB)
        context.insert(exC)
        try context.save()

        let repo = MockTemplateRepository()
        let vm = TemplateEditorViewModel(template: nil, templateRepository: repo)
        vm.name = "Pull Day"

        vm.addExercise(exA)
        vm.addExercise(exB)
        vm.addExercise(exC)
        await vm.save()

        #expect(repo.saveCallCount == 1)
        let saved = try #require(repo.savedTemplates.first)
        #expect(saved.exercises.count == 3)
    }
}
