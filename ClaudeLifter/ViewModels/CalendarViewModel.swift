import Foundation
import Observation

@Observable
@MainActor
final class CalendarViewModel {
    var currentMonth: Date = .now
    var workoutDays: [Date: WorkoutIntensity] = [:]
    var selectedDate: Date? = nil
    var selectedDayWorkouts: [Workout] = []
    var workoutsThisWeek: Int = 0
    var errorMessage: String? = nil

    enum WorkoutIntensity: Int, Comparable {
        case none = 0, light = 1, medium = 2, heavy = 3

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        static func from(completedSetCount: Int) -> WorkoutIntensity {
            switch completedSetCount {
            case 0: return .none
            case 1...10: return .light
            case 11...20: return .medium
            default: return .heavy
            }
        }
    }

    private let workoutRepository: any WorkoutRepository
    private let calendar = Calendar.current

    init(workoutRepository: any WorkoutRepository) {
        self.workoutRepository = workoutRepository
    }

    func loadMonth() async {
        errorMessage = nil
        let range = monthDateRange(for: currentMonth)
        do {
            let workouts = try await workoutRepository.fetchByDateRange(from: range.start, to: range.end)
            workoutDays = buildIntensityMap(from: workouts, in: range)
            workoutsThisWeek = countWorkoutsThisWeek(from: workouts)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectDate(_ date: Date) async {
        selectedDate = date
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
        do {
            let workouts = try await workoutRepository.fetchByDateRange(from: dayStart, to: dayEnd)
            selectedDayWorkouts = workouts.filter { $0.completedAt != nil }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func nextMonth() {
        guard let next = calendar.date(byAdding: .month, value: 1, to: currentMonth) else { return }
        currentMonth = next
        Task { await loadMonth() }
    }

    func previousMonth() {
        guard let prev = calendar.date(byAdding: .month, value: -1, to: currentMonth) else { return }
        currentMonth = prev
        Task { await loadMonth() }
    }

    // MARK: - Private helpers

    private func monthDateRange(for date: Date) -> (start: Date, end: Date) {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start)!
        return (start, end)
    }

    private func buildIntensityMap(from workouts: [Workout], in range: (start: Date, end: Date)) -> [Date: WorkoutIntensity] {
        var map: [Date: Int] = [:]
        for workout in workouts where workout.completedAt != nil {
            let day = calendar.startOfDay(for: workout.startedAt)
            let totalSets = workout.exercises.flatMap { $0.sets }.filter { $0.isCompleted }.count
            map[day, default: 0] += totalSets
        }
        return map.mapValues { WorkoutIntensity.from(completedSetCount: $0) }
    }

    private func countWorkoutsThisWeek(from workouts: [Workout]) -> Int {
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return 0 }
        let weekEnd = Date.now
        return workouts.filter { w in
            guard w.completedAt != nil else { return false }
            return w.startedAt >= weekStart && w.startedAt <= weekEnd
        }.count
    }
}
