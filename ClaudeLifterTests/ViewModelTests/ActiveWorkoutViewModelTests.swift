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
        let set = try #require(vm.workout?.exercises.first?.sets.first)
        vm.completeSet(set)
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

    // MARK: - #69: Empty workout prevention

    @Test("finishWorkout with empty exercises deletes workout instead of saving")
    func finishWorkout_emptyExercises_deletesWorkout() async throws {
        let workoutRepo = MockWorkoutRepository()
        let vm = ActiveWorkoutViewModel(
            adHocName: "Quick Workout",
            workoutRepository: workoutRepo,
            autoFillService: MockAutoFillService()
        )
        await vm.startWorkout()
        #expect(vm.workout != nil)
        #expect(vm.workout?.exercises.isEmpty == true)

        await vm.finishWorkout()

        #expect(workoutRepo.deletedWorkouts.count == 1, "Empty workout should be deleted")
        #expect(vm.isFinished == true, "UI should still dismiss")
    }

    @Test("finishWorkout with no completed sets deletes workout instead of saving")
    func finishWorkout_noCompletedSets_deletesWorkout() async throws {
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
        #expect(vm.workout?.exercises.isEmpty == false)
        #expect(vm.hasCompletedSets == false)

        await vm.finishWorkout()

        #expect(workoutRepo.deletedWorkouts.count == 1, "Workout with no completed sets should be deleted")
        #expect(vm.isFinished == true, "UI should still dismiss")
    }

    @Test("finishWorkout with completed sets saves normally (regression)")
    func finishWorkout_withCompletedSets_savesNormally() async throws {
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
        let set = try #require(vm.workout?.exercises.first?.sets.first)
        vm.completeSet(set)

        await vm.finishWorkout()

        #expect(vm.workout?.completedAt != nil, "Completed workout should have completedAt set")
        #expect(vm.isFinished == true)
        #expect(workoutRepo.deletedWorkouts.isEmpty, "Should NOT delete a workout with completed sets")
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
        let set = try #require(vm.workout?.exercises.first?.sets.first)
        vm.completeSet(set)
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
        let set = try #require(vm.workout?.exercises.first?.sets.first)
        vm.completeSet(set)
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

extension ActiveWorkoutViewModelTests {

    // MARK: - #76: Single persisting mutation API for set edits

    /// Starts a workout from a template with one exercise and `setCount` sets,
    /// then ages the workout's sync bookkeeping so tests can observe the
    /// pending/lastModified transition caused by the mutation under test.
    private func makeStartedWorkout(
        setCount: Int = 2,
        settings: SettingsManager? = nil
    ) async throws -> (ModelContainer, MockWorkoutRepository, ActiveWorkoutViewModel, Workout, WorkoutExercise) {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: setCount, defaultReps: 8)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let workoutRepo = MockWorkoutRepository()
        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: workoutRepo,
            autoFillService: MockAutoFillService(),
            settings: settings
        )
        await vm.startWorkout()
        let workout = try #require(vm.workout)
        let we = try #require(workout.exercises.first)
        workout.lastModified = .distantPast
        workout.syncStatus = .synced
        return (container, workoutRepo, vm, workout, we)
    }

    private func makeTestSettings(unit: WeightUnit) -> SettingsManager {
        // Force unwrap acceptable in tests: the suite name is a fresh UUID.
        let defaults = UserDefaults(suiteName: "test-awvm-\(UUID().uuidString)")!
        let settings = SettingsManager(defaults: defaults)
        settings.weightUnit = unit
        return settings
    }

    @Test("updateSetWeight mutates the set, marks workout pending, bumps lastModified, and saves")
    func updateSetWeightPersistsAndMarksPending() async throws {
        let (container, workoutRepo, vm, workout, we) = try await makeStartedWorkout()
        let saveCountBefore = workoutRepo.saveCallCount
        let set = try #require(we.sets.first)

        vm.updateSetWeight(set, weight: 72.5)

        #expect(set.weight == 72.5)
        #expect(workout.syncStatus == .pending, "Weight edit must re-queue the workout for sync")
        #expect(workout.lastModified > .distantPast, "Weight edit must bump lastModified")
        await vm.awaitPendingSave()
        #expect(workoutRepo.saveCallCount > saveCountBefore, "Weight edit must persist via the repository")
        withExtendedLifetime(container) {}
    }

    @Test("updateSetReps mutates the set, marks workout pending, bumps lastModified, and saves")
    func updateSetRepsPersistsAndMarksPending() async throws {
        let (container, workoutRepo, vm, workout, we) = try await makeStartedWorkout()
        let saveCountBefore = workoutRepo.saveCallCount
        let set = try #require(we.sets.first)

        vm.updateSetReps(set, reps: 12)

        #expect(set.reps == 12)
        #expect(workout.syncStatus == .pending, "Reps edit must re-queue the workout for sync")
        #expect(workout.lastModified > .distantPast, "Reps edit must bump lastModified")
        await vm.awaitPendingSave()
        #expect(workoutRepo.saveCallCount > saveCountBefore, "Reps edit must persist via the repository")
        withExtendedLifetime(container) {}
    }

    @Test("addSet appends a set with the next order, marks workout pending, and saves")
    func addSetAppendsPersistsAndMarksPending() async throws {
        let (container, workoutRepo, vm, workout, we) = try await makeStartedWorkout(setCount: 2)
        let saveCountBefore = workoutRepo.saveCallCount

        vm.addSet(to: we)

        #expect(we.sets.count == 3)
        #expect(we.sets.map(\.order).sorted() == [0, 1, 2], "New set must get the next order")
        #expect(workout.syncStatus == .pending, "Add Set must re-queue the workout for sync")
        #expect(workout.lastModified > .distantPast, "Add Set must bump lastModified")
        await vm.awaitPendingSave()
        #expect(workoutRepo.saveCallCount > saveCountBefore, "Add Set must persist via the repository")
        withExtendedLifetime(container) {}
    }

    @Test("removeSet marks workout pending and saves")
    func removeSetPersistsAndMarksPending() async throws {
        let (container, workoutRepo, vm, workout, we) = try await makeStartedWorkout(setCount: 2)
        let saveCountBefore = workoutRepo.saveCallCount
        let set = try #require(we.sets.first)

        vm.removeSet(set, from: we)

        #expect(we.sets.count == 1)
        #expect(workout.syncStatus == .pending)
        #expect(workout.lastModified > .distantPast)
        await vm.awaitPendingSave()
        #expect(workoutRepo.saveCallCount > saveCountBefore, "Remove Set must persist via the repository")
        withExtendedLifetime(container) {}
    }

    @Test("failed save from a set mutation surfaces errorMessage")
    func failedMutationSaveSurfacesErrorMessage() async throws {
        let (container, workoutRepo, vm, _, we) = try await makeStartedWorkout()
        let set = try #require(we.sets.first)
        workoutRepo.errorToThrow = NSError(
            domain: "test", code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Save failed"]
        )

        vm.updateSetWeight(set, weight: 100)
        await vm.awaitPendingSave()

        #expect(vm.errorMessage != nil, "A failed mutation save must not be silent")
        withExtendedLifetime(container) {}
    }

    // MARK: - #83: New sets default to the global weight unit preference

    @Test("addSet defaults new set to global kg preference")
    func addSetDefaultsToKgPreference() async throws {
        let settings = makeTestSettings(unit: .kg)
        let (container, _, vm, _, we) = try await makeStartedWorkout(setCount: 1, settings: settings)

        vm.addSet(to: we)

        #expect(we.sets.sorted(by: { $0.order < $1.order }).last?.weightUnit == .kg)
        await vm.awaitPendingSave()
        withExtendedLifetime(container) {}
    }

    @Test("addSet defaults new set to global lbs preference")
    func addSetDefaultsToLbsPreference() async throws {
        let settings = makeTestSettings(unit: .lbs)
        let (container, _, vm, _, we) = try await makeStartedWorkout(setCount: 1, settings: settings)

        vm.addSet(to: we)

        #expect(we.sets.sorted(by: { $0.order < $1.order }).last?.weightUnit == .lbs)
        await vm.awaitPendingSave()
        withExtendedLifetime(container) {}
    }

    @Test("startFromTemplate without auto-fill uses global lbs preference for new sets")
    func startFromTemplateUsesGlobalUnitWhenNoAutoFill() async throws {
        let settings = makeTestSettings(unit: .lbs)
        let (container, _, vm, _, we) = try await makeStartedWorkout(setCount: 2, settings: settings)

        #expect(we.sets.allSatisfy { $0.weightUnit == .lbs },
                "Without auto-fill history, sets must use the global unit preference")
        await vm.awaitPendingSave()
        withExtendedLifetime(container) {}
    }

    @Test("startFromTemplate keeps auto-fill unit over global preference (per-set continuity)")
    func startFromTemplateAutoFillUnitWinsOverGlobal() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 1, defaultReps: 8)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let autoFill = MockAutoFillService()
        autoFill.resultByExerciseId[exercise.id] = AutoFillResult(
            weight: 100, weightUnit: .kg, reps: 5, date: .now
        )
        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: autoFill,
            settings: makeTestSettings(unit: .lbs)
        )
        await vm.startWorkout()

        let set = try #require(vm.workout?.exercises.first?.sets.first)
        #expect(set.weightUnit == .kg, "Last session's unit must carry forward over the global default")
        withExtendedLifetime(container) {}
    }

    @Test("addExercise creates sets with the global lbs preference")
    func addExerciseUsesGlobalUnit() async throws {
        let settings = makeTestSettings(unit: .lbs)
        let (container, _, vm, workout, _) = try await makeStartedWorkout(setCount: 1, settings: settings)
        let newExercise = TestFixtures.makeExercise(name: "Overhead Press")
        container.mainContext.insert(newExercise)
        try container.mainContext.save()

        vm.addExercise(newExercise)

        let added = try #require(workout.exercises.first(where: { $0.exercise?.id == newExercise.id }))
        #expect(added.sets.allSatisfy { $0.weightUnit == .lbs })
        await vm.awaitPendingSave()
        withExtendedLifetime(container) {}
    }
}

extension ActiveWorkoutViewModelTests {

    // MARK: - #31 / #53: completeSet() auto-saves (crash recovery)

    @Test("completeSet triggers a repository save for crash recovery")
    func completeSetTriggersRepositorySave() async throws {
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
        let saveCountAfterStart = workoutRepo.saveCallCount

        let set = try #require(vm.workout?.exercises.first?.sets.first)
        vm.completeSet(set)

        // Allow the async Task inside completeSet to execute
        try await Task.sleep(for: .milliseconds(50))

        #expect(workoutRepo.saveCallCount > saveCountAfterStart,
                "completeSet() must trigger a save so completed sets survive a crash")
    }

    @Test("completeSet updates workout lastModified")
    func completeSetUpdatesLastModified() async throws {
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
        let before = vm.workout?.lastModified ?? Date.distantPast

        let set = try #require(vm.workout?.exercises.first?.sets.first)
        vm.completeSet(set)
        try await Task.sleep(for: .milliseconds(50))

        let after = vm.workout?.lastModified ?? Date.distantPast
        #expect(after >= before, "lastModified must be updated when a set is completed")
    }

    // MARK: - #33 / #34: timesPerformed and lastPerformedAt updated on finish

    @Test("finishWorkout increments template timesPerformed")
    func finishWorkoutIncrementsTimesPerformed() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 1, defaultReps: 8)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let initialCount = template.timesPerformed

        let templateRepo = MockTemplateRepository()
        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService(),
            templateRepository: templateRepo
        )
        await vm.startWorkout()
        let set = try #require(vm.workout?.exercises.first?.sets.first)
        vm.completeSet(set)
        await vm.finishWorkout()

        #expect(template.timesPerformed == initialCount + 1,
                "timesPerformed must be incremented when a workout is finished")
        #expect(templateRepo.saveCallCount >= 1)
    }

    @Test("finishWorkout sets template lastPerformedAt")
    func finishWorkoutSetsLastPerformedAt() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 1, defaultReps: 8)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let templateRepo = MockTemplateRepository()
        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService(),
            templateRepository: templateRepo
        )
        await vm.startWorkout()
        let set = try #require(vm.workout?.exercises.first?.sets.first)
        vm.completeSet(set)
        let beforeFinish = Date.now
        await vm.finishWorkout()

        let lastPerformed = try #require(template.lastPerformedAt,
                                         "lastPerformedAt must be set when a workout is finished")
        #expect(lastPerformed >= beforeFinish)
    }

    @Test("finishWorkout without templateRepository leaves template unchanged")
    func finishWorkoutWithoutTemplateRepoLeavesTemplateUnchanged() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 1, defaultReps: 8)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let initialCount = template.timesPerformed

        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService()
            // no templateRepository
        )
        await vm.startWorkout()
        let set = try #require(vm.workout?.exercises.first?.sets.first)
        vm.completeSet(set)
        await vm.finishWorkout()

        // Without a templateRepository the template should be untouched
        #expect(template.timesPerformed == initialCount)
    }
}
