import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@Suite("ProgressChartsViewModel Tests")
@MainActor
struct ProgressChartsViewModelTests {

    func makeVM() -> ProgressChartsViewModel {
        ProgressChartsViewModel(
            workoutRepository: MockWorkoutRepository(),
            exerciseRepository: MockExerciseRepository()
        )
    }

    // MARK: - Volume Tests

    @Test("Volume over time calculates total weight x reps per day")
    func volumeOverTimeCalculatesCorrectly() async throws {
        let workoutRepo = MockWorkoutRepository()
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)
        let workout = TestFixtures.makeWorkout(name: "Push Day", startedAt: Date(timeIntervalSinceNow: -3600), completedAt: Date())
        let we = TestFixtures.makeWorkoutExercise(exercise: exercise, sets: [(60, 8), (70, 6)], in: context)
        workout.exercises.append(we)
        context.insert(workout)
        try context.save()

        workoutRepo.workouts = [workout]
        let vm = ProgressChartsViewModel(workoutRepository: workoutRepo, exerciseRepository: MockExerciseRepository())

        await vm.loadVolumeOverTime(days: 30)

        #expect(!vm.volumeData.isEmpty)
        // 60*8 + 70*6 = 480 + 420 = 900
        let totalVolume = vm.volumeData.reduce(0) { $0 + $1.volume }
        #expect(abs(totalVolume - 900) < 0.01)
    }

    @Test("Volume returns empty for no workouts")
    func volumeEmptyForNoWorkouts() async {
        let vm = makeVM()
        await vm.loadVolumeOverTime(days: 30)
        #expect(vm.volumeData.isEmpty)
    }

    @Test("Volume data sorted by date ascending")
    func volumeDataSortedByDateAscending() async throws {
        let workoutRepo = MockWorkoutRepository()
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Squat")
        context.insert(exercise)

        let now = Date()
        let older = Date(timeIntervalSinceNow: -86400 * 5)

        let workout1 = TestFixtures.makeWorkout(startedAt: now, completedAt: now)
        let we1 = TestFixtures.makeWorkoutExercise(exercise: exercise, sets: [(100, 5)], in: context)
        workout1.exercises.append(we1)
        context.insert(workout1)

        let workout2 = TestFixtures.makeWorkout(startedAt: older, completedAt: older)
        let we2 = TestFixtures.makeWorkoutExercise(exercise: exercise, sets: [(90, 5)], in: context)
        workout2.exercises.append(we2)
        context.insert(workout2)

        try context.save()

        workoutRepo.workouts = [workout1, workout2]
        let vm = ProgressChartsViewModel(workoutRepository: workoutRepo, exerciseRepository: MockExerciseRepository())

        await vm.loadVolumeOverTime(days: 30)

        #expect(vm.volumeData.count >= 2)
        let dates = vm.volumeData.map(\.date)
        for i in 1..<dates.count {
            #expect(dates[i] >= dates[i - 1])
        }
    }

    @Test("Charts handle single-workout data")
    func chartsHandleSingleWorkout() async throws {
        let workoutRepo = MockWorkoutRepository()
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Deadlift")
        context.insert(exercise)
        let workout = TestFixtures.makeWorkout(completedAt: Date())
        let we = TestFixtures.makeWorkoutExercise(exercise: exercise, sets: [(150, 3)], in: context)
        workout.exercises.append(we)
        context.insert(workout)
        try context.save()

        workoutRepo.workouts = [workout]
        let vm = ProgressChartsViewModel(workoutRepository: workoutRepo, exerciseRepository: MockExerciseRepository())

        await vm.loadVolumeOverTime(days: 30)

        #expect(vm.volumeData.count == 1)
        #expect(abs(vm.volumeData[0].volume - 450) < 0.01) // 150*3
    }

    // MARK: - 1RM Tests

    @Test("1RM progression uses Brzycki formula")
    func oneRMProgressionUsesBrzyckiFormula() async throws {
        let workoutRepo = MockWorkoutRepository()
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)
        let workout = TestFixtures.makeWorkout(completedAt: Date())
        let we = TestFixtures.makeWorkoutExercise(exercise: exercise, sets: [(100, 5)], in: context)
        workout.exercises.append(we)
        context.insert(workout)
        try context.save()

        workoutRepo.workouts = [workout]
        let vm = ProgressChartsViewModel(workoutRepository: workoutRepo, exerciseRepository: MockExerciseRepository())

        await vm.load1RMProgression(exerciseId: exercise.id)

        #expect(!vm.oneRMData.isEmpty)
        // Brzycki: 100 * (36 / (37 - 5)) = 100 * (36/32) = 112.5
        let expected1RM = PersonalRecord.estimated1RM(weight: 100, reps: 5) ?? 0
        #expect(abs(vm.oneRMData[0].estimated1RM - expected1RM) < 0.01)
    }

    @Test("1RM progression filtered by exerciseId")
    func oneRMProgressionFilteredByExerciseId() async throws {
        let workoutRepo = MockWorkoutRepository()
        let container = try makeTestContainer()
        let context = container.mainContext

        let bench = TestFixtures.makeExercise(name: "Bench Press")
        let squat = TestFixtures.makeExercise(name: "Squat", primaryMuscles: ["quadriceps"])
        context.insert(bench)
        context.insert(squat)

        let workout = TestFixtures.makeWorkout(completedAt: Date())
        let weBench = TestFixtures.makeWorkoutExercise(exercise: bench, sets: [(100, 5)], in: context)
        let weSquat = TestFixtures.makeWorkoutExercise(exercise: squat, order: 1, sets: [(140, 5)], in: context)
        workout.exercises.append(contentsOf: [weBench, weSquat])
        context.insert(workout)
        try context.save()

        workoutRepo.workouts = [workout]
        let vm = ProgressChartsViewModel(workoutRepository: workoutRepo, exerciseRepository: MockExerciseRepository())

        await vm.load1RMProgression(exerciseId: bench.id)

        // Should only contain data for bench, not squat
        let expected1RM = PersonalRecord.estimated1RM(weight: 100, reps: 5) ?? 0
        let squat1RM = PersonalRecord.estimated1RM(weight: 140, reps: 5) ?? 0
        #expect(vm.oneRMData.allSatisfy { abs($0.estimated1RM - expected1RM) < 0.01 })
        #expect(!vm.oneRMData.contains { abs($0.estimated1RM - squat1RM) < 0.01 })
    }

    // MARK: - Muscle Distribution Tests

    @Test("Muscle distribution sums primary muscles across workouts")
    func muscleDistributionSumsPrimaryMuscles() async throws {
        let workoutRepo = MockWorkoutRepository()
        let container = try makeTestContainer()
        let context = container.mainContext

        let bench = TestFixtures.makeExercise(name: "Bench Press", primaryMuscles: ["chest"])
        let row = TestFixtures.makeExercise(name: "Barbell Row", primaryMuscles: ["back"])
        context.insert(bench)
        context.insert(row)

        let workout = TestFixtures.makeWorkout(completedAt: Date())
        let weBench = TestFixtures.makeWorkoutExercise(exercise: bench, sets: [(80, 8), (80, 8)], in: context)
        let weRow = TestFixtures.makeWorkoutExercise(exercise: row, order: 1, sets: [(70, 8)], in: context)
        workout.exercises.append(contentsOf: [weBench, weRow])
        context.insert(workout)
        try context.save()

        workoutRepo.workouts = [workout]
        let vm = ProgressChartsViewModel(workoutRepository: workoutRepo, exerciseRepository: MockExerciseRepository())

        await vm.loadMuscleDistribution(days: 30)

        #expect(!vm.muscleDistribution.isEmpty)
        let chestDist = vm.muscleDistribution.first { $0.muscle == "chest" }
        let backDist = vm.muscleDistribution.first { $0.muscle == "back" }
        #expect(chestDist != nil)
        #expect(backDist != nil)
    }

    @Test("Muscle distribution percentages sum to approximately 100")
    func muscleDistributionPercentagesSumTo100() async throws {
        let workoutRepo = MockWorkoutRepository()
        let container = try makeTestContainer()
        let context = container.mainContext

        let bench = TestFixtures.makeExercise(name: "Bench Press", primaryMuscles: ["chest"])
        let squat = TestFixtures.makeExercise(name: "Squat", primaryMuscles: ["quadriceps"])
        let row = TestFixtures.makeExercise(name: "Row", primaryMuscles: ["back"])
        context.insert(bench)
        context.insert(squat)
        context.insert(row)

        let workout = TestFixtures.makeWorkout(completedAt: Date())
        let we1 = TestFixtures.makeWorkoutExercise(exercise: bench, sets: [(80, 8)], in: context)
        let we2 = TestFixtures.makeWorkoutExercise(exercise: squat, order: 1, sets: [(100, 8)], in: context)
        let we3 = TestFixtures.makeWorkoutExercise(exercise: row, order: 2, sets: [(70, 8)], in: context)
        workout.exercises.append(contentsOf: [we1, we2, we3])
        context.insert(workout)
        try context.save()

        workoutRepo.workouts = [workout]
        let vm = ProgressChartsViewModel(workoutRepository: workoutRepo, exerciseRepository: MockExerciseRepository())

        await vm.loadMuscleDistribution(days: 30)

        let total = vm.muscleDistribution.reduce(0) { $0 + $1.percentage }
        #expect(abs(total - 100) < 0.1)
    }
}
