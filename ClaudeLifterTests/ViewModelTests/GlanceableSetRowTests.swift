import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

/// Glanceable set rows (evaluation item 7), #144 drift text and #174 committed
/// prefill for exercises added mid-workout.
@Suite("Glanceable set rows")
@MainActor
struct GlanceableSetRowTests {
    private let en = Locale(identifier: "en_US")

    // MARK: - Text

    @Test("PREVIOUS reads weight × reps, with BW for bodyweight")
    func previousText() {
        let weighted = AutoFillResult(weight: 80, weightUnit: .kg, reps: 8, date: .now)
        let fractional = AutoFillResult(weight: 22.5, weightUnit: .kg, reps: 12, date: .now)
        let bodyweight = AutoFillResult(weight: nil, weightUnit: .kg, reps: 12, date: .now)
        let noReps = AutoFillResult(weight: 60, weightUnit: .kg, reps: nil, date: .now)

        #expect(SetEntryText.previous(weighted, locale: en) == "80 × 8")
        #expect(SetEntryText.previous(fractional, locale: en) == "22.5 × 12")
        #expect(SetEntryText.previous(bodyweight, locale: en) == "BW × 12")
        #expect(SetEntryText.previous(noReps, locale: en) == "60 × –")
    }

    @Test("Drift reads as last time, an arrow, and the target (#144)")
    func driftText() {
        let drifted = AutoFillResult(weight: 12, weightUnit: .kg, reps: 12, date: .now)
        #expect(SetEntryText.previous(drifted, driftTarget: 8, locale: en) == "12 × 12 → 8")
        #expect(SetEntryText.previous(drifted, driftTarget: nil, locale: en) == "12 × 12")
    }

    @Test("The target line in the card header reads sets × reps · rest")
    func targetText() {
        let target = PlannedTarget(sets: 3, reps: 8, restSeconds: 90, notes: nil)
        let noRest = PlannedTarget(sets: 2, reps: 12, restSeconds: 0, notes: nil)
        #expect(SetEntryText.target(target) == "3 × 8 · 90 s")
        #expect(SetEntryText.target(noRest) == "2 × 12")
    }

    @Test("A range of sets summarises as count × reps @ weight")
    func setRangeSummary() {
        let uniform = [(80.0, 8), (80.0, 8), (80.0, 8)].map {
            SetEntryText.Entry(weight: $0.0, unit: .kg, reps: $0.1)
        }
        let varied = [(75.0, 8), (80.0, 6), (85.0, 5)].map {
            SetEntryText.Entry(weight: $0.0, unit: .kg, reps: $0.1)
        }
        let bodyweight = [SetEntryText.Entry(weight: nil, unit: .kg, reps: 12)]

        #expect(SetEntryText.summary(of: uniform, locale: en) == "3 × 8 @ 80 kg")
        #expect(SetEntryText.summary(of: varied, locale: en) == "3 × 5–8 @ 75–85 kg")
        #expect(SetEntryText.summary(of: bodyweight, locale: en) == "1 × 12 @ BW")
        #expect(SetEntryText.summary(of: [], locale: en) == nil)
    }

    // MARK: - Drift target from the ViewModel

    @Test("The drift target is the planned reps when last session missed them")
    func driftTargetFromViewModel() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = TestFixtures.makeExercise(name: "Split Squat")
        context.insert(exercise)
        let template = TestFixtures.makeTemplate(name: "Lower B")
        context.insert(template)
        let te = TemplateExercise(order: 0, exercise: exercise, defaultSets: 2, defaultReps: 8)
        context.insert(te)
        template.exercises.append(te)
        try context.save()
        let autoFill = MockAutoFillService()
        autoFill.resultByExerciseId[exercise.id] = AutoFillResult(weight: 12, weightUnit: .kg, reps: 12, date: .now)
        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: autoFill,
            baselineRepository: MockTemplateBaselineRepository()
        )
        await vm.startWorkout()
        await vm.awaitPlannedTargetsLoad()
        let we = try #require(vm.workout?.exercises.first)
        let set = try #require(we.sets.first)

        #expect(vm.driftTarget(for: set, in: we) == 8)
        #expect(vm.previousText(for: set, in: we, locale: en) == "12 × 12 → 8")
        await vm.awaitPendingSave()
        withExtendedLifetime(container) {}
    }

    // MARK: - #174: an exercise added mid-workout

    private func makeAdHoc(
        history: AutoFillResult?
    ) async -> (ActiveWorkoutViewModel, Exercise, MockAutoFillService) {
        let exercise = TestFixtures.makeExercise(name: "Leg Press")
        let autoFill = MockAutoFillService()
        autoFill.resultByExerciseId[exercise.id] = history
        let vm = ActiveWorkoutViewModel(
            adHocName: "Quick Workout",
            workoutRepository: MockWorkoutRepository(),
            autoFillService: autoFill
        )
        await vm.startWorkout()
        return (vm, exercise, autoFill)
    }

    @Test("An added exercise commits its last weight and reps, as a template start does")
    func addedExerciseCommitsWeight() async throws {
        let (vm, exercise, _) = await makeAdHoc(
            history: AutoFillResult(weight: 60, weightUnit: .lbs, reps: 12, date: .now)
        )

        vm.addExercise(exercise)
        await vm.awaitPreviousValuesLoad()

        let sets = try #require(vm.workout?.exercises.first?.sets)
        #expect(sets.allSatisfy { $0.weight == 60 })
        #expect(sets.allSatisfy { $0.weightUnit == .lbs })
        #expect(sets.allSatisfy { $0.reps == 12 })
        await vm.awaitPendingSave()
    }

    @Test("A bodyweight exercise added mid-workout keeps an empty weight")
    func addedBodyweightExerciseKeepsNilWeight() async throws {
        // nil already means bodyweight: committing anything here would log a
        // loaded set for a dip (the rejected ghost-adoption design).
        let (vm, exercise, _) = await makeAdHoc(
            history: AutoFillResult(weight: nil, weightUnit: .kg, reps: 15, date: .now)
        )

        vm.addExercise(exercise)
        await vm.awaitPreviousValuesLoad()

        let sets = try #require(vm.workout?.exercises.first?.sets)
        #expect(sets.allSatisfy { $0.weight == nil })
        #expect(sets.allSatisfy { $0.reps == 15 })
        await vm.awaitPendingSave()
    }

    @Test("A weight typed before history loads is not overwritten")
    func typedWeightSurvivesLateLoad() async throws {
        let (vm, exercise, _) = await makeAdHoc(
            history: AutoFillResult(weight: 60, weightUnit: .kg, reps: 12, date: .now)
        )

        vm.addExercise(exercise)
        let first = try #require(vm.workout?.exercises.first?.sets.min { $0.order < $1.order })
        vm.updateSetWeight(first, weight: 70)
        await vm.awaitPreviousValuesLoad()

        #expect(first.weight == 70)
        await vm.awaitPendingSave()
    }

    @Test("A weight cleared on purpose before history loads stays empty")
    func clearedWeightSurvivesLateLoad() async throws {
        let (vm, exercise, _) = await makeAdHoc(
            history: AutoFillResult(weight: 60, weightUnit: .kg, reps: 12, date: .now)
        )

        vm.addExercise(exercise)
        let first = try #require(vm.workout?.exercises.first?.sets.min { $0.order < $1.order })
        vm.updateSetWeight(first, weight: nil)
        await vm.awaitPreviousValuesLoad()

        #expect(first.weight == nil)
        await vm.awaitPendingSave()
    }

    @Test("A resumed draft never gains a weight it did not have")
    func resumeDoesNotCommitWeight() async throws {
        let exercise = TestFixtures.makeExercise(name: "Dip")
        let workout = Workout(name: "Draft", startedAt: .now)
        let we = WorkoutExercise(order: 0, exercise: exercise)
        let set = WorkoutSet(order: 0)
        we.sets = [set]
        workout.exercises = [we]
        let autoFill = MockAutoFillService()
        autoFill.resultByExerciseId[exercise.id] = AutoFillResult(weight: 20, weightUnit: .kg, reps: 10, date: .now)
        let vm = ActiveWorkoutViewModel(
            resuming: workout,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: autoFill
        )

        await vm.startWorkout()

        // Before the crash this may have been a deliberate bodyweight set.
        #expect(set.weight == nil)
        await vm.awaitPendingSave()
    }

    // MARK: - Keyboard bar ±2.5

    @Test("±2.5 steps the weight in the set's unit", arguments: [
        (80.0 as Double?, 2.5, 82.5 as Double?),
        (80.0 as Double?, -2.5, 77.5 as Double?),
        (nil as Double?, 2.5, 2.5 as Double?),
        (nil as Double?, -2.5, nil as Double?),
        (2.5 as Double?, -2.5, nil as Double?),
        (1.0 as Double?, -2.5, nil as Double?),
    ])
    func adjustWeight(start: Double?, delta: Double, expected: Double?) async throws {
        let (vm, exercise, _) = await makeAdHoc(history: nil)
        vm.addExercise(exercise)
        await vm.awaitPreviousValuesLoad()
        let set = try #require(vm.workout?.exercises.first?.sets.first)
        vm.updateSetWeight(set, weight: start)

        vm.adjustWeight(set, by: delta)

        // Zero is bodyweight, so it is stored as nil, never as 0 kg.
        #expect(set.weight == expected)
        await vm.awaitPendingSave()
    }

    // MARK: - #170 photos

    @Test("Photos are fetched once per workout, in the background")
    func photosFetchedOnce() async throws {
        let (vm, _, _) = await makeAdHoc(history: nil)
        let fetcher = MockExercisePhotoFetcher()
        fetcher.result = 2

        await vm.fetchMissingPhotos(using: fetcher)
        await vm.fetchMissingPhotos(using: fetcher)

        #expect(fetcher.callCount == 1)
        #expect(vm.photoGeneration == 1, "cards reload their thumbnail when photos land")
    }

    @Test("No new photos leaves the thumbnails alone")
    func noNewPhotosKeepsGeneration() async throws {
        let (vm, _, _) = await makeAdHoc(history: nil)
        let fetcher = MockExercisePhotoFetcher()
        fetcher.result = 0

        await vm.fetchMissingPhotos(using: fetcher)

        #expect(vm.photoGeneration == 0)
    }
}

@MainActor
final class MockExercisePhotoFetcher: ExercisePhotoFetching {
    var callCount = 0
    var result = 0

    @discardableResult
    func fetchMissing() async -> Int {
        callCount += 1
        return result
    }
}
