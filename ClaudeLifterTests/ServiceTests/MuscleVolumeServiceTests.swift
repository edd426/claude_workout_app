import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

/// A fixed clock for the weekly-volume tests. The calendar deliberately starts
/// its weeks on Sunday, as a US locale does, to prove the service still
/// starts the week on Monday.
enum VolumeTestClock {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam") ?? .gmt
        calendar.firstWeekday = 1
        return calendar
    }()

    /// 2026-11-`day` at `hour`:`minute` local. 2 November 2026 is a Monday.
    static func date(day: Int, month: Int = 11, hour: Int = 12, minute: Int = 0) -> Date {
        let components = DateComponents(
            year: 2026, month: month, day: day, hour: hour, minute: minute
        )
        return calendar.date(from: components) ?? .distantPast
    }

    /// Wednesday 4 November 2026, noon.
    static let now = date(day: 4)
}

/// Builds workouts in an in-memory store. The container is held here so no
/// model outlives it (the iOS 26.5 container-lifetime trap).
@MainActor
final class VolumeFixture {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try makeTestContainer()
    }

    func exercise(_ name: String, primary: [String], secondary: [String] = []) -> Exercise {
        let exercise = Exercise(name: name, primaryMuscles: primary, secondaryMuscles: secondary)
        context.insert(exercise)
        return exercise
    }

    /// One workout with `done` completed and `notDone` uncompleted sets per entry.
    @discardableResult
    func workout(
        _ name: String = "Session",
        startedAt: Date,
        finished: Bool = true,
        _ entries: [(Exercise?, done: Int, notDone: Int)]
    ) -> Workout {
        let workout = Workout(
            name: name,
            startedAt: startedAt,
            completedAt: finished ? startedAt.addingTimeInterval(3_600) : nil
        )
        context.insert(workout)
        for (order, entry) in entries.enumerated() {
            // A nil entry stands for an exercise deleted from the library,
            // which the nullify rule leaves as a nil reference.
            let workoutExercise = WorkoutExercise(
                order: order, exercise: entry.0 ?? exercise("Deleted", primary: ["chest"])
            )
            if entry.0 == nil { workoutExercise.exercise = nil }
            context.insert(workoutExercise)
            for index in 0..<(entry.done + entry.notDone) {
                let isDone = index < entry.done
                let set = WorkoutSet(
                    order: index, weight: 50, reps: 8,
                    isCompleted: isDone,
                    completedAt: isDone ? startedAt.addingTimeInterval(Double(index) * 120) : nil
                )
                context.insert(set)
                workoutExercise.sets.append(set)
            }
            workout.exercises.append(workoutExercise)
        }
        return workout
    }

    func bench() -> Exercise {
        exercise("Bench Press", primary: ["chest"], secondary: ["triceps", "shoulders"])
    }

    func squat() -> Exercise {
        exercise("Barbell Squat", primary: ["quadriceps"], secondary: ["glutes", "hamstrings"])
    }
}

@Suite("MuscleVolumeService")
@MainActor
struct MuscleVolumeServiceTests {
    private let service = MuscleVolumeService(calendar: VolumeTestClock.calendar)
    private let now = VolumeTestClock.now

    // MARK: Counting

    @Test("A completed set counts 1 for each primary muscle and 0.5 for each secondary")
    func primaryOneSecondaryHalf() throws {
        let fixture = try VolumeFixture()
        let workout = fixture.workout(startedAt: VolumeTestClock.date(day: 2), [(fixture.bench(), 3, 0)])

        let volume = service.weeklyVolume(from: [workout], now: now)

        #expect(volume.sets(for: .chest) == 3)
        #expect(volume.sets(for: .triceps) == 1.5)
        #expect(volume.sets(for: .shoulders) == 1.5)
    }

    @Test("Sets add up across exercises and workouts in the week")
    func setsAccumulate() throws {
        let fixture = try VolumeFixture()
        let bench = fixture.bench()
        let fly = fixture.exercise("Cable Fly", primary: ["chest"])
        let monday = fixture.workout(startedAt: VolumeTestClock.date(day: 2), [(bench, 3, 0), (fly, 2, 0)])
        let tuesday = fixture.workout(startedAt: VolumeTestClock.date(day: 3), [(bench, 2, 0)])

        let volume = service.weeklyVolume(from: [monday, tuesday], now: now)

        #expect(volume.sets(for: .chest) == 7)
        #expect(volume.sets(for: .triceps) == 2.5)
    }

    @Test("Uncompleted sets are excluded")
    func incompleteSetsExcluded() throws {
        let fixture = try VolumeFixture()
        let workout = fixture.workout(startedAt: VolumeTestClock.date(day: 2), [(fixture.bench(), 2, 3)])

        let volume = service.weeklyVolume(from: [workout], now: now)

        #expect(volume.sets(for: .chest) == 2)
        #expect(volume.sets(for: .triceps) == 1)
    }

    @Test("An exercise with no completed sets contributes nothing")
    func exerciseWithNoCompletedSets() throws {
        let fixture = try VolumeFixture()
        let workout = fixture.workout(startedAt: VolumeTestClock.date(day: 2), [(fixture.bench(), 0, 3)])

        let volume = service.weeklyVolume(from: [workout], now: now)

        #expect(volume.sets(for: .chest) == 0)
        #expect(volume.muscles.allSatisfy { $0.contributions.isEmpty })
    }

    @Test("Drafts are excluded: a workout without completedAt counts nothing")
    func draftsExcluded() throws {
        let fixture = try VolumeFixture()
        let draft = fixture.workout(
            startedAt: VolumeTestClock.date(day: 3), finished: false, [(fixture.bench(), 4, 0)]
        )

        let volume = service.weeklyVolume(from: [draft], now: now)

        #expect(volume.sets(for: .chest) == 0)
        #expect(volume.hasAnySets == false)
    }

    @Test("A muscle listed as both primary and secondary counts once, as primary")
    func primaryWinsOverSecondary() throws {
        let fixture = try VolumeFixture()
        let odd = fixture.exercise("Odd Press", primary: ["chest"], secondary: ["chest", "triceps"])
        let workout = fixture.workout(startedAt: VolumeTestClock.date(day: 2), [(odd, 2, 0)])

        let volume = service.weeklyVolume(from: [workout], now: now)

        #expect(volume.sets(for: .chest) == 2)
        #expect(volume.muscles.first { $0.muscle == .chest }?.contributions.count == 1)
    }

    @Test("A set whose exercise was deleted is skipped")
    func missingExerciseSkipped() throws {
        let fixture = try VolumeFixture()
        let workout = fixture.workout(startedAt: VolumeTestClock.date(day: 2), [(nil, 3, 0)])

        let volume = service.weeklyVolume(from: [workout], now: now)

        #expect(volume.hasAnySets == false)
    }

    // MARK: Week boundaries

    @Test("The week starts Monday 00:00 local even when the calendar starts on Sunday")
    func weekStartsMonday() {
        let week = service.week(containing: now)

        #expect(week.start == VolumeTestClock.date(day: 2, hour: 0))
        #expect(week.end == VolumeTestClock.date(day: 9, hour: 0))
    }

    @Test("Sunday 23:59 belongs to last week; Monday 00:00 to this week")
    func mondayMidnightBoundary() throws {
        let fixture = try VolumeFixture()
        let bench = fixture.bench()
        let sundayNight = fixture.workout(
            startedAt: VolumeTestClock.date(day: 1, hour: 23, minute: 59), [(bench, 5, 0)]
        )
        let mondayMidnight = fixture.workout(
            startedAt: VolumeTestClock.date(day: 2, hour: 0), [(bench, 2, 0)]
        )

        let volume = service.weeklyVolume(from: [sundayNight, mondayMidnight], now: now)

        #expect(volume.sets(for: .chest) == 2)
    }

    @Test("On Sunday night the week still includes Monday and Sunday, and not the next Monday")
    func sundayNightIncludesWholeWeek() throws {
        let fixture = try VolumeFixture()
        let bench = fixture.bench()
        let workouts = [
            fixture.workout(startedAt: VolumeTestClock.date(day: 2, hour: 6), [(bench, 1, 0)]),
            fixture.workout(startedAt: VolumeTestClock.date(day: 8, hour: 20), [(bench, 2, 0)]),
            fixture.workout(startedAt: VolumeTestClock.date(day: 9, hour: 0), [(bench, 4, 0)]),
        ]

        let volume = service.weeklyVolume(
            from: workouts, now: VolumeTestClock.date(day: 8, hour: 23, minute: 30)
        )

        #expect(volume.sets(for: .chest) == 3)
    }

    @Test("A session that starts Sunday night stays in that week, even if it ends on Monday")
    func sessionPastMidnightStaysInStartWeek() throws {
        let fixture = try VolumeFixture()
        let late = fixture.workout(
            startedAt: VolumeTestClock.date(day: 1, hour: 23, minute: 40), [(fixture.bench(), 3, 0)]
        )

        let volume = service.weeklyVolume(from: [late], now: now)

        #expect(volume.sets(for: .chest) == 0)
    }

    @Test("Older history is ignored")
    func olderHistoryIgnored() throws {
        let fixture = try VolumeFixture()
        let old = fixture.workout(
            startedAt: VolumeTestClock.date(day: 20, month: 10), [(fixture.bench(), 6, 0)]
        )

        let volume = service.weeklyVolume(from: [old], now: now)

        #expect(volume.hasAnySets == false)
    }

    // MARK: Muscle mapping

    @Test("Catalog names and aliases map onto tracked muscles", arguments: [
        ("chest", [TrackedMuscle.chest]),
        ("middle back", [.middleBack]),
        ("Quadriceps", [.quadriceps]),
        (" lats ", [.lats]),
        ("abs", [.abdominals]),
        ("quads", [.quadriceps]),
        ("back", [.lats, .middleBack]),
        ("forearms", []),
        ("lower back", []),
        ("traps", []),
        ("abductors", []),
        ("neck", []),
    ])
    func mapping(name: String, expected: [TrackedMuscle]) {
        #expect(TrackedMuscle.from(catalogName: name) == expected)
    }

    @Test("Every tracked muscle appears, untrained ones at zero, in tracked order")
    func everyMusclePresent() throws {
        let fixture = try VolumeFixture()
        let workout = fixture.workout(startedAt: VolumeTestClock.date(day: 2), [(fixture.squat(), 3, 0)])

        let volume = service.weeklyVolume(from: [workout], now: now)

        #expect(volume.muscles.map(\.muscle) == TrackedMuscle.allCases)
        #expect(volume.muscles.count == 12)
        #expect(volume.sets(for: .calves) == 0)
        #expect(volume.sets(for: .hamstrings) == 1.5)
    }

    @Test("Untracked muscles add nothing anywhere")
    func untrackedIgnored() throws {
        let fixture = try VolumeFixture()
        let curl = fixture.exercise("Wrist Curl", primary: ["forearms"], secondary: ["lower back"])
        let workout = fixture.workout(startedAt: VolumeTestClock.date(day: 2), [(curl, 4, 0)])

        let volume = service.weeklyVolume(from: [workout], now: now)

        #expect(volume.hasAnySets == false)
    }

    // MARK: Contributions

    @Test("Contributions record the exercise, the workout, the role and the sets, oldest first")
    func contributions() throws {
        let fixture = try VolumeFixture()
        let squat = fixture.squat()
        let rdl = fixture.exercise("Romanian Deadlift", primary: ["hamstrings"], secondary: ["glutes"])
        let wednesday = fixture.workout("Legs 2", startedAt: VolumeTestClock.date(day: 4, hour: 6), [(rdl, 3, 0)])
        let monday = fixture.workout("Legs 1", startedAt: VolumeTestClock.date(day: 2, hour: 6), [(squat, 4, 1)])

        let volume = service.weeklyVolume(from: [wednesday, monday], now: now)
        let hamstrings = try #require(volume.muscles.first { $0.muscle == .hamstrings })

        #expect(hamstrings.sets == 5)
        #expect(hamstrings.contributions.map(\.exerciseName) == ["Barbell Squat", "Romanian Deadlift"])
        #expect(hamstrings.contributions.map(\.workoutName) == ["Legs 1", "Legs 2"])
        #expect(hamstrings.contributions.map(\.role) == [.secondary, .primary])
        #expect(hamstrings.contributions.map(\.completedSets) == [4, 3])
        #expect(hamstrings.contributions.map(\.sets) == [2, 3])
    }

    // MARK: Thresholds and the card

    @Test("Under-minimum is strictly below 4 sets; the target band is 6–10 inclusive")
    func thresholds() throws {
        let fixture = try VolumeFixture()
        let fly = fixture.exercise("Cable Fly", primary: ["chest"])
        let curl = fixture.exercise("Curl", primary: ["biceps"])
        let pushdown = fixture.exercise("Pushdown", primary: ["triceps"])
        let workout = fixture.workout(
            startedAt: VolumeTestClock.date(day: 2), [(fly, 4, 0), (curl, 6, 0), (pushdown, 11, 0)]
        )

        let volume = service.weeklyVolume(from: [workout], now: now)
        let chest = try #require(volume.muscles.first { $0.muscle == .chest })
        let biceps = try #require(volume.muscles.first { $0.muscle == .biceps })
        let triceps = try #require(volume.muscles.first { $0.muscle == .triceps })

        #expect(chest.isUnderMinimum == false)
        #expect(chest.isInTargetBand == false)
        #expect(biceps.isInTargetBand)
        #expect(triceps.isInTargetBand == false)
        #expect(MuscleVolumeTargets.minimumSets == 4)
        #expect(MuscleVolumeTargets.targetBand == 6...10)
    }

    @Test("Muscles under the minimum are listed lowest first, ties in tracked order")
    func underMinimumOrder() throws {
        let fixture = try VolumeFixture()
        let workout = fixture.workout(
            startedAt: VolumeTestClock.date(day: 2),
            [
                (fixture.exercise("Leg Curl", primary: ["hamstrings"]), 2, 0),
                (fixture.exercise("Hip Thrust", primary: ["glutes"]), 3, 0),
                (fixture.exercise("Fly", primary: ["chest"]), 5, 0),
            ]
        )

        let volume = service.weeklyVolume(from: [workout], now: now)
        let under = volume.underMinimum.map(\.muscle)

        #expect(under.first == .lats)
        #expect(Array(under.suffix(2)) == [.hamstrings, .glutes])
        #expect(under.contains(.chest) == false)
        #expect(under.count == 11)
    }

    @Test("The card names the lowest muscles and folds the rest into +N more")
    func cardSummaryUnder() throws {
        let fixture = try VolumeFixture()
        let everything = TrackedMuscle.allCases.map { muscle -> (Exercise?, done: Int, notDone: Int) in
            let sets: Int
            switch muscle {
            case .calves: sets = 0
            case .hamstrings: sets = 2
            case .glutes: sets = 3
            case .abdominals: sets = 1
            default: sets = 6
            }
            return (fixture.exercise("\(muscle)", primary: [muscle.rawValue]), sets, 0)
        }
        let workout = fixture.workout(startedAt: VolumeTestClock.date(day: 2), everything)

        let volume = service.weeklyVolume(from: [workout], now: now)

        #expect(volume.cardSummary(maxNames: 2) == "Under 4 sets: Calves 0 · Abs 1 · +2 more")
        #expect(volume.cardSummary(maxNames: 4) == "Under 4 sets: Calves 0 · Abs 1 · Hamstrings 2 · Glutes 3")
    }

    @Test("Half sets read as 1.5, not 1.50")
    func cardSummaryHalves() throws {
        let fixture = try VolumeFixture()
        let workout = fixture.workout(startedAt: VolumeTestClock.date(day: 2), [(fixture.squat(), 3, 0)])

        let volume = service.weeklyVolume(from: [workout], now: now)

        #expect(WeeklyMuscleVolume.format(1.5) == "1.5")
        #expect(WeeklyMuscleVolume.format(2) == "2")
        #expect(volume.cardSummary(maxNames: 20).contains("Hamstrings 1.5"))
    }

    @Test("When no muscle is under 4 the card says so")
    func cardSummaryAllMet() throws {
        let fixture = try VolumeFixture()
        let entries = TrackedMuscle.allCases.map { muscle -> (Exercise?, done: Int, notDone: Int) in
            (fixture.exercise("\(muscle)", primary: [muscle.rawValue]), 4, 0)
        }
        let workout = fixture.workout(startedAt: VolumeTestClock.date(day: 2), entries)

        let volume = service.weeklyVolume(from: [workout], now: now)

        #expect(volume.underMinimum.isEmpty)
        #expect(volume.cardSummary() == "All muscles ≥ 4 sets this week")
    }

    @Test("The chart's VoiceOver summary names the gaps, the band and the top muscle")
    func accessibilitySummary() throws {
        let fixture = try VolumeFixture()
        let entries = TrackedMuscle.allCases.map { muscle -> (Exercise?, done: Int, notDone: Int) in
            let sets: Int
            switch muscle {
            case .calves: sets = 0
            case .hamstrings: sets = 2
            case .chest: sets = 9
            default: sets = 5
            }
            return (fixture.exercise("\(muscle)", primary: [muscle.rawValue]), sets, 0)
        }
        let workout = fixture.workout(startedAt: VolumeTestClock.date(day: 2), entries)

        let volume = service.weeklyVolume(from: [workout], now: now)

        #expect(volume.accessibilitySummary
            == "2 of 12 muscles under 4 sets. Lowest: Calves 0, Hamstrings 2. 1 in the 6 to 10 range. Most: Chest 9.")
    }

    @Test("An empty week has no sets to show")
    func emptyWeek() {
        let volume = service.weeklyVolume(from: [], now: now)

        #expect(volume.hasAnySets == false)
        #expect(volume.underMinimum.count == 12)
    }
}
