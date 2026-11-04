import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

/// "Machine taken" (#169): swap a planned exercise for one of the template's
/// listed alternatives, for this session only, in at most two taps.
@Suite("Machine taken swap")
@MainActor
struct MachineTakenSwapTests {

    @MainActor
    struct Fixture {
        let container: ModelContainer
        let template: WorkoutTemplate
        let squat: Exercise
        let legPress: Exercise
        let hackSquat: Exercise
        let curl: Exercise
        let squatTemplateExercise: TemplateExercise
        let autoFill: MockAutoFillService
        let alternatives: MockExerciseAlternativeRepository
        let baselines: MockTemplateBaselineRepository
        let vm: ActiveWorkoutViewModel

        var squatSlot: WorkoutExercise {
            // Force unwrap acceptable in tests: the fixture always starts one.
            vm.orderedExercises[0]
        }
    }

    /// Squat (3 sets) then Leg Curl (2 sets). Squat lists Leg Press and Hack
    /// Squat as alternatives; Leg Press has history, Hack Squat has none.
    func makeFixture(listAlternatives: Bool = true) async throws -> Fixture {
        let container = try makeTestContainer()
        let context = container.mainContext
        let squat = TestFixtures.makeExercise(name: "Squat", primaryMuscles: ["quadriceps"], externalId: "Barbell_Squat")
        let legPress = TestFixtures.makeExercise(name: "Leg Press", primaryMuscles: ["quadriceps"], externalId: "Leg_Press")
        let hackSquat = TestFixtures.makeExercise(name: "Hack Squat", primaryMuscles: ["quadriceps"], externalId: "Hack_Squat")
        let curl = TestFixtures.makeExercise(name: "Leg Curl", primaryMuscles: ["hamstrings"], externalId: "Leg_Curl")
        for exercise in [squat, legPress, hackSquat, curl] { context.insert(exercise) }

        let template = TestFixtures.makeTemplate(name: "Lower A")
        context.insert(template)
        let squatTE = TemplateExercise(order: 0, exercise: squat, defaultSets: 3, defaultReps: 8, notes: "Belt on")
        let curlTE = TemplateExercise(order: 1, exercise: curl, defaultSets: 2, defaultReps: 12)
        for te in [squatTE, curlTE] {
            context.insert(te)
            template.exercises.append(te)
        }
        try context.save()

        let autoFill = MockAutoFillService()
        autoFill.resultByExerciseId[squat.id] = AutoFillResult(weight: 80, weightUnit: .kg, reps: 8, date: .now)
        autoFill.valuesByExerciseId[legPress.id] = [
            AutoFillResult(weight: 140, weightUnit: .kg, reps: 12, date: .now),
            AutoFillResult(weight: 150, weightUnit: .kg, reps: 10, date: .now),
        ]
        autoFill.resultByExerciseId[legPress.id] = AutoFillResult(weight: 150, weightUnit: .kg, reps: 10, date: .now)

        let alternatives = MockExerciseAlternativeRepository()
        if listAlternatives {
            alternatives.alternatives = [
                ExerciseAlternative(templateExerciseId: squatTE.id, externalId: "Leg_Press", order: 0, note: "if the rack is taken"),
                ExerciseAlternative(templateExerciseId: squatTE.id, externalId: "Hack_Squat", order: 1),
                // Listed by the Coach but not in this phone's catalog.
                ExerciseAlternative(templateExerciseId: squatTE.id, externalId: "Not_In_Catalog", order: 2),
            ]
        }
        let exerciseRepository = MockExerciseRepository()
        exerciseRepository.exercises = [squat, legPress, hackSquat, curl]
        let templateRepository = MockTemplateRepository()
        templateRepository.templates = [template]

        let baselines = MockTemplateBaselineRepository()
        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: autoFill,
            exerciseRepository: exerciseRepository,
            templateRepository: templateRepository,
            baselineRepository: baselines,
            alternativeRepository: alternatives
        )
        await vm.startWorkout()
        await vm.awaitPlannedTargetsLoad()
        await vm.awaitAlternativesLoad()
        return Fixture(
            container: container,
            template: template,
            squat: squat,
            legPress: legPress,
            hackSquat: hackSquat,
            curl: curl,
            squatTemplateExercise: squatTE,
            autoFill: autoFill,
            alternatives: alternatives,
            baselines: baselines,
            vm: vm
        )
    }

    // MARK: - Listing

    @Test("A planned exercise lists the template's alternatives in order, with last time")
    func listsAlternativesWithLastTime() async throws {
        let f = try await makeFixture()

        let options = f.vm.alternatives(for: f.squatSlot)

        // The unknown externalId is dropped rather than shown as a dead row.
        #expect(options.map(\.name) == ["Leg Press", "Hack Squat"])
        #expect(options.first?.note == "if the rack is taken")
        #expect(options.first?.lastText(locale: Locale(identifier: "en_US")) == "last: 150 kg × 10")
        #expect(options.last?.lastText(locale: Locale(identifier: "en_US")) == nil)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("An exercise with no alternatives lists none, so the button goes straight to Other…")
    func noAlternativesListsNone() async throws {
        let f = try await makeFixture(listAlternatives: false)
        #expect(f.vm.alternatives(for: f.squatSlot).isEmpty)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("A resumed workout finds its alternatives through the baseline")
    func resumedWorkoutFindsAlternatives() async throws {
        let f = try await makeFixture()
        let workout = try #require(f.vm.workout)
        let exerciseRepository = MockExerciseRepository()
        exerciseRepository.exercises = [f.squat, f.legPress, f.hackSquat, f.curl]
        // The baseline the first session captured is all a resume has.
        let resumed = ActiveWorkoutViewModel(
            resuming: workout,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: f.autoFill,
            exerciseRepository: exerciseRepository,
            baselineRepository: f.baselines,
            alternativeRepository: f.alternatives
        )
        await resumed.startWorkout()
        await resumed.awaitPlannedTargetsLoad()
        await resumed.awaitAlternativesLoad()

        #expect(resumed.alternatives(for: f.squatSlot).map(\.name) == ["Leg Press", "Hack Squat"])
        await f.vm.awaitPendingSave()
        await resumed.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("The view can supply the repository after construction")
    func repositoryCanBeSuppliedLate() async throws {
        let f = try await makeFixture()
        let exerciseRepository = MockExerciseRepository()
        exerciseRepository.exercises = [f.squat, f.legPress, f.hackSquat, f.curl]
        let late = ActiveWorkoutViewModel(
            template: f.template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: f.autoFill,
            exerciseRepository: exerciseRepository,
            baselineRepository: MockTemplateBaselineRepository()
        )
        await late.startWorkout()

        late.useAlternatives(from: f.alternatives)
        await late.awaitAlternativesLoad()

        let slot = late.orderedExercises[0]
        #expect(late.alternatives(for: slot).map(\.name) == ["Leg Press", "Hack Squat"])
        await f.vm.awaitPendingSave()
        await late.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    // MARK: - Swapping

    @Test("Swap keeps the position and the set count, and changes the exercise")
    func swapKeepsOrderAndSetCount() async throws {
        let f = try await makeFixture()
        let slot = f.squatSlot
        let slotId = slot.id

        await f.vm.swap(slot, to: f.legPress)

        #expect(f.vm.orderedExercises.map { $0.exercise?.name } == ["Leg Press", "Leg Curl"])
        #expect(f.vm.orderedExercises[0].id == slotId, "Swapped in place: the same row, not a new one")
        #expect(slot.order == 0)
        #expect(slot.sets.count == 3)
        #expect(f.vm.isSwapped(slot))
        #expect(f.vm.workout?.syncStatus == .pending)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("Swap autofills committed weights and reps from the alternative's own history")
    func swapAutofillsFromAlternativeHistory() async throws {
        let f = try await makeFixture()
        let slot = f.squatSlot

        await f.vm.swap(slot, to: f.legPress)

        let sets = slot.sets.sorted { $0.order < $1.order }
        #expect(sets.map(\.weight) == [140, 150, 150])
        #expect(sets.map(\.reps) == [12, 10, 10])
        #expect(f.vm.previous(for: sets[0])?.weight == 140)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("Swapping to an alternative with no history keeps the planned reps and leaves weight empty")
    func swapWithoutHistoryKeepsPlannedReps() async throws {
        let f = try await makeFixture()
        let slot = f.squatSlot

        await f.vm.swap(slot, to: f.hackSquat)

        let sets = slot.sets.sorted { $0.order < $1.order }
        // Squat's 80 kg would be a lie on a hack squat. Empty means the field
        // shows "BW" until he types a weight.
        #expect(sets.allSatisfy { $0.weight == nil })
        #expect(sets.allSatisfy { $0.reps == 8 })
        #expect(sets.allSatisfy { f.vm.previous(for: $0) == nil })
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("Undo restores the original exercise, its values and its note")
    func undoRestoresOriginal() async throws {
        let f = try await makeFixture()
        let slot = f.squatSlot
        let before = slot.sets.sorted { $0.order < $1.order }.map { ($0.weight, $0.reps) }
        #expect(slot.notes == "Belt on")

        await f.vm.swap(slot, to: f.legPress)
        #expect(f.vm.swappedFromName(for: slot) == "Squat")
        #expect(slot.notes == nil, "The squat cue does not belong on the leg press")
        await f.vm.undoSwap(slot)

        let after = slot.sets.sorted { $0.order < $1.order }.map { ($0.weight, $0.reps) }
        #expect(slot.exercise?.id == f.squat.id)
        #expect(after.map(\.0) == before.map(\.0))
        #expect(after.map(\.1) == before.map(\.1))
        #expect(slot.notes == "Belt on")
        #expect(f.vm.isSwapped(slot) == false)
        #expect(f.vm.swappedFromName(for: slot) == nil)
        #expect(f.vm.previous(for: try #require(slot.sets.first))?.weight == 80)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("A second swap from the alternative still undoes to the original")
    func secondSwapUndoesToOriginal() async throws {
        let f = try await makeFixture()
        let slot = f.squatSlot

        await f.vm.swap(slot, to: f.legPress)
        await f.vm.swap(slot, to: f.hackSquat)
        #expect(f.vm.swappedFromName(for: slot) == "Squat")
        await f.vm.undoSwap(slot)

        #expect(slot.exercise?.id == f.squat.id)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("Swapping to the planned exercise is an undo")
    func swappingBackIsUndo() async throws {
        let f = try await makeFixture()
        let slot = f.squatSlot

        await f.vm.swap(slot, to: f.legPress)
        await f.vm.swap(slot, to: f.squat)

        #expect(f.vm.isSwapped(slot) == false)
        #expect(slot.notes == "Belt on")
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("A logged set blocks the swap, so history is never relabelled")
    func loggedSetBlocksSwap() async throws {
        let f = try await makeFixture()
        let slot = f.squatSlot
        f.vm.completeSet(try #require(slot.sets.first))

        #expect(f.vm.canSwap(slot) == false)
        await f.vm.swap(slot, to: f.legPress)

        #expect(slot.exercise?.id == f.squat.id)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("A swapped exercise never produces a template-change prompt at Finish")
    func swapProducesNoTemplatePrompt() async throws {
        let f = try await makeFixture()
        let slot = f.squatSlot
        await f.vm.swap(slot, to: f.legPress)
        for we in f.vm.orderedExercises {
            for set in we.sets { f.vm.completeSet(set) }
        }

        await f.vm.finishWorkout()
        await f.vm.awaitPostCommitWork()

        let summary = try #require(f.vm.completionSummary)
        #expect(summary.templateChangeSet == nil)
        // History records what was actually done.
        #expect(f.vm.workout?.exercises.contains { $0.exercise?.id == f.legPress.id } == true)
        #expect(f.template.exercises.contains { $0.exercise?.id == f.legPress.id } == false)
        withExtendedLifetime(f.container) {}
    }

    @Test("A swapped exercise with an added set still prompts nothing")
    func swapWithExtraSetPromptsNothing() async throws {
        let f = try await makeFixture()
        let slot = f.squatSlot
        await f.vm.swap(slot, to: f.legPress)
        f.vm.addSet(to: slot)
        for we in f.vm.orderedExercises {
            for set in we.sets { f.vm.completeSet(set) }
        }

        await f.vm.finishWorkout()
        await f.vm.awaitPostCommitWork()

        // Four leg-press sets say nothing about how many squat sets to plan.
        #expect(try #require(f.vm.completionSummary).templateChangeSet == nil)
        withExtendedLifetime(f.container) {}
    }

    @Test("Other… swaps to any library exercise in place")
    func otherSwapsAnyExercise() async throws {
        let f = try await makeFixture()
        let slot = f.squatSlot
        let lunge = TestFixtures.makeExercise(name: "Walking Lunge", primaryMuscles: ["quadriceps"])
        f.container.mainContext.insert(lunge)

        await f.vm.swap(slot, to: lunge)

        #expect(f.vm.orderedExercises[0].exercise?.name == "Walking Lunge")
        #expect(slot.sets.count == 3)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("The primary muscle pre-filters Other…")
    func otherPrefilterMuscle() async throws {
        let f = try await makeFixture()
        #expect(f.vm.primaryMuscle(for: f.squatSlot) == "quadriceps")
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }
}
