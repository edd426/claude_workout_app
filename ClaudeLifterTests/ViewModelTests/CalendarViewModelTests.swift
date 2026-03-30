import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@Suite("CalendarViewModel Tests")
@MainActor
struct CalendarViewModelTests {

    // MARK: - Helpers

    private func makeVM() -> (CalendarViewModel, MockWorkoutRepository) {
        let repo = MockWorkoutRepository()
        let vm = CalendarViewModel(workoutRepository: repo)
        return (vm, repo)
    }

    private func makeWorkoutWithSets(startedAt: Date, setCount: Int) -> Workout {
        let workout = Workout(
            name: "Test Workout",
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(3600)
        )
        for i in 0..<setCount {
            let set = WorkoutSet(order: i, isCompleted: true, completedAt: startedAt)
            let we = WorkoutExercise(order: 0, exercise: TestFixtures.makeExercise())
            we.sets.append(set)
            workout.exercises.append(we)
        }
        return workout
    }

    // MARK: - WorkoutIntensity

    @Test("Intensity: 0 sets -> none")
    func intensityNone() {
        #expect(CalendarViewModel.WorkoutIntensity.from(completedSetCount: 0) == .none)
    }

    @Test("Intensity: 5 sets -> light")
    func intensityLight() {
        #expect(CalendarViewModel.WorkoutIntensity.from(completedSetCount: 5) == .light)
    }

    @Test("Intensity: 1 set -> light (boundary)")
    func intensityLightBoundary() {
        #expect(CalendarViewModel.WorkoutIntensity.from(completedSetCount: 1) == .light)
    }

    @Test("Intensity: 10 sets -> light (upper boundary)")
    func intensityLightUpperBoundary() {
        #expect(CalendarViewModel.WorkoutIntensity.from(completedSetCount: 10) == .light)
    }

    @Test("Intensity: 15 sets -> medium")
    func intensityMedium() {
        #expect(CalendarViewModel.WorkoutIntensity.from(completedSetCount: 15) == .medium)
    }

    @Test("Intensity: 11 sets -> medium (boundary)")
    func intensityMediumBoundary() {
        #expect(CalendarViewModel.WorkoutIntensity.from(completedSetCount: 11) == .medium)
    }

    @Test("Intensity: 20 sets -> medium (upper boundary)")
    func intensityMediumUpperBoundary() {
        #expect(CalendarViewModel.WorkoutIntensity.from(completedSetCount: 20) == .medium)
    }

    @Test("Intensity: 25 sets -> heavy")
    func intensityHeavy() {
        #expect(CalendarViewModel.WorkoutIntensity.from(completedSetCount: 25) == .heavy)
    }

    @Test("Intensity: 21 sets -> heavy (boundary)")
    func intensityHeavyBoundary() {
        #expect(CalendarViewModel.WorkoutIntensity.from(completedSetCount: 21) == .heavy)
    }

    // MARK: - loadMonth

    @Test("loadMonth populates workoutDays with correct intensities")
    func loadMonthPopulatesIntensities() async throws {
        let (vm, repo) = makeVM()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        let lightWorkout = makeWorkoutWithSets(startedAt: today, setCount: 5)
        let heavyWorkout = makeWorkoutWithSets(startedAt: today.addingTimeInterval(-86400), setCount: 25)
        repo.workouts = [lightWorkout, heavyWorkout]

        await vm.loadMonth()

        #expect(vm.workoutDays[today] == .light)
        let yesterday = today.addingTimeInterval(-86400)
        #expect(vm.workoutDays[yesterday] == .heavy)
    }

    @Test("loadMonth with empty month shows all .none")
    func loadMonthEmpty() async {
        let (vm, repo) = makeVM()
        repo.workouts = []

        await vm.loadMonth()

        #expect(vm.workoutDays.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test("loadMonth with error sets errorMessage")
    func loadMonthError() async {
        let (vm, repo) = makeVM()
        repo.errorToThrow = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "fetch failed"])

        await vm.loadMonth()

        #expect(vm.errorMessage != nil)
        #expect(vm.workoutDays.isEmpty)
    }

    @Test("loadMonth accumulates sets from multiple workouts on same day")
    func loadMonthAccumulateSameDay() async {
        let (vm, repo) = makeVM()
        let today = Calendar.current.startOfDay(for: .now)
        let w1 = makeWorkoutWithSets(startedAt: today, setCount: 6)   // 6 sets
        let w2 = makeWorkoutWithSets(startedAt: today.addingTimeInterval(3600), setCount: 6)  // 6 more = 12 total -> medium
        repo.workouts = [w1, w2]

        await vm.loadMonth()

        #expect(vm.workoutDays[today] == .medium)
    }

    // MARK: - nextMonth / previousMonth

    @Test("nextMonth advances currentMonth by one month")
    func nextMonthAdvances() {
        let (vm, _) = makeVM()
        let calendar = Calendar.current
        let before = vm.currentMonth

        vm.nextMonth()

        let expected = calendar.date(byAdding: .month, value: 1, to: before)!
        #expect(calendar.isDate(vm.currentMonth, equalTo: expected, toGranularity: .month))
    }

    @Test("previousMonth rewinds currentMonth by one month")
    func previousMonthRewinds() {
        let (vm, _) = makeVM()
        let calendar = Calendar.current
        let before = vm.currentMonth

        vm.previousMonth()

        let expected = calendar.date(byAdding: .month, value: -1, to: before)!
        #expect(calendar.isDate(vm.currentMonth, equalTo: expected, toGranularity: .month))
    }

    @Test("nextMonth then previousMonth returns to original month")
    func nextThenPreviousReturnsOriginal() {
        let (vm, _) = makeVM()
        let calendar = Calendar.current
        let original = vm.currentMonth

        vm.nextMonth()
        vm.previousMonth()

        #expect(calendar.isDate(vm.currentMonth, equalTo: original, toGranularity: .month))
    }

    // MARK: - selectDate

    @Test("selectDate sets selectedDate and fetches workouts for that day")
    func selectDateFetchesWorkouts() async {
        let (vm, repo) = makeVM()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let workout = makeWorkoutWithSets(startedAt: today, setCount: 3)
        repo.workouts = [workout]

        await vm.selectDate(today)

        #expect(vm.selectedDate != nil)
        #expect(calendar.isDate(vm.selectedDate!, inSameDayAs: today))
        #expect(vm.selectedDayWorkouts.count == 1)
    }

    @Test("selectDate with no workouts returns empty selectedDayWorkouts")
    func selectDateNoWorkouts() async {
        let (vm, repo) = makeVM()
        repo.workouts = []

        await vm.selectDate(.now)

        #expect(vm.selectedDayWorkouts.isEmpty)
    }

    @Test("selectDate only returns completed workouts")
    func selectDateOnlyCompletedWorkouts() async {
        let (vm, repo) = makeVM()
        let today = Calendar.current.startOfDay(for: .now)
        let completed = makeWorkoutWithSets(startedAt: today, setCount: 4)
        let incomplete = Workout(name: "In Progress", startedAt: today, completedAt: nil)
        repo.workouts = [completed, incomplete]

        await vm.selectDate(today)

        #expect(vm.selectedDayWorkouts.count == 1)
    }

    // MARK: - workoutsThisWeek

    @Test("workoutsThisWeek counts completed workouts in current week")
    func workoutsThisWeekCounts() async {
        let (vm, repo) = makeVM()
        let calendar = Calendar.current
        let today = Date.now
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)!.start
        let mondayish = weekStart.addingTimeInterval(86400)  // 1 day into week

        let thisWeek = makeWorkoutWithSets(startedAt: mondayish, setCount: 5)
        let lastWeek = makeWorkoutWithSets(startedAt: weekStart.addingTimeInterval(-86400), setCount: 5)
        repo.workouts = [thisWeek, lastWeek]

        await vm.loadMonth()

        #expect(vm.workoutsThisWeek == 1)
    }

    @Test("workoutsThisWeek is 0 for empty month")
    func workoutsThisWeekZeroWhenEmpty() async {
        let (vm, repo) = makeVM()
        repo.workouts = []

        await vm.loadMonth()

        #expect(vm.workoutsThisWeek == 0)
    }
}
