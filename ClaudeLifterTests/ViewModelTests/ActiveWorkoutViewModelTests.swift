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

        let firstSet = try #require(vm.workout?.exercises.first?.sets.first)
        #expect(firstSet.weight == 80.0)
        #expect(firstSet.reps == 5)
        #expect(vm.previous(for: firstSet)?.weight == 80.0)
        #expect(vm.previous(for: firstSet)?.reps == 5)
    }

    @Test("startFromTemplate leaves weight empty without history or a template weight")
    func startFromTemplateLeavesWeightEmptyWithoutSourceValue() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let templateExercise = TemplateExercise(
            order: 0,
            exercise: exercise,
            defaultSets: 1,
            defaultReps: 8
        )
        context.insert(templateExercise)
        template.exercises.append(templateExercise)
        try context.save()

        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService()
        )
        await vm.startWorkout()

        let set = try #require(vm.workout?.exercises.first?.sets.first)
        #expect(set.weight == nil)
        #expect(set.reps == 8)
        #expect(vm.previous(for: set) == nil)
        withExtendedLifetime(container) {}
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

    @Test("removeSet renumbers surviving sets without gaps")
    func removeSetRenumbersSurvivors() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(
            order: 0,
            exercise: exercise,
            defaultSets: 3,
            defaultReps: 8
        )
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService()
        )
        await vm.startWorkout()
        let workoutExercise = try #require(vm.workout?.exercises.first)
        let middleSet = try #require(
            workoutExercise.sets.first(where: { $0.order == 1 })
        )

        vm.removeSet(middleSet, from: workoutExercise)

        #expect(workoutExercise.sets.map(\.order).sorted() == [0, 1])
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

    // MARK: - #124: Finish is idempotent
    //
    // The user-visible bug (#123) is that a swipe-dismissed summary leaves the
    // workout onscreen. What makes that state *corrupting* rather than merely
    // annoying is this: every further Finish tap re-entered finishWorkout(),
    // which found the workout still non-nil and re-ran the whole path.

    /// A started workout with one completed set, ready to finish.
    ///
    /// Holds the `ModelContainer` as well as the objects under test. Dropping it
    /// deallocates the container, and on iOS 26.5 the next touch of a model
    /// object then traps with "This model instance was destroyed by calling
    /// ModelContext.reset" — a crash, not a test failure, so it presents as an
    /// unrelated mess rather than a lifetime bug.
    private struct FinishableWorkout {
        let container: ModelContainer
        let vm: ActiveWorkoutViewModel
        let template: WorkoutTemplate
    }

    /// Builds a started workout with exactly one completed set, ready to finish.
    private func makeFinishableWorkout(
        workoutRepository: MockWorkoutRepository = MockWorkoutRepository(),
        templateRepository: MockTemplateRepository? = nil,
        prDetectionService: MockPRDetectionService? = nil
    ) async throws -> FinishableWorkout {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 1, defaultReps: 8)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: workoutRepository,
            autoFillService: MockAutoFillService(),
            templateRepository: templateRepository,
            prDetectionService: prDetectionService
        )
        await vm.startWorkout()
        let set = try #require(vm.workout?.exercises.first?.sets.first)
        vm.completeSet(set)
        await vm.awaitPendingSave()
        return FinishableWorkout(container: container, vm: vm, template: template)
    }

    @Test("a second Finish tap does not save the workout again")
    func repeatedFinishSavesOnce() async throws {
        let repo = MockWorkoutRepository()
        let fixture = try await makeFinishableWorkout(workoutRepository: repo)
        let vm = fixture.vm

        await vm.finishWorkout()
        let savesAfterFirstFinish = repo.saveCallCount

        await vm.finishWorkout()
        await vm.finishWorkout()

        #expect(
            repo.saveCallCount == savesAfterFirstFinish,
            "Finishing an already-finished workout must not save it again"
        )
    }

    @Test("a second Finish tap does not re-stamp completedAt")
    func repeatedFinishKeepsOriginalCompletedAt() async throws {
        let fixture = try await makeFinishableWorkout()
        let vm = fixture.vm

        await vm.finishWorkout()
        let firstCompletedAt = try #require(vm.workout?.completedAt)

        // A real user tapping again is separated from the first tap in time;
        // without a guard the second tap silently moves the recorded finish
        // time to "whenever they last jabbed the button".
        try await Task.sleep(for: .milliseconds(20))
        await vm.finishWorkout()

        #expect(
            vm.workout?.completedAt == firstCompletedAt,
            "completedAt is the moment the workout ended, not the moment of the last tap"
        )
    }

    @Test("a second Finish tap does not re-run PR detection")
    func repeatedFinishDetectsPRsOnce() async throws {
        let prService = MockPRDetectionService()
        let fixture = try await makeFinishableWorkout(prDetectionService: prService)
        let vm = fixture.vm

        await vm.finishWorkout()
        await vm.awaitPostCommitWork()
        await vm.finishWorkout()
        await vm.awaitPostCommitWork()

        #expect(
            prService.detectCallCount == 1,
            "Re-running detection on the same workout can announce duplicate PRs"
        )
    }

    @Test("a second Finish tap does not inflate template timesPerformed")
    func repeatedFinishCountsTemplateUseOnce() async throws {
        let templateRepo = MockTemplateRepository()
        let fixture = try await makeFinishableWorkout(
            templateRepository: templateRepo
        )
        let vm = fixture.vm
        let template = fixture.template
        let before = template.timesPerformed

        await vm.finishWorkout()
        await vm.awaitPostCommitWork()
        await vm.finishWorkout()
        await vm.awaitPostCommitWork()

        #expect(template.timesPerformed == before + 1)
    }

    // MARK: - #125: post-commit work cannot trap a saved workout

    @Test("a failing PR service still leaves the workout finished")
    func failingPRDetectionStillFinishes() async throws {
        let prService = MockPRDetectionService()
        prService.errorToThrow = NSError(domain: "PR", code: 1)
        let repo = MockWorkoutRepository()
        let fixture = try await makeFinishableWorkout(
            workoutRepository: repo,
            prDetectionService: prService
        )
        let vm = fixture.vm

        await vm.finishWorkout()
        await vm.awaitPostCommitWork()

        #expect(vm.isFinished, "PR detection is post-commit — it cannot reopen the workout")
        #expect(vm.workout?.completedAt != nil)
        #expect(repo.deletedWorkouts.isEmpty)
    }

    @Test("a failing template save still leaves the workout finished")
    func failingTemplateSaveStillFinishes() async throws {
        let templateRepo = MockTemplateRepository()
        templateRepo.errorToThrow = NSError(domain: "Template", code: 1)
        let fixture = try await makeFinishableWorkout(
            templateRepository: templateRepo
        )
        let vm = fixture.vm

        await vm.finishWorkout()
        await vm.awaitPostCommitWork()

        #expect(vm.isFinished, "Template bookkeeping is post-commit — it cannot reopen the workout")
        #expect(vm.workout?.completedAt != nil)
    }

    @Test("post-commit failures are reported rather than swallowed")
    func postCommitFailuresAreSurfaced() async throws {
        let prService = MockPRDetectionService()
        prService.errorToThrow = NSError(domain: "PR", code: 1)
        let fixture = try await makeFinishableWorkout(prDetectionService: prService)
        let vm = fixture.vm

        await vm.finishWorkout()
        await vm.awaitPostCommitWork()

        // The old code used `try?` here, so a broken PR service was invisible.
        #expect(!vm.postCommitWarnings.isEmpty)
    }

    // MARK: - #123 / #125: a failed critical save is recoverable

    @Test("a failed critical save keeps the workout intact and retryable")
    func failedCriticalSaveIsRetryable() async throws {
        let repo = MockWorkoutRepository()
        let fixture = try await makeFinishableWorkout(workoutRepository: repo)
        let vm = fixture.vm

        repo.errorToThrow = NSError(domain: "Save", code: 1)
        await vm.finishWorkout()

        #expect(!vm.isFinished, "A workout that failed to save must not be reported as finished")
        #expect(vm.workout != nil, "The user's logged sets must survive a failed save")
        #expect(vm.errorMessage != nil)

        // Retry succeeds once the underlying failure clears.
        repo.errorToThrow = nil
        await vm.finishWorkout()

        #expect(vm.isFinished)
        #expect(vm.workout?.completedAt != nil)
    }

    // MARK: - #69 regression: a discarded session has no summary to show

    @Test("a discarded empty workout finishes without a summary payload")
    func discardedWorkoutHasNoSummary() async throws {
        let vm = ActiveWorkoutViewModel(
            adHocName: "Quick Workout",
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService()
        )
        await vm.startWorkout()

        await vm.finishWorkout()

        // Previously this set a one-way flag that presented a summary sheet
        // built from a now-nil workout — an empty sheet with no Done button,
        // and therefore no way back out.
        #expect(vm.isFinished, "The UI must still leave the workout")
        #expect(vm.completionSummary == nil, "There is nothing to show a receipt for")
    }

    // MARK: - #121: a debounced draft save must not outlive completion

    @Test("an in-flight draft save cannot overwrite the finished workout")
    func pendingDraftSaveCannotClobberCompletion() async throws {
        let repo = MockWorkoutRepository()
        let fixture = try await makeFinishableWorkout(workoutRepository: repo)
        let vm = fixture.vm
        let set = try #require(vm.workout?.exercises.first?.sets.first)

        // Edit and immediately finish, without awaiting the debounced save —
        // exactly what "type 45, tap Finish" does.
        vm.updateSetReps(set, reps: 12)
        await vm.finishWorkout()
        await vm.awaitPendingSave()

        #expect(vm.isFinished)
        #expect(vm.workout?.completedAt != nil, "A late draft save must not clear completion")
        #expect(set.reps == 12, "The last edit must survive into the saved workout")
    }
}

extension ActiveWorkoutViewModelTests {

    // MARK: - PR Detection Tests

    @Test("dependency-wired PR detection surfaces a record only when history is beaten")
    func dependencyWiredPRDetectionSurfacesOnlyNewRecords() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let dependencies = DependencyContainer(modelContext: context)
        let prService = dependencies.prDetectionService
        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)

        func makeWorkout(weight: Double) -> Workout {
            let workout = Workout(name: "Push Day", startedAt: .now)
            let workoutExercise = WorkoutExercise(order: 0, exercise: exercise)
            workoutExercise.sets.append(
                WorkoutSet(
                    order: 0,
                    weight: weight,
                    weightUnit: .kg,
                    reps: 5,
                    isCompleted: true,
                    completedAt: .now
                )
            )
            workout.exercises.append(workoutExercise)
            return workout
        }

        let historicalWorkout = makeWorkout(weight: 60)
        _ = try await prService.detectPRs(for: historicalWorkout)

        let recordWorkout = makeWorkout(weight: 65)
        let recordViewModel = ActiveWorkoutViewModel(
            resuming: recordWorkout,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService(),
            prDetectionService: prService
        )
        await recordViewModel.finishWorkout()

        #expect(
            recordViewModel.detectedPRs.contains {
                $0.prType == .heaviestWeight && $0.value == 65
            }
        )

        let matchingWorkout = makeWorkout(weight: 65)
        let matchingViewModel = ActiveWorkoutViewModel(
            resuming: matchingWorkout,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService(),
            prDetectionService: prService
        )
        await matchingViewModel.finishWorkout()

        #expect(matchingViewModel.detectedPRs.isEmpty)
    }

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

    @Test("startFromTemplate keeps auto-fill unit over global preference")
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
        #expect(set.weight == 100)
        #expect(
            set.weightUnit == .kg,
            "Last session's unit must carry forward over the global default"
        )
        #expect(vm.previous(for: set)?.weightUnit == .kg)
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

extension ActiveWorkoutViewModelTests {

    // MARK: - Active-workout set entry usability

    @Test("ordered set-entry fields follow exercise order, set order, then weight and reps")
    func orderedSetEntryFieldsFollowWorkoutOrder() {
        let firstExercise = TestFixtures.makeExercise(name: "First")
        let secondExercise = TestFixtures.makeExercise(name: "Second")
        let workout = Workout(name: "Ordered", startedAt: .now)
        let laterWorkoutExercise = WorkoutExercise(
            order: 1,
            exercise: secondExercise
        )
        let earlierWorkoutExercise = WorkoutExercise(
            order: 0,
            exercise: firstExercise
        )
        let secondSet = WorkoutSet(order: 1)
        let firstSet = WorkoutSet(order: 0)
        earlierWorkoutExercise.sets = [secondSet, firstSet]
        let onlyLaterSet = WorkoutSet(order: 0)
        laterWorkoutExercise.sets = [onlyLaterSet]
        workout.exercises = [laterWorkoutExercise, earlierWorkoutExercise]

        let fields = orderedSetEntryFields(in: workout)

        #expect(fields == [
            SetEntryFieldID(
                exerciseID: earlierWorkoutExercise.id,
                setID: firstSet.id,
                kind: .weight
            ),
            SetEntryFieldID(
                exerciseID: earlierWorkoutExercise.id,
                setID: firstSet.id,
                kind: .reps
            ),
            SetEntryFieldID(
                exerciseID: earlierWorkoutExercise.id,
                setID: secondSet.id,
                kind: .weight
            ),
            SetEntryFieldID(
                exerciseID: earlierWorkoutExercise.id,
                setID: secondSet.id,
                kind: .reps
            ),
            SetEntryFieldID(
                exerciseID: laterWorkoutExercise.id,
                setID: onlyLaterSet.id,
                kind: .weight
            ),
            SetEntryFieldID(
                exerciseID: laterWorkoutExercise.id,
                setID: onlyLaterSet.id,
                kind: .reps
            ),
        ])
    }

    @Test("select-all scope accepts only UUID-addressed set-entry fields")
    func selectAllScopeAcceptsOnlySetEntryFields() {
        let exerciseID = UUID()
        let setID = UUID()

        #expect(isSetEntryFieldAccessibilityIdentifier(
            "weight_\(exerciseID.uuidString)_\(setID.uuidString)"
        ))
        #expect(isSetEntryFieldAccessibilityIdentifier(
            "reps_\(exerciseID.uuidString)_\(setID.uuidString)"
        ))
        #expect(!isSetEntryFieldAccessibilityIdentifier("exerciseSearch"))
        #expect(!isSetEntryFieldAccessibilityIdentifier("weight_not-a-set"))
        #expect(!isSetEntryFieldAccessibilityIdentifier(nil))
    }

    @Test("resuming a workout populates previous-value ghosts")
    func resumePopulatesPreviousValues() async throws {
        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        let workout = Workout(name: "Draft", startedAt: .now)
        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise)
        let set = WorkoutSet(order: 0)
        workoutExercise.sets = [set]
        workout.exercises = [workoutExercise]
        let autoFill = MockAutoFillService()
        autoFill.resultByExerciseId[exercise.id] = AutoFillResult(
            weight: 82.5,
            weightUnit: .kg,
            reps: 6,
            date: .now
        )
        let vm = ActiveWorkoutViewModel(
            resuming: workout,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: autoFill
        )

        await vm.startWorkout()

        #expect(vm.previous(for: set)?.weight == 82.5)
        #expect(vm.previous(for: set)?.reps == 6)
        #expect(autoFill.excludedWorkoutIds.last == workout.id)
    }

    @Test("adding a set populates its previous-value ghost")
    func addSetPopulatesPreviousValue() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let templateExercise = TemplateExercise(
            order: 0,
            exercise: exercise,
            defaultSets: 1,
            defaultReps: 8
        )
        context.insert(templateExercise)
        template.exercises.append(templateExercise)
        try context.save()
        let autoFill = MockAutoFillService()
        autoFill.resultByExerciseId[exercise.id] = AutoFillResult(
            weight: 70,
            weightUnit: .kg,
            reps: 10,
            date: .now
        )
        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: autoFill
        )
        await vm.startWorkout()
        let workoutExercise = try #require(vm.workout?.exercises.first)

        vm.addSet(to: workoutExercise)
        await vm.awaitPreviousValuesLoad()

        let addedSet = try #require(
            workoutExercise.sets.max(by: { $0.order < $1.order })
        )
        #expect(addedSet.weight == 70)
        #expect(addedSet.reps == 10)
        #expect(addedSet.weightUnit == .kg)
        #expect(vm.previous(for: addedSet)?.weight == 70)
        #expect(vm.previous(for: addedSet)?.reps == 10)
        await vm.awaitPendingSave()
        withExtendedLifetime(container) {}
    }

    @Test("adding an exercise populates previous-value ghosts for its sets")
    func addExercisePopulatesPreviousValues() async throws {
        let workoutRepository = MockWorkoutRepository()
        let autoFill = MockAutoFillService()
        let exercise = TestFixtures.makeExercise(name: "Deadlift")
        autoFill.resultByExerciseId[exercise.id] = AutoFillResult(
            weight: 120,
            weightUnit: .kg,
            reps: 5,
            date: .now
        )
        let vm = ActiveWorkoutViewModel(
            adHocName: "Quick Workout",
            workoutRepository: workoutRepository,
            autoFillService: autoFill
        )
        await vm.startWorkout()

        vm.addExercise(exercise)
        await vm.awaitPreviousValuesLoad()

        let addedSets = try #require(
            vm.workout?.exercises.first(where: { $0.exercise?.id == exercise.id })?.sets
        )
        #expect(addedSets.count == 3)
        #expect(addedSets.allSatisfy { vm.previous(for: $0)?.weight == 120 })
        #expect(addedSets.allSatisfy { vm.previous(for: $0)?.reps == 5 })
    }

    @Test("completing a set preserves values the user intentionally cleared")
    func completeSetPreservesIntentionallyClearedValues() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let templateExercise = TemplateExercise(
            order: 0,
            exercise: exercise,
            defaultSets: 1,
            defaultReps: 8
        )
        context.insert(templateExercise)
        template.exercises.append(templateExercise)
        try context.save()
        let autoFill = MockAutoFillService()
        autoFill.resultByExerciseId[exercise.id] = AutoFillResult(
            weight: 80,
            weightUnit: .kg,
            reps: 5,
            date: .now
        )
        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: autoFill
        )
        await vm.startWorkout()
        let set = try #require(vm.workout?.exercises.first?.sets.first)
        #expect(set.weight == 80)
        #expect(set.reps == 5)
        #expect(vm.previous(for: set)?.weight == 80)

        vm.updateSetWeight(set, weight: nil)
        vm.updateSetReps(set, reps: nil)
        vm.completeSet(set)

        #expect(set.weight == nil)
        #expect(set.reps == nil)
        #expect(set.isCompleted)
        await vm.awaitPendingSave()
        withExtendedLifetime(container) {}
    }

    @Test("tapping a completed set again un-completes it without requesting rest")
    func secondCompletionTapUncompletesWithoutRest() async throws {
        let (container, _, vm, _, workoutExercise) = try await makeStartedWorkout(
            setCount: 1
        )
        let set = try #require(workoutExercise.sets.first)

        let firstTapStartsRest = vm.completeSet(set)
        let secondTapStartsRest = vm.completeSet(set)

        #expect(firstTapStartsRest)
        #expect(secondTapStartsRest == false)
        #expect(set.isCompleted == false)
        #expect(set.completedAt == nil)
        await vm.awaitPendingSave()
        withExtendedLifetime(container) {}
    }

    // MARK: - Per-exercise notes (#136)
    //
    // The machine settings ("Ankle 4; Seat 4; Pivot 1") live on
    // TemplateExercise.notes and were never copied into the session, so they
    // vanished exactly where they are needed — standing at the machine.

    @Test("startFromTemplate copies per-exercise notes into the session")
    func startFromTemplateCopiesNotes() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(
            order: 0,
            exercise: exercise,
            defaultSets: 1,
            defaultReps: 8,
            defaultWeight: 60,
            notes: "Ankle 4; Seat 4; Pivot 1"
        )
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
        #expect(we.notes == "Ankle 4; Seat 4; Pivot 1")
        await vm.awaitPendingSave()
        withExtendedLifetime(container) {}
    }

    @Test("startFromTemplate leaves notes nil when the template has none")
    func startFromTemplateLeavesNotesNilWhenAbsent() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 1, defaultReps: 8, defaultWeight: 60)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService()
        )
        await vm.startWorkout()

        #expect(vm.workout?.exercises.first?.notes == nil)
        await vm.awaitPendingSave()
        withExtendedLifetime(container) {}
    }

    @Test("updateExerciseNotes writes the note onto the exercise, not the session")
    func updateExerciseNotesWritesToExercise() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 1, defaultReps: 8, defaultWeight: 60)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let exerciseRepo = MockExerciseRepository()
        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService(),
            exerciseRepository: exerciseRepo
        )
        await vm.startWorkout()
        let we = try #require(vm.workout?.exercises.first)

        await vm.updateExerciseNotes(we, notes: "Ankle 4; Seat 4; Pivot 1")

        // The note belongs to the machine, so it lands on the library
        // exercise and every future workout using it inherits it.
        #expect(exercise.notes == "Ankle 4; Seat 4; Pivot 1")
        #expect(exerciseRepo.savedExercises.contains { $0.id == exercise.id })
        // Bundled exercises never sync, so the session copy is the one that
        // reaches the server and the Coach.
        #expect(we.notes == "Ankle 4; Seat 4; Pivot 1")
        #expect(vm.workout?.syncStatus == .pending)
        await vm.awaitPendingSave()
        withExtendedLifetime(container) {}
    }

    @Test("updateExerciseNotes stores an emptied note as nil, not as empty text")
    func updateExerciseNotesClearsToNil() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        exercise.notes = "Ankle 4"
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 1, defaultReps: 8, defaultWeight: 60)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService(),
            exerciseRepository: MockExerciseRepository()
        )
        await vm.startWorkout()
        let we = try #require(vm.workout?.exercises.first)

        await vm.updateExerciseNotes(we, notes: "   ")

        #expect(exercise.notes == nil)
        await vm.awaitPendingSave()
        withExtendedLifetime(container) {}
    }

    @Test("updateExerciseNotes after finish still saves — the note is not workout data")
    func updateExerciseNotesAfterFinishStillSaves() async throws {
        let (container, exercise, template) = try makeSetup()
        let context = container.mainContext
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 1, defaultReps: 8, defaultWeight: 60)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService(),
            exerciseRepository: MockExerciseRepository()
        )
        await vm.startWorkout()
        let we = try #require(vm.workout?.exercises.first)
        vm.completeSet(try #require(we.sets.first))
        let workout = try #require(vm.workout)
        await vm.finishWorkout()
        await vm.awaitPostCommitWork()
        workout.syncStatus = .synced

        await vm.updateExerciseNotes(we, notes: "late note")

        #expect(exercise.notes == "late note")
        // The finished workout record stays authoritative — the note write
        // must not re-open it for a draft save (#124).
        #expect(workout.syncStatus == .synced)
        await vm.awaitPendingSave()
        withExtendedLifetime(container) {}
    }
}
