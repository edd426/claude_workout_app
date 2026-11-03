import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

/// One set in a fixture workout.
struct RecencySetSpec {
    var weight: Double? = 60
    var reps: Int? = 8
    var done = true
}

/// Builds workout history inside an in-memory store. The container is held by
/// the fixture so no model outlives it (see the iOS 26.5 container-lifetime trap).
@MainActor
final class RecencyFixture {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try makeTestContainer()
    }

    func exercise(
        _ name: String,
        primary: [String],
        secondary: [String] = [],
        isCustom: Bool = false
    ) -> Exercise {
        let exercise = Exercise(
            name: name,
            primaryMuscles: primary,
            secondaryMuscles: secondary,
            isCustom: isCustom
        )
        context.insert(exercise)
        return exercise
    }

    /// A workout started at 17:00 on day `day`; each set is completed three
    /// minutes after the previous one, so later entries have later sets.
    @discardableResult
    func workout(
        _ name: String,
        day: Int,
        finished: Bool = true,
        _ entries: [(Exercise, [RecencySetSpec])]
    ) -> Workout {
        let start = TrendTestClock.day(day, hour: 17)
        let workout = Workout(
            name: name,
            startedAt: start,
            completedAt: finished ? start.addingTimeInterval(3_600) : nil
        )
        context.insert(workout)
        var minute = 0
        for (order, (exercise, sets)) in entries.enumerated() {
            let workoutExercise = WorkoutExercise(order: order, exercise: exercise)
            context.insert(workoutExercise)
            for (setOrder, spec) in sets.enumerated() {
                minute += 3
                let set = WorkoutSet(
                    order: setOrder,
                    weight: spec.weight,
                    reps: spec.reps,
                    isCompleted: spec.done,
                    completedAt: spec.done ? start.addingTimeInterval(Double(minute) * 60) : nil
                )
                context.insert(set)
                workoutExercise.sets.append(set)
            }
            workout.exercises.append(workoutExercise)
        }
        return workout
    }
}

@Suite("ExerciseRecencyCalculator")
@MainActor
struct ExerciseRecencyTests {
    private let calendar = TrendTestClock.calendar
    private let now = TrendTestClock.now

    private func recency(
        for exercise: Exercise,
        in history: [Workout],
        excluding activeId: UUID? = nil
    ) -> ExerciseRecency {
        ExerciseRecencyCalculator.recency(
            for: exercise,
            history: history,
            excludingWorkoutId: activeId,
            now: now,
            calendar: calendar
        )
    }

    private func sets(_ pairs: (Double, Int)...) -> [RecencySetSpec] {
        pairs.map { RecencySetSpec(weight: $0.0, reps: $0.1) }
    }

    // MARK: - This exercise

    @Test("Last done ignores the in-progress workout")
    func lastDoneIgnoresInProgressWorkout() throws {
        let fixture = try RecencyFixture()
        let pulldown = fixture.exercise("Wide-Grip Lat Pulldown", primary: ["lats"])
        let previous = fixture.workout("Pull A", day: -6, [(pulldown, sets((60, 8), (65, 6)))])
        let active = fixture.workout("Pull B", day: 0, finished: false, [(pulldown, sets((70, 8)))])

        let result = recency(for: pulldown, in: [active, previous], excluding: active.id)

        let session = try #require(result.lastSession)
        #expect(session.date == previous.startedAt)
        #expect(session.workoutName == "Pull A")
        #expect(session.sets == [
            .init(weight: 60, unit: .kg, reps: 8),
            .init(weight: 65, unit: .kg, reps: 6),
        ])
        #expect(result.muscles.first?.lastTrained != nil)
        #expect(result.muscles.first.map { $0.lastTrained! < active.startedAt } == true)
    }

    @Test("An unfinished draft is not history")
    func unfinishedDraftIsNotHistory() throws {
        let fixture = try RecencyFixture()
        let pulldown = fixture.exercise("Wide-Grip Lat Pulldown", primary: ["lats"])
        let completed = fixture.workout("Pull A", day: -6, [(pulldown, sets((60, 8)))])
        let draft = fixture.workout("Saved draft", day: -1, finished: false, [(pulldown, sets((80, 8)))])

        let result = recency(for: pulldown, in: [draft, completed])

        #expect(result.lastSession?.date == completed.startedAt)
    }

    @Test("Only completed sets count as doing the exercise")
    func onlyCompletedSetsCount() throws {
        let fixture = try RecencyFixture()
        let pulldown = fixture.exercise("Wide-Grip Lat Pulldown", primary: ["lats"])
        let older = fixture.workout("Pull A", day: -10, [(pulldown, [
            RecencySetSpec(weight: 60, reps: 8),
            RecencySetSpec(weight: 60, reps: 8, done: false),
        ])])
        fixture.workout("Pull B", day: -3, [(pulldown, [RecencySetSpec(done: false)])])

        let result = recency(for: pulldown, in: fixture.workoutsByRecency())

        let session = try #require(result.lastSession)
        #expect(session.date == older.startedAt)
        #expect(session.sets.count == 1)
    }

    @Test("No history shows never")
    func noHistoryShowsNever() throws {
        let fixture = try RecencyFixture()
        let pulldown = fixture.exercise("Wide-Grip Lat Pulldown", primary: ["lats"])
        let bench = fixture.exercise("Bench Press", primary: ["chest"])
        fixture.workout("Push", day: -2, [(bench, sets((80, 5)))])

        let result = recency(for: pulldown, in: fixture.workoutsByRecency())

        #expect(result.lastSession == nil)
        #expect(result.muscles == [
            .init(name: "lats", lastTrained: nil, viaExercise: nil, setsThisWeek: 0)
        ])
        #expect(ExerciseRecency.relativeDay(nil, now: now, calendar: calendar) == "Never")
    }

    // MARK: - Muscle groups

    @Test("Muscle last trained picks the most recent completed set across exercises")
    func muscleUsesMostRecentExercise() throws {
        let fixture = try RecencyFixture()
        let pulldown = fixture.exercise("Wide-Grip Lat Pulldown", primary: ["lats"])
        let highRow = fixture.exercise("Leverage High Row", primary: ["lats", "middle back"])
        fixture.workout("Pull A", day: -5, [(pulldown, sets((60, 8)))])
        let latest = fixture.workout("Pull B", day: -2, [(highRow, sets((50, 10)))])

        let result = recency(for: pulldown, in: fixture.workoutsByRecency())

        let lats = try #require(result.muscles.first { $0.name == "lats" })
        #expect(lats.viaExercise == "Leverage High Row")
        #expect(try #require(lats.lastTrained) > latest.startedAt)
        #expect(try #require(lats.lastTrained) < latest.startedAt.addingTimeInterval(3_600))
    }

    @Test("Within one workout, the exercise with the later set is credited")
    func laterSetWinsWithinWorkout() throws {
        let fixture = try RecencyFixture()
        let pulldown = fixture.exercise("Wide-Grip Lat Pulldown", primary: ["lats"])
        let highRow = fixture.exercise("Leverage High Row", primary: ["lats", "middle back"])
        fixture.workout("Pull", day: -1, [
            (highRow, sets((50, 10), (50, 10))),
            (pulldown, sets((60, 8), (60, 8))),
        ])

        let result = recency(for: highRow, in: fixture.workoutsByRecency())

        try #require(result.muscles.map(\.name) == ["lats", "middle back"])
        #expect(result.muscles[0].viaExercise == "Wide-Grip Lat Pulldown")
        #expect(result.muscles[1].viaExercise == "Leverage High Row")
    }

    @Test("Secondary-muscle work does not count as training that muscle")
    func secondaryWorkIsNotLastTrained() throws {
        let fixture = try RecencyFixture()
        let pulldown = fixture.exercise("Wide-Grip Lat Pulldown", primary: ["lats"])
        let pullover = fixture.exercise("Dumbbell Pullover", primary: ["chest"], secondary: ["lats"])
        fixture.workout("Pull", day: -9, [(pulldown, sets((60, 8)))])
        fixture.workout("Push", day: -1, [(pullover, sets((30, 12)))])

        let result = recency(for: pulldown, in: fixture.workoutsByRecency())

        #expect(result.muscles.first?.viaExercise == "Wide-Grip Lat Pulldown")
    }

    @Test("Custom exercises use their own muscle fields")
    func customExercisesUseOwnMuscles() throws {
        let fixture = try RecencyFixture()
        let crusher = fixture.exercise("Grip Crusher", primary: ["forearms"], isCustom: true)
        let pinch = fixture.exercise("Plate Pinch", primary: ["forearms"], isCustom: true)
        fixture.workout("Grip day", day: -3, [(pinch, [RecencySetSpec(weight: 20, reps: 30)])])

        let result = recency(for: crusher, in: fixture.workoutsByRecency())

        #expect(result.lastSession == nil)
        #expect(result.muscles.map(\.name) == ["forearms"])
        #expect(result.muscles.first?.viaExercise == "Plate Pinch")
    }

    @Test("Weekly sets count indirect work as half a set")
    func weeklySetsAreFractional() throws {
        let fixture = try RecencyFixture()
        let pulldown = fixture.exercise(
            "Wide-Grip Lat Pulldown", primary: ["lats"], secondary: ["middle back"]
        )
        let highRow = fixture.exercise("Leverage High Row", primary: ["lats", "middle back"])
        let pullover = fixture.exercise("Dumbbell Pullover", primary: ["chest"], secondary: ["lats"])
        // `now` is a Wednesday; the week starts Monday (day -2).
        fixture.workout("Monday pull", day: -2, [
            (pulldown, sets((60, 8), (60, 8), (60, 8)) + [RecencySetSpec(done: false)]),
            (pullover, sets((30, 12), (30, 12))),
        ])
        fixture.workout("Last Friday", day: -5, [(pulldown, sets((60, 8), (60, 8)))])
        let active = fixture.workout("Today", day: 0, finished: false, [(highRow, sets((50, 10)))])

        let result = recency(for: highRow, in: fixture.workoutsByRecency(), excluding: active.id)

        // lats: 3 direct pulldown sets + 2 pullover sets at half = 4.0
        // middle back: 3 pulldown sets at half = 1.5
        #expect(result.muscles.map(\.setsThisWeek) == [4.0, 1.5])
    }

    // MARK: - Formatting

    @Test("Relative day reads naturally", arguments: [
        (0, "Today"), (-1, "Yesterday"), (-6, "6 days ago"), (-13, "13 days ago"),
        (-14, "2 weeks ago"), (-59, "8 weeks ago"), (-60, "2 months ago"), (-800, "2 years ago"),
    ])
    func relativeDay(offset: Int, expected: String) {
        let date = TrendTestClock.day(offset, hour: 7)
        #expect(ExerciseRecency.relativeDay(date, now: now, calendar: calendar) == expected)
    }

    @Test("Session sets summarize as weight × reps with one unit")
    func setSummary() {
        let sets: [ExerciseRecency.SetSummary] = [
            .init(weight: 60, unit: .kg, reps: 8),
            .init(weight: 65, unit: .kg, reps: 6),
        ]
        #expect(ExerciseRecency.summary(of: sets) == "60 × 8, 65 × 6 kg")
    }

    @Test("Bodyweight sets summarize without a unit")
    func bodyweightSetSummary() {
        let sets: [ExerciseRecency.SetSummary] = [
            .init(weight: nil, unit: .kg, reps: 12),
            .init(weight: nil, unit: .kg, reps: 10),
        ]
        #expect(ExerciseRecency.summary(of: sets) == "BW × 12, BW × 10")
    }
}

@Suite("ActiveWorkoutViewModel last done")
@MainActor
struct ActiveWorkoutRecencyTests {
    @Test("A card's last-done info leaves out the session being logged")
    func cardRecencyExcludesActiveSession() async throws {
        let fixture = try RecencyFixture()
        let pulldown = fixture.exercise("Wide-Grip Lat Pulldown", primary: ["lats"])
        fixture.workout("Pull A", day: -6, [(pulldown, [RecencySetSpec()])])
        // A resumed session: unfinished, already holding a completed set.
        let active = fixture.workout("Pull B", day: 0, finished: false, [(pulldown, [RecencySetSpec()])])
        let repository = MockWorkoutRepository()
        repository.workouts = fixture.workoutsByRecency()
        let vm = ActiveWorkoutViewModel(
            resuming: active,
            workoutRepository: repository,
            autoFillService: MockAutoFillService()
        )
        let card = try #require(active.exercises.first)

        let result = try #require(await vm.recency(
            for: card, now: TrendTestClock.now, calendar: TrendTestClock.calendar
        ))

        #expect(result.lastSession?.workoutName == "Pull A")
    }

    @Test("Re-expanding a card does not re-read history")
    func recencyIsCachedPerExercise() async throws {
        let fixture = try RecencyFixture()
        let pulldown = fixture.exercise("Wide-Grip Lat Pulldown", primary: ["lats"])
        let active = fixture.workout("Pull", day: 0, finished: false, [(pulldown, [RecencySetSpec()])])
        let repository = MockWorkoutRepository()
        repository.workouts = [active]
        let vm = ActiveWorkoutViewModel(
            resuming: active,
            workoutRepository: repository,
            autoFillService: MockAutoFillService()
        )
        let card = try #require(active.exercises.first)

        _ = await vm.recency(for: card)
        let second = try #require(await vm.recency(for: card))

        #expect(repository.fetchAllCallCount == 1)
        #expect(second.lastSession == nil)
    }

    @Test("A failed history read shows nothing rather than never")
    func failedReadIsNotNever() async throws {
        let fixture = try RecencyFixture()
        let pulldown = fixture.exercise("Wide-Grip Lat Pulldown", primary: ["lats"])
        let active = fixture.workout("Pull", day: 0, finished: false, [(pulldown, [RecencySetSpec()])])
        let repository = MockWorkoutRepository()
        repository.errorToThrow = NSError(domain: "test", code: 1)
        let vm = ActiveWorkoutViewModel(
            resuming: active,
            workoutRepository: repository,
            autoFillService: MockAutoFillService()
        )
        let card = try #require(active.exercises.first)

        #expect(await vm.recency(for: card) == nil)
    }
}

extension RecencyFixture {
    /// Every workout in the store, newest first, as `fetchAll()` returns them.
    func workoutsByRecency() -> [Workout] {
        let descriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
