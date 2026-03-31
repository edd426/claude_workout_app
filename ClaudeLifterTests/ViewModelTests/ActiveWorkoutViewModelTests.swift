import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@Suite("ActiveWorkoutViewModel Tests")
@MainActor
struct ActiveWorkoutViewModelTests {

    func makeSetup() throws -> (ModelContainer, Exercise, WorkoutTemplate) {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)
        let template = TestFixtures.makeTemplate(name: "Push Day")
        context.insert(template)
        try context.save()
        return (container, exercise, template)
    }

    @Test("startFromTemplate creates workout with exercises")
    func startFromTemplateCreatesWorkout() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 3, defaultReps: 8, defaultWeight: 60)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let workoutRepo = MockWorkoutRepository()
        let autoFill = MockAutoFillService()
        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: workoutRepo,
            autoFillService: autoFill
        )
        await vm.startWorkout()

        #expect(vm.workout != nil)
        #expect(vm.workout?.name == "Push Day")
        #expect(vm.workout?.exercises.count == 1)
    }

    @Test("startFromTemplate auto-fills sets from last session")
    func startFromTemplateAutoFillsSets() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 3, defaultReps: 8, defaultWeight: 60)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let workoutRepo = MockWorkoutRepository()
        let autoFill = MockAutoFillService()
        autoFill.resultByExerciseId[exercise.id] = AutoFillResult(
            weight: 80.0, weightUnit: .kg, reps: 5, date: .now
        )

        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: workoutRepo,
            autoFillService: autoFill
        )
        await vm.startWorkout()

        let firstSet = vm.workout?.exercises.first?.sets.first
        #expect(firstSet?.weight == 80.0)
        #expect(firstSet?.reps == 5)
    }

    @Test("completeSet marks set completed and records timestamp")
    func completeSetMarksCompleted() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 1, defaultReps: 8)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService()
        )
        await vm.startWorkout()

        let set = try #require(vm.workout?.exercises.first?.sets.first)
        vm.completeSet(set)

        #expect(set.isCompleted == true)
        #expect(set.completedAt != nil)
    }

    @Test("finishWorkout sets completedAt and saves")
    func finishWorkoutSetsCompletedAt() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 1, defaultReps: 8)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let workoutRepo = MockWorkoutRepository()
        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: workoutRepo,
            autoFillService: MockAutoFillService()
        )
        await vm.startWorkout()
        await vm.finishWorkout()

        #expect(vm.workout?.completedAt != nil)
        #expect(vm.isFinished == true)
        #expect(workoutRepo.saveCallCount >= 1)
    }

    @Test("totalSetsCompleted counts completed sets across exercises")
    func totalSetsCompletedCount() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 3, defaultReps: 8)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService()
        )
        await vm.startWorkout()

        let sets = vm.workout?.exercises.first?.sets ?? []
        vm.completeSet(sets[0])
        vm.completeSet(sets[1])

        #expect(vm.totalSetsCompleted == 2)
    }

    @Test("addExercise adds to active workout exercises")
    func addExerciseAddsToWorkout() async throws {
        let (container, _, template) = try makeSetup()
        let context = container.mainContext
        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService()
        )
        await vm.startWorkout()
        let initialCount = vm.workout?.exercises.count ?? 0

        let newExercise = TestFixtures.makeExercise(name: "Overhead Press")
        context.insert(newExercise)
        try context.save()
        vm.addExercise(newExercise)

        #expect((vm.workout?.exercises.count ?? 0) == initialCount + 1)
    }

    @Test("removeExercise removes from workout session only")
    func removeExerciseFromSession() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 2, defaultReps: 8)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService()
        )
        await vm.startWorkout()
        #expect(vm.workout?.exercises.count == 1)
        #expect(template.exercises.count == 1)

        let we = vm.workout!.exercises.first!
        vm.removeExercise(we)

        #expect(vm.workout?.exercises.count == 0)
        #expect(template.exercises.count == 1)
    }

    @Test("ad-hoc workout starts with no exercises")
    func adHocWorkoutStartsWithNoExercises() async throws {
        let workoutRepo = MockWorkoutRepository()
        let vm = ActiveWorkoutViewModel(
            adHocName: "Quick Workout",
            workoutRepository: workoutRepo,
            autoFillService: MockAutoFillService()
        )
        await vm.startWorkout()

        #expect(vm.workout != nil)
        #expect(vm.workout?.exercises.isEmpty == true)
    }

    @Test("ad-hoc workout has the provided custom name")
    func adHocWorkoutHasCustomName() async throws {
        let vm = ActiveWorkoutViewModel(
            adHocName: "Quick Workout",
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService()
        )
        await vm.startWorkout()

        #expect(vm.workout?.name == "Quick Workout")
    }

    @Test("ad-hoc workout has no templateId")
    func adHocWorkoutHasNoTemplateId() async throws {
        let vm = ActiveWorkoutViewModel(
            adHocName: "Quick Workout",
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService()
        )
        await vm.startWorkout()

        #expect(vm.workout?.templateId == nil)
    }
}
