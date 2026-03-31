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

    @Test("cancelWorkout deletes workout from repository")
    func cancelWorkoutDeletesFromRepository() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 2, defaultReps: 8)
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
        #expect(vm.workout != nil)

        await vm.cancelWorkout()

        #expect(workoutRepo.deletedWorkouts.count == 1)
        #expect(vm.workout == nil)
    }

    @Test("saveDraft saves workout without completedAt")
    func saveDraftSavesWithoutCompletedAt() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 2, defaultReps: 8)
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
        await vm.saveDraft()

        #expect(workoutRepo.saveCallCount >= 1)
        #expect(vm.workout?.completedAt == nil)
    }

    @Test("removeSet removes the specified set from the workout exercise")
    func removeSetRemovesFromExercise() async throws {
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
        let we = try #require(vm.workout?.exercises.first)
        #expect(we.sets.count == 3)

        let setToRemove = try #require(we.sets.first)
        vm.removeSet(setToRemove, from: we)

        #expect(we.sets.count == 2)
    }

    @Test("hasCompletedSets is false when no sets are completed")
    func hasCompletedSetsIsFalseWhenNoneCompleted() async throws {
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

        #expect(vm.hasCompletedSets == false)
    }

    @Test("hasCompletedSets is true after completing one set")
    func hasCompletedSetsIsTrueAfterCompletion() async throws {
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
        let set = try #require(vm.workout?.exercises.first?.sets.first)
        vm.completeSet(set)

        #expect(vm.hasCompletedSets == true)
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

extension ActiveWorkoutViewModelTests {

    // MARK: - PR Detection Tests

    @Test("finishWorkout detects PRs and stores them")
    func finishWorkoutDetectsPRs() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 1, defaultReps: 8)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let prService = MockPRDetectionService()
        let fakePR = PersonalRecord(
            exerciseId: exercise.id,
            type: .heaviestWeight,
            value: 100,
            weight: 100,
            achievedAt: .now,
            workoutId: UUID()
        )
        prService.detectedPRs = [fakePR]

        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService(),
            prDetectionService: prService
        )
        await vm.startWorkout()
        await vm.finishWorkout()

        #expect(vm.detectedPRs.count == 1)
        #expect(prService.detectCallCount == 1)
    }

    @Test("detected PRs stored in observable property after finish")
    func detectedPRsStoredInObservableProperty() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 1, defaultReps: 8)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let prService = MockPRDetectionService()
        let pr1 = PersonalRecord(exerciseId: exercise.id, type: .heaviestWeight, value: 80, weight: 80, achievedAt: .now, workoutId: UUID())
        let pr2 = PersonalRecord(exerciseId: exercise.id, type: .highest1RM, value: 90, achievedAt: .now, workoutId: UUID())
        prService.detectedPRs = [pr1, pr2]

        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService(),
            prDetectionService: prService
        )
        await vm.startWorkout()
        await vm.finishWorkout()

        #expect(vm.detectedPRs.count == 2)
    }

    @Test("no PRs detected for empty workout")
    func noPRsForEmptyWorkout() async throws {
        let prService = MockPRDetectionService()
        prService.detectedPRs = []

        let vm = ActiveWorkoutViewModel(
            adHocName: "Empty",
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService(),
            prDetectionService: prService
        )
        await vm.startWorkout()
        await vm.finishWorkout()

        #expect(vm.detectedPRs.isEmpty)
    }
}
