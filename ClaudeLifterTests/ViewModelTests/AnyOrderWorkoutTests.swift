import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

/// The "any order" workout screen (1.9.0, evaluation item 1). He trains out of
/// order in 37% of sessions and skips something in 87% of them, so which card
/// is open, what is skipped and where each exercise stands are ViewModel state
/// the screen renders, not something it works out in `body`.
@Suite("Any-order workout")
@MainActor
struct AnyOrderWorkoutTests {

    @MainActor
    struct Fixture {
        let container: ModelContainer
        let template: WorkoutTemplate
        let exercises: [Exercise]
        let templateRepository: MockTemplateRepository
        let baselineRepository: MockTemplateBaselineRepository
        let vm: ActiveWorkoutViewModel

        var workoutExercises: [WorkoutExercise] { vm.orderedExercises }
    }

    /// Lower-body day: three planned exercises, three sets each.
    func makeFixture(
        names: [String] = ["Squat", "Romanian Deadlift", "Seated Calf Raise"],
        sets: Int = 3,
        autoFill: MockAutoFillService = MockAutoFillService()
    ) async throws -> Fixture {
        let container = try makeTestContainer()
        let context = container.mainContext
        let template = TestFixtures.makeTemplate(name: "Lower A")
        context.insert(template)
        var exercises: [Exercise] = []
        for (index, name) in names.enumerated() {
            let exercise = TestFixtures.makeExercise(name: name, primaryMuscles: ["quadriceps"])
            context.insert(exercise)
            exercises.append(exercise)
            let te = TemplateExercise(
                order: index,
                exercise: exercise,
                defaultSets: sets,
                defaultReps: 8,
                defaultRestSeconds: 90
            )
            context.insert(te)
            template.exercises.append(te)
        }
        try context.save()

        let templateRepository = MockTemplateRepository()
        templateRepository.templates = [template]
        let baselineRepository = MockTemplateBaselineRepository()
        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: autoFill,
            templateRepository: templateRepository,
            baselineRepository: baselineRepository
        )
        await vm.startWorkout()
        await vm.awaitPlannedTargetsLoad()
        return Fixture(
            container: container,
            template: template,
            exercises: exercises,
            templateRepository: templateRepository,
            baselineRepository: baselineRepository,
            vm: vm
        )
    }

    // MARK: - Ordering

    @Test("orderedExercises follows each exercise's order")
    func orderedExercisesFollowOrder() async throws {
        let f = try await makeFixture()
        #expect(f.vm.orderedExercises.map { $0.exercise?.name } == [
            "Squat", "Romanian Deadlift", "Seated Calf Raise",
        ])
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("Move down swaps an exercise with the next one and persists")
    func moveDownSwapsWithNext() async throws {
        let f = try await makeFixture()
        let squat = f.workoutExercises[0]

        f.vm.moveExercise(squat, by: 1)

        #expect(f.vm.orderedExercises.map { $0.exercise?.name } == [
            "Romanian Deadlift", "Squat", "Seated Calf Raise",
        ])
        #expect(f.vm.workout?.syncStatus == .pending)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("Move up and move down stop at the ends")
    func moveStopsAtEnds() async throws {
        let f = try await makeFixture()
        let first = f.workoutExercises[0]
        let last = f.workoutExercises[2]

        #expect(f.vm.canMove(first, by: -1) == false)
        #expect(f.vm.canMove(last, by: 1) == false)
        #expect(f.vm.canMove(first, by: 1))
        f.vm.moveExercise(first, by: -1)

        #expect(f.vm.orderedExercises.first?.id == first.id)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    // MARK: - Expansion

    @Test("The first exercise with incomplete sets starts expanded")
    func firstIncompleteStartsExpanded() async throws {
        let f = try await makeFixture()
        #expect(f.vm.expandedExerciseId == f.workoutExercises[0].id)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("A resumed workout opens on the first exercise that still has work")
    func resumedWorkoutOpensOnFirstIncomplete() async throws {
        let squat = TestFixtures.makeExercise(name: "Squat")
        let curl = TestFixtures.makeExercise(name: "Leg Curl")
        let workout = Workout(name: "Draft", startedAt: .now)
        let done = WorkoutExercise(order: 0, exercise: squat)
        done.sets = [WorkoutSet(order: 0, weight: 80, reps: 8, isCompleted: true, completedAt: .now)]
        let open = WorkoutExercise(order: 1, exercise: curl)
        open.sets = [WorkoutSet(order: 0, weight: 40, reps: 12)]
        workout.exercises = [done, open]
        let vm = ActiveWorkoutViewModel(
            resuming: workout,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService()
        )

        await vm.startWorkout()

        #expect(vm.expandedExerciseId == open.id)
    }

    @Test("Expanding a card collapses the one that was open")
    func expandingIsExclusive() async throws {
        let f = try await makeFixture()
        let calf = f.workoutExercises[2]

        f.vm.expand(calf)

        #expect(f.vm.isExpanded(calf))
        #expect(f.vm.isExpanded(f.workoutExercises[0]) == false)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("Toggling the open card collapses it, leaving none open")
    func togglingOpenCardCollapses() async throws {
        let f = try await makeFixture()
        let squat = f.workoutExercises[0]

        f.vm.toggleExpansion(squat)

        #expect(f.vm.expandedExerciseId == nil)
        f.vm.toggleExpansion(squat)
        #expect(f.vm.expandedExerciseId == squat.id)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("Finishing the open card's last set does not move the expansion")
    func completingLastSetKeepsExpansion() async throws {
        let f = try await makeFixture()
        let squat = f.workoutExercises[0]

        for set in squat.sets { f.vm.completeSet(set) }

        // UI-H3: the target never moves under the thumb mid-set. His next
        // tap, not an order, decides what opens next.
        #expect(f.vm.expandedExerciseId == squat.id)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    // MARK: - Progress

    @Test("Progress counts completed sets and derives the status")
    func progressDerivesStatus() async throws {
        let f = try await makeFixture()
        let squat = f.workoutExercises[0]
        let rdl = f.workoutExercises[1]
        let sortedSquatSets = squat.sets.sorted { $0.order < $1.order }

        #expect(f.vm.progress(for: squat) == ExerciseProgress(completedSets: 0, totalSets: 3, status: .untouched))
        f.vm.completeSet(sortedSquatSets[0])
        #expect(f.vm.progress(for: squat) == ExerciseProgress(completedSets: 1, totalSets: 3, status: .inProgress))
        for set in sortedSquatSets { if !set.isCompleted { f.vm.completeSet(set) } }
        #expect(f.vm.progress(for: squat).status == .finished)
        #expect(f.vm.progress(for: rdl).status == .untouched)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    // MARK: - Skip today

    @Test("Skip marks the exercise skipped and collapses it")
    func skipMarksAndCollapses() async throws {
        let f = try await makeFixture()
        let squat = f.workoutExercises[0]

        f.vm.skip(squat)

        #expect(f.vm.isSkipped(squat))
        #expect(f.vm.progress(for: squat).status == .skipped)
        #expect(f.vm.isExpanded(squat) == false)
        // Skipping is not a removal: the rows stay, nothing is deleted.
        #expect(squat.sets.count == 3)
        #expect(f.vm.workout?.exercises.count == 3)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("Opening a skipped card un-skips it")
    func expandingUnskips() async throws {
        let f = try await makeFixture()
        let squat = f.workoutExercises[0]
        f.vm.skip(squat)

        f.vm.expand(squat)

        #expect(f.vm.isSkipped(squat) == false)
        #expect(f.vm.isExpanded(squat))
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("An exercise with a logged set cannot be skipped")
    func cannotSkipStartedExercise() async throws {
        let f = try await makeFixture()
        let squat = f.workoutExercises[0]
        f.vm.completeSet(try #require(squat.sets.first))

        #expect(f.vm.canSkip(squat) == false)
        f.vm.skip(squat)

        #expect(f.vm.isSkipped(squat) == false)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("A skipped exercise never produces a template-change prompt at Finish")
    func skipProducesNoTemplatePrompt() async throws {
        let f = try await makeFixture()
        let squat = f.workoutExercises[0]
        let rdl = f.workoutExercises[1]
        let calf = f.workoutExercises[2]
        for set in squat.sets { f.vm.completeSet(set) }
        for set in rdl.sets { f.vm.completeSet(set) }

        f.vm.skip(calf)
        await f.vm.finishWorkout()
        await f.vm.awaitPostCommitWork()

        let summary = try #require(f.vm.completionSummary)
        #expect(summary.templateChangeSet == nil)
        withExtendedLifetime(f.container) {}
    }

    @Test("Doing the exercises out of order without moving them prompts nothing")
    func outOfOrderPromptsNothing() async throws {
        let f = try await makeFixture()
        // Calf first, then squat, then RDL: the cards stay where they are.
        for we in [f.workoutExercises[2], f.workoutExercises[0], f.workoutExercises[1]] {
            f.vm.expand(we)
            for set in we.sets { f.vm.completeSet(set) }
        }

        await f.vm.finishWorkout()
        await f.vm.awaitPostCommitWork()

        #expect(try #require(f.vm.completionSummary).templateChangeSet == nil)
        withExtendedLifetime(f.container) {}
    }

    // MARK: - Remove from this workout

    @Test("Removing the open exercise leaves no card open")
    func removingOpenExerciseClearsExpansion() async throws {
        let f = try await makeFixture()
        let squat = f.workoutExercises[0]

        f.vm.removeExercise(squat)

        #expect(f.vm.expandedExerciseId == nil)
        #expect(f.vm.orderedExercises.count == 2)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("Removing an exercise closes the gap in the order")
    func removingRenumbersOrder() async throws {
        let f = try await makeFixture()

        f.vm.removeExercise(f.workoutExercises[0])

        #expect(f.vm.orderedExercises.map(\.order) == [0, 1])
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    // MARK: - Card summaries

    @Test("A finished card summarises what was done")
    func finishedCardSummary() async throws {
        let autoFill = MockAutoFillService()
        let f = try await makeFixture(names: ["Squat"], autoFill: autoFill)
        let squat = f.workoutExercises[0]
        for set in squat.sets {
            f.vm.updateSetWeight(set, weight: 80)
            f.vm.updateSetReps(set, reps: 8)
            f.vm.completeSet(set)
        }

        #expect(f.vm.collapsedSummary(for: squat, locale: Locale(identifier: "en_US")) == "✓ 3 × 8 @ 80 kg")
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("An untouched card summarises last time")
    func untouchedCardSummary() async throws {
        let autoFill = MockAutoFillService()
        let exerciseName = "Squat"
        // The fixture creates the exercise, so seed the autofill once its id
        // is known: build, then read back.
        let f = try await makeFixture(names: [exerciseName], autoFill: autoFill)
        let squat = f.workoutExercises[0]
        autoFill.resultByExerciseId[try #require(squat.exercise?.id)] = AutoFillResult(
            weight: 75, weightUnit: .kg, reps: 8, date: .now
        )
        // A resumed copy rebuilds the previous values from the service.
        let resumed = ActiveWorkoutViewModel(
            resuming: try #require(f.vm.workout),
            workoutRepository: MockWorkoutRepository(),
            autoFillService: autoFill
        )
        await resumed.startWorkout()

        #expect(resumed.collapsedSummary(for: squat, locale: Locale(identifier: "en_US")) == "Last 3 × 8 @ 75 kg")
        await f.vm.awaitPendingSave()
        await resumed.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("A skipped card says so")
    func skippedCardSummary() async throws {
        let f = try await makeFixture()
        let squat = f.workoutExercises[0]
        f.vm.skip(squat)

        #expect(f.vm.collapsedSummary(for: squat) == "Skipped today")
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }
}
