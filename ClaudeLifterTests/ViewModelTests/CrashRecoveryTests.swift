import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

/// Issue #75 — crash recovery. An in-progress workout (`completedAt == nil`)
/// must survive an app crash/force-quit, be surfaced on the Home screen as
/// resumable, and only ever be deleted after an explicit user choice.
/// Starting a new workout must NOT silently delete non-empty drafts.
@Suite("Crash Recovery (#75)")
@MainActor
struct CrashRecoveryTests {

    // MARK: - Helpers

    /// A standalone (not context-inserted) in-progress workout with one
    /// exercise and two sets, the first of which is completed. Mirrors what
    /// "Save progress as draft" or a mid-session crash leaves behind.
    private func makeStandaloneDraft(
        name: String = "Push Day",
        startedAt: Date = Date(timeIntervalSinceNow: -1800)
    ) -> Workout {
        let workout = Workout(name: name, startedAt: startedAt, completedAt: nil)
        let exercise = TestFixtures.makeExercise(
            name: "Bench \(UUID().uuidString.prefix(8))"
        )
        let we = WorkoutExercise(order: 0, exercise: exercise)
        we.sets.append(
            WorkoutSet(order: 0, weight: 80, weightUnit: .kg, reps: 8,
                       isCompleted: true, completedAt: .now)
        )
        we.sets.append(
            WorkoutSet(order: 1, weight: 80, weightUnit: .kg, reps: 8)
        )
        workout.exercises.append(we)
        return workout
    }

    /// A ghost session: in-progress, no exercises, no notes. The only kind
    /// of workout that may be cleaned up without asking.
    private func makeGhost(startedAt: Date = Date(timeIntervalSinceNow: -7200)) -> Workout {
        Workout(name: "Quick Workout", startedAt: startedAt, completedAt: nil)
    }

    // MARK: - Resuming restores the session

    @Test("init(resuming:) restores the draft as the active workout with sets intact")
    func resumeRestoresWorkoutWithSets() throws {
        let repo = MockWorkoutRepository()
        let draft = makeStandaloneDraft()
        repo.workouts = [draft]

        let vm = ActiveWorkoutViewModel(
            resuming: draft,
            workoutRepository: repo,
            autoFillService: MockAutoFillService()
        )

        #expect(vm.workout?.id == draft.id)
        #expect(vm.hasCompletedSets == true)
        #expect(vm.totalSetsCompleted == 1)
        #expect(vm.workout?.exercises.first?.sets.count == 2)
    }

    @Test("startWorkout on a resumed VM neither recreates the workout nor deletes anything")
    func startWorkoutOnResumedVMIsNoOp() async throws {
        let repo = MockWorkoutRepository()
        let draft = makeStandaloneDraft()
        repo.workouts = [draft]
        let vm = ActiveWorkoutViewModel(
            resuming: draft,
            workoutRepository: repo,
            autoFillService: MockAutoFillService()
        )

        // ActiveWorkoutView fires startWorkout from .task — it must be safe
        // to call on a resumed session.
        await vm.startWorkout()

        #expect(vm.workout?.id == draft.id)
        #expect(vm.totalSetsCompleted == 1, "Resumed sets must stay intact")
        #expect(repo.deletedWorkouts.isEmpty, "Resuming must not delete anything")
    }

    // MARK: - Starting a new workout no longer nukes drafts

    @Test("starting a new workout must NOT delete a non-empty in-progress draft")
    func startWorkoutKeepsNonEmptyDraft() async throws {
        let repo = MockWorkoutRepository()
        let draft = makeStandaloneDraft()
        let finished = TestFixtures.makeWorkout(name: "Done Yesterday")
        repo.workouts = [draft, finished]

        let vm = ActiveWorkoutViewModel(
            adHocName: "Quick Workout",
            workoutRepository: repo,
            autoFillService: MockAutoFillService()
        )
        await vm.startWorkout()

        #expect(!repo.deletedWorkouts.contains(where: { $0.id == draft.id }),
                "A draft with logged sets must never be silently deleted")
        #expect(repo.workouts.contains(where: { $0.id == draft.id }))
        #expect(repo.workouts.contains(where: { $0.id == finished.id }))
    }

    @Test("starting a new workout still cleans up a genuinely empty ghost session")
    func startWorkoutCleansEmptyGhost() async throws {
        let repo = MockWorkoutRepository()
        let ghost = makeGhost()
        let finished = TestFixtures.makeWorkout(name: "Done Yesterday")
        repo.workouts = [ghost, finished]

        let vm = ActiveWorkoutViewModel(
            adHocName: "Quick Workout",
            workoutRepository: repo,
            autoFillService: MockAutoFillService()
        )
        await vm.startWorkout()

        #expect(repo.deletedWorkouts.map(\.id) == [ghost.id],
                "Only the empty ghost may be cleaned up")
        #expect(repo.workouts.contains(where: { $0.id == finished.id }))
    }

    // MARK: - Home surfaces the resumable draft

    @Test("checkForResumableWorkout surfaces the in-progress draft")
    func homeDetectsResumableDraft() async throws {
        let repo = MockWorkoutRepository()
        let draft = makeStandaloneDraft()
        repo.workouts = [TestFixtures.makeWorkout(name: "Done"), draft]
        let vm = HomeViewModel(
            templateRepository: MockTemplateRepository(),
            workoutRepository: repo
        )

        await vm.checkForResumableWorkout()

        #expect(vm.resumableWorkout?.id == draft.id)
    }

    @Test("checkForResumableWorkout ignores completed workouts and empty ghosts")
    func homeIgnoresCompletedAndGhosts() async throws {
        let repo = MockWorkoutRepository()
        repo.workouts = [TestFixtures.makeWorkout(name: "Done"), makeGhost()]
        let vm = HomeViewModel(
            templateRepository: MockTemplateRepository(),
            workoutRepository: repo
        )

        await vm.checkForResumableWorkout()

        #expect(vm.resumableWorkout == nil)
    }

    @Test("checkForResumableWorkout picks the most recent of several drafts")
    func homePicksMostRecentDraft() async throws {
        let repo = MockWorkoutRepository()
        let older = makeStandaloneDraft(
            name: "Old Draft", startedAt: Date(timeIntervalSinceNow: -86_400)
        )
        let newer = makeStandaloneDraft(
            name: "New Draft", startedAt: Date(timeIntervalSinceNow: -600)
        )
        repo.workouts = [older, newer]
        let vm = HomeViewModel(
            templateRepository: MockTemplateRepository(),
            workoutRepository: repo
        )

        await vm.checkForResumableWorkout()

        #expect(vm.resumableWorkout?.id == newer.id)
    }

    @Test("discardResumableWorkout deletes exactly the surfaced workout")
    func discardDeletesExactlyOne() async throws {
        let repo = MockWorkoutRepository()
        let older = makeStandaloneDraft(
            name: "Old Draft", startedAt: Date(timeIntervalSinceNow: -86_400)
        )
        let newer = makeStandaloneDraft(
            name: "New Draft", startedAt: Date(timeIntervalSinceNow: -600)
        )
        let finished = TestFixtures.makeWorkout(name: "Done")
        repo.workouts = [older, newer, finished]
        let vm = HomeViewModel(
            templateRepository: MockTemplateRepository(),
            workoutRepository: repo
        )
        await vm.checkForResumableWorkout()
        #expect(vm.resumableWorkout?.id == newer.id)

        await vm.discardResumableWorkout()

        #expect(repo.deletedWorkouts.map(\.id) == [newer.id],
                "Discard must delete exactly the one surfaced workout")
        #expect(repo.workouts.contains(where: { $0.id == finished.id }))
        // The next lingering draft surfaces so it can also be resolved.
        #expect(vm.resumableWorkout?.id == older.id)
    }

    @Test("discardResumableWorkout failure surfaces errorMessage and deletes nothing")
    func discardFailureSurfacesError() async throws {
        let repo = MockWorkoutRepository()
        let draft = makeStandaloneDraft()
        repo.workouts = [draft]
        let vm = HomeViewModel(
            templateRepository: MockTemplateRepository(),
            workoutRepository: repo
        )
        await vm.checkForResumableWorkout()
        repo.errorToThrow = NSError(
            domain: "test", code: 9,
            userInfo: [NSLocalizedDescriptionKey: "Delete failed"]
        )

        await vm.discardResumableWorkout()

        #expect(vm.errorMessage != nil)
        #expect(repo.deletedWorkouts.isEmpty)
    }

    // MARK: - Full crash/relaunch cycle over a real SwiftData repository

    @Test("relaunch: mid-session progress is detected and resumable with sets intact")
    func relaunchResumeCycle() async throws {
        // Arrange — session 1: user starts from a template and logs a set.
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataWorkoutRepository(context: context)

        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)
        let template = TestFixtures.makeTemplate(name: "Push Day")
        context.insert(template)
        let te = TemplateExercise(
            order: 0, exercise: exercise,
            defaultSets: 2, defaultReps: 8, defaultWeight: 60
        )
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let session1 = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: repo,
            autoFillService: MockAutoFillService()
        )
        await session1.startWorkout()
        let set = try #require(session1.workout?.exercises.first?.sets.first)
        session1.completeSet(set)
        await session1.awaitPendingSave()
        let draftId = try #require(session1.workout?.id)

        // Act — "relaunch": fresh Home state over the same repository, as
        // the app would build after a crash or force-quit.
        let home = HomeViewModel(
            templateRepository: MockTemplateRepository(),
            workoutRepository: repo
        )
        await home.checkForResumableWorkout()

        // Assert — the draft is detected and resumable with sets intact.
        let resumable = try #require(home.resumableWorkout,
                                     "Relaunch must detect the in-progress workout")
        #expect(resumable.id == draftId)

        let resumed = ActiveWorkoutViewModel(
            resuming: resumable,
            workoutRepository: repo,
            autoFillService: MockAutoFillService()
        )
        await resumed.startWorkout() // View fires this from .task — must be safe
        #expect(resumed.workout?.id == draftId)
        #expect(resumed.totalSetsCompleted == 1, "Logged set must survive the relaunch")
        #expect(resumed.workout?.exercises.first?.sets.count == 2)

        withExtendedLifetime(container) {}
    }

    @Test("relaunch: starting a new workout instead of resuming leaves the draft untouched")
    func relaunchStartNewKeepsDraft() async throws {
        // Arrange — session 1 crashes mid-workout with one completed set.
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataWorkoutRepository(context: context)

        let exercise = TestFixtures.makeExercise(name: "Squat")
        context.insert(exercise)
        let template = TestFixtures.makeTemplate(name: "Leg Day")
        context.insert(template)
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 2, defaultReps: 5)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let session1 = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: repo,
            autoFillService: MockAutoFillService()
        )
        await session1.startWorkout()
        let set = try #require(session1.workout?.exercises.first?.sets.first)
        session1.completeSet(set)
        await session1.awaitPendingSave()
        let draftId = try #require(session1.workout?.id)

        // Act — after relaunch the user ignores the prompt and starts fresh.
        let session2 = ActiveWorkoutViewModel(
            adHocName: "Quick Workout",
            workoutRepository: repo,
            autoFillService: MockAutoFillService()
        )
        await session2.startWorkout()

        // Assert — the draft and its logged set are still in the store.
        let all = try await repo.fetchAll()
        let draft = try #require(all.first(where: { $0.id == draftId }),
                                 "Starting a new workout must not delete the draft")
        #expect(draft.exercises.flatMap(\.sets).filter(\.isCompleted).count == 1)

        withExtendedLifetime(container) {}
    }
}
