import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

/// Report 07B1AD96 (2026-09-18): a workout left open finishes itself three
/// hours after the last logged set, records first-set-to-last-set as its
/// duration, and says so on the summary the user sees when they come back.
@Suite("Auto-finish idle workouts (report 07B1AD96)")
@MainActor
struct AutoFinishTests {

    private func hoursAgo(_ hours: Double) -> Date {
        Date(timeIntervalSinceNow: -hours * 3600)
    }

    /// A draft left behind by a force-quit or "Save progress as draft": two
    /// completed sets at the given times, one set never ticked.
    private func makeDraft(
        startedAt: Date,
        firstSetAt: Date,
        lastSetAt: Date
    ) -> Workout {
        let workout = Workout(name: "Lower A", startedAt: startedAt)
        let we = WorkoutExercise(
            order: 0,
            exercise: TestFixtures.makeExercise(name: "Seated Calf Raise")
        )
        we.sets.append(WorkoutSet(
            order: 0, weight: 37.5, reps: 15, isCompleted: true, completedAt: firstSetAt
        ))
        we.sets.append(WorkoutSet(
            order: 1, weight: 40, reps: 15, isCompleted: true, completedAt: lastSetAt
        ))
        we.sets.append(WorkoutSet(order: 2, weight: 40, reps: 15))
        workout.exercises.append(we)
        return workout
    }

    private func makeResumedVM(
        _ workout: Workout,
        repo: MockWorkoutRepository = MockWorkoutRepository()
    ) -> ActiveWorkoutViewModel {
        repo.workouts = [workout]
        return ActiveWorkoutViewModel(
            resuming: workout,
            workoutRepository: repo,
            autoFillService: MockAutoFillService()
        )
    }

    @Test("an idle workout is finished with its duration trimmed to the logged sets")
    func idleWorkoutFinishesWithTrimmedDuration() async throws {
        let firstSetAt = hoursAgo(5)
        let lastSetAt = hoursAgo(4)
        let draft = makeDraft(
            startedAt: hoursAgo(5.5),
            firstSetAt: firstSetAt,
            lastSetAt: lastSetAt
        )
        let repo = MockWorkoutRepository()
        let vm = makeResumedVM(draft, repo: repo)

        let finished = await vm.autoFinishIfIdle()

        #expect(finished)
        #expect(vm.isFinished)
        #expect(draft.startedAt == firstSetAt, "Duration starts at the first logged set")
        #expect(draft.completedAt == lastSetAt, "Duration ends at the last logged set, not now")
        #expect(repo.savedWorkouts.contains { $0.id == draft.id })
    }

    @Test("the summary says the workout was finished automatically")
    func summaryIsMarkedAutomatic() async throws {
        let draft = makeDraft(
            startedAt: hoursAgo(5.5),
            firstSetAt: hoursAgo(5),
            lastSetAt: hoursAgo(4)
        )
        let vm = makeResumedVM(draft)

        await vm.autoFinishIfIdle()

        let summary = try #require(vm.completionSummary)
        #expect(summary.finishedAutomatically)
    }

    @Test("a workout with a set logged under three hours ago stays open")
    func activeWorkoutStaysOpen() async throws {
        let draft = makeDraft(
            startedAt: hoursAgo(3),
            firstSetAt: hoursAgo(2.5),
            lastSetAt: hoursAgo(1)
        )
        let originalStart = draft.startedAt
        let repo = MockWorkoutRepository()
        let vm = makeResumedVM(draft, repo: repo)

        let finished = await vm.autoFinishIfIdle()

        #expect(!finished)
        #expect(!vm.isFinished)
        #expect(draft.completedAt == nil)
        #expect(draft.startedAt == originalStart)
        #expect(repo.saveCallCount == 0)
    }

    @Test("a workout the user finished by hand is not marked automatic")
    func manualFinishIsNotAutomatic() async throws {
        let draft = makeDraft(
            startedAt: hoursAgo(1),
            firstSetAt: hoursAgo(0.9),
            lastSetAt: hoursAgo(0.1)
        )
        let vm = makeResumedVM(draft)

        await vm.finishWorkout()

        let summary = try #require(vm.completionSummary)
        #expect(!summary.finishedAutomatically)
    }

    @Test("auto-finish after a finish does nothing")
    func autoFinishIsIdempotent() async throws {
        let draft = makeDraft(
            startedAt: hoursAgo(5.5),
            firstSetAt: hoursAgo(5),
            lastSetAt: hoursAgo(4)
        )
        let repo = MockWorkoutRepository()
        let vm = makeResumedVM(draft, repo: repo)

        await vm.autoFinishIfIdle()
        let savesAfterFirst = repo.saveCallCount
        let completedAt = draft.completedAt

        let again = await vm.autoFinishIfIdle()

        #expect(!again)
        #expect(repo.saveCallCount == savesAfterFirst)
        #expect(draft.completedAt == completedAt)
    }

    @Test("a failed save restores the original start time and stays retryable")
    func failedAutoFinishRestoresStart() async throws {
        let startedAt = hoursAgo(5.5)
        let draft = makeDraft(
            startedAt: startedAt,
            firstSetAt: hoursAgo(5),
            lastSetAt: hoursAgo(4)
        )
        let repo = MockWorkoutRepository()
        let vm = makeResumedVM(draft, repo: repo)
        repo.errorToThrow = NSError(domain: "Save", code: 1)

        let finished = await vm.autoFinishIfIdle()

        #expect(!finished)
        #expect(!vm.isFinished)
        #expect(draft.completedAt == nil)
        #expect(draft.startedAt == startedAt, "A failed save must not leave a half-trimmed workout")

        repo.errorToThrow = nil
        #expect(await vm.autoFinishIfIdle())
        #expect(vm.isFinished)
    }

    @Test("the template records when the workout ended, not when the app noticed")
    func templateLastPerformedIsTheLastSet() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = TestFixtures.makeExercise(name: "Seated Calf Raise")
        context.insert(exercise)
        let template = TestFixtures.makeTemplate(name: "Lower A")
        context.insert(template)
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 1, defaultReps: 15)
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService(),
            templateRepository: MockTemplateRepository()
        )
        await vm.startWorkout()
        let set = try #require(vm.workout?.exercises.first?.sets.first)
        vm.completeSet(set)
        await vm.awaitPendingSave()
        let lastSetAt = hoursAgo(4)
        set.completedAt = lastSetAt

        await vm.autoFinishIfIdle()
        await vm.awaitPostCommitWork()

        #expect(template.lastPerformedAt == lastSetAt)
        withExtendedLifetime(container) {}
    }
}
