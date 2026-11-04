import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

/// History counts what was done, not what was planned (#176).
@Suite("WorkoutHistorySummary (#176)")
@MainActor
struct WorkoutHistorySummaryTests {

    /// A finished Upper A-style workout: `done` exercises with three completed
    /// sets each, and `skipped` exercises whose planned sets were never logged.
    private func makeWorkout(
        done: Int,
        skipped: Int,
        in context: ModelContext,
        start: Date = Date(timeIntervalSince1970: 1_759_734_000)
    ) -> Workout {
        let workout = Workout(name: "Upper A", startedAt: start, completedAt: start.addingTimeInterval(45 * 60))
        context.insert(workout)
        for index in 0..<(done + skipped) {
            let exercise = TestFixtures.makeExercise(name: "Exercise \(index)")
            context.insert(exercise)
            let workoutExercise = WorkoutExercise(order: index, exercise: exercise)
            context.insert(workoutExercise)
            let isDone = index < done
            for setIndex in 0..<3 {
                let set = WorkoutSet(
                    order: setIndex,
                    weight: 50,
                    weightUnit: .kg,
                    reps: 10,
                    isCompleted: isDone,
                    completedAt: isDone ? start : nil
                )
                context.insert(set)
                workoutExercise.sets.append(set)
            }
            workout.exercises.append(workoutExercise)
        }
        return workout
    }

    @Test("Counts completed exercises and sets, not planned ones")
    func countsDoneNotPlanned() throws {
        let container = try makeTestContainer()
        let workout = makeWorkout(done: 3, skipped: 6, in: container.mainContext)

        let summary = WorkoutHistorySummary(workout)

        #expect(summary.completedExercises == 3)
        #expect(summary.completedSets == 9)
        #expect(summary.skippedExercises == 6)
        #expect(summary.rowDetail == "3 exercises · 9 sets")
    }

    @Test("One exercise and one set read in the singular")
    func singular() throws {
        let container = try makeTestContainer()
        let workout = makeWorkout(done: 1, skipped: 0, in: container.mainContext)
        let sets = try #require(workout.exercises.first?.sets)
        for set in sets where set.order > 0 { set.isCompleted = false }

        let summary = WorkoutHistorySummary(workout)

        #expect(summary.rowDetail == "1 exercise · 1 set")
    }

    @Test("Duration runs from start to finish, in minutes")
    func duration() throws {
        let container = try makeTestContainer()
        let workout = makeWorkout(done: 1, skipped: 0, in: container.mainContext)

        #expect(WorkoutHistorySummary(workout).durationMinutes == 45)
    }

    @Test("Volume counts completed sets only, converted to kilograms")
    func volume() throws {
        let container = try makeTestContainer()
        let workout = makeWorkout(done: 1, skipped: 1, in: container.mainContext)
        let poundSet = WorkoutSet(order: 3, weight: 100, weightUnit: .lbs, reps: 10, isCompleted: true)
        container.mainContext.insert(poundSet)
        workout.exercises.first?.sets.append(poundSet)

        let summary = WorkoutHistorySummary(workout)

        // 3 × 50 kg × 10 + 45.36 kg × 10
        #expect(abs(summary.volumeKg - 1_953.59) < 0.01)
    }

    @Test("An exercise with no completed set is skipped")
    func skippedExercise() throws {
        let container = try makeTestContainer()
        let workout = makeWorkout(done: 1, skipped: 1, in: container.mainContext)
        let ordered = workout.exercises.sorted { $0.order < $1.order }

        #expect(!WorkoutHistorySummary.isSkipped(ordered[0]))
        #expect(WorkoutHistorySummary.isSkipped(ordered[1]))
    }

    @Test("A calendar day's label names the date, workouts and sets")
    func calendarDayLabel() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8)) ?? .now

        let label = CalendarViewModel.accessibilityLabel(
            for: day,
            summary: CalendarViewModel.DaySummary(workouts: 1, sets: 12),
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )

        #expect(label == "Thursday 8 October, 1 workout, 12 sets")
    }

    @Test("A day without a workout says so")
    func calendarEmptyDayLabel() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9)) ?? .now

        let label = CalendarViewModel.accessibilityLabel(
            for: day, summary: nil, calendar: calendar, locale: Locale(identifier: "en_GB")
        )

        #expect(label == "Friday 9 October, no workout")
    }

    @Test("loadMonth counts each day's workouts and completed sets")
    func calendarDaySummaries() async throws {
        let container = try makeTestContainer()
        let start = Date()
        let workout = makeWorkout(done: 2, skipped: 1, in: container.mainContext, start: start)
        let repo = MockWorkoutRepository()
        repo.workouts = [workout]
        let vm = CalendarViewModel(workoutRepository: repo)

        await vm.loadMonth()

        let summary = vm.daySummaries[Calendar.current.startOfDay(for: start)]
        #expect(summary == CalendarViewModel.DaySummary(workouts: 1, sets: 6))
    }
}
