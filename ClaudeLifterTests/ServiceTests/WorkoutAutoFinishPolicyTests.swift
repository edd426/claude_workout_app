import Testing
import Foundation
@testable import ClaudeLifter

/// Report 07B1AD96 (2026-09-18): "I keep accidentally not clicking finish on
/// my workouts." A workout left open finishes itself once three hours pass
/// without a logged set, and records its duration from the first logged set
/// to the last rather than from Start to whenever the app noticed.
@Suite("Workout auto-finish policy (report 07B1AD96)")
@MainActor
struct WorkoutAutoFinishPolicyTests {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func hoursAgo(_ hours: Double) -> Date {
        now.addingTimeInterval(-hours * 3600)
    }

    /// An open workout with one exercise and the given sets.
    private func makeOpenWorkout(
        startedAt: Date? = nil,
        sets: [WorkoutSet]
    ) -> Workout {
        let workout = Workout(name: "Lower A", startedAt: startedAt ?? hoursAgo(6))
        let we = WorkoutExercise(
            order: 0,
            exercise: TestFixtures.makeExercise(name: "Seated Calf Raise")
        )
        for set in sets {
            we.sets.append(set)
        }
        workout.exercises.append(we)
        return workout
    }

    private func completedSet(_ order: Int, at date: Date) -> WorkoutSet {
        WorkoutSet(order: order, weight: 40, reps: 15, isCompleted: true, completedAt: date)
    }

    @Test("the idle threshold is three hours")
    func thresholdIsThreeHours() {
        #expect(WorkoutAutoFinishPolicy.idleThreshold == 3 * 60 * 60)
    }

    @Test("a workout whose last set was under three hours ago is left open")
    func recentWorkoutIsLeftOpen() {
        let workout = makeOpenWorkout(sets: [
            completedSet(0, at: hoursAgo(4)),
            completedSet(1, at: hoursAgo(2.9)),
        ])

        #expect(WorkoutAutoFinishPolicy.window(for: workout, now: now) == nil)
    }

    @Test("three hours after the last set, the window runs first set to last set")
    func idleWorkoutGetsFirstToLastSetWindow() {
        let first = hoursAgo(5)
        let last = hoursAgo(3)
        let workout = makeOpenWorkout(
            startedAt: hoursAgo(5.5),
            sets: [completedSet(0, at: first), completedSet(1, at: last)]
        )

        let window = WorkoutAutoFinishPolicy.window(for: workout, now: now)

        #expect(window == DateInterval(start: first, end: last))
    }

    @Test("sets completed out of order still give the earliest and latest")
    func outOfOrderSetsUseEarliestAndLatest() {
        let earliest = hoursAgo(6)
        let latest = hoursAgo(4)
        let workout = makeOpenWorkout(sets: [
            completedSet(0, at: hoursAgo(5)),
            completedSet(1, at: latest),
            completedSet(2, at: earliest),
        ])
        let second = WorkoutExercise(
            order: 1,
            exercise: TestFixtures.makeExercise(name: "Barbell Squat")
        )
        second.sets.append(completedSet(0, at: hoursAgo(4.5)))
        workout.exercises.append(second)

        let window = WorkoutAutoFinishPolicy.window(for: workout, now: now)

        #expect(window == DateInterval(start: earliest, end: latest))
    }

    @Test("unfinished and untimestamped sets do not count as activity")
    func onlyTimestampedCompletedSetsCount() {
        let logged = hoursAgo(4)
        let workout = makeOpenWorkout(sets: [
            completedSet(0, at: logged),
            // Filled in but never ticked — not a logged set.
            WorkoutSet(order: 1, weight: 40, reps: 15, completedAt: hoursAgo(0.5)),
            // Ticked but with no timestamp (legacy / synced) — no evidence of when.
            WorkoutSet(order: 2, weight: 40, reps: 15, isCompleted: true),
        ])

        let window = WorkoutAutoFinishPolicy.window(for: workout, now: now)

        #expect(window == DateInterval(start: logged, end: logged))
    }

    @Test("a workout with nothing logged is never auto-finished")
    func nothingLoggedIsLeftForResumeOrDiscard() {
        // Finishing a workout with no completed sets discards it (#69). That
        // must stay the user's explicit choice on the Resume card (#75), not
        // something that happens to them while they are away.
        let workout = makeOpenWorkout(
            startedAt: hoursAgo(48),
            sets: [WorkoutSet(order: 0, weight: 40, reps: 15)]
        )

        #expect(WorkoutAutoFinishPolicy.window(for: workout, now: now) == nil)
    }

    @Test("an already finished workout is left alone")
    func finishedWorkoutIsLeftAlone() {
        let workout = makeOpenWorkout(sets: [completedSet(0, at: hoursAgo(10))])
        workout.completedAt = hoursAgo(9)

        #expect(WorkoutAutoFinishPolicy.window(for: workout, now: now) == nil)
    }
}
