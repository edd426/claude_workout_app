import Foundation
import Observation

@Observable
@MainActor
final class CalendarViewModel {
    var currentMonth: Date = .now
    var workoutDays: [Date: WorkoutIntensity] = [:]
    /// Finished workouts and completed sets per day (start of day), for the
    /// day cells' VoiceOver labels (UI-A5).
    var daySummaries: [Date: DaySummary] = [:]
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

    struct DaySummary: Equatable, Sendable {
        let workouts: Int
        let sets: Int
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
            daySummaries = buildDaySummaries(from: workouts)
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

    /// "Thursday 8 October, 1 workout, 12 sets" (UI-A5).
    static func accessibilityLabel(
        for date: Date,
        summary: DaySummary?,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar)
        style.timeZone = calendar.timeZone
        let day = date.formatted(style.weekday(.wide).day().month(.wide))
            .replacingOccurrences(of: ",", with: "")
        guard let summary, summary.workouts > 0 else { return "\(day), no workout" }
        let workouts = summary.workouts == 1 ? "1 workout" : "\(summary.workouts) workouts"
        let sets = summary.sets == 1 ? "1 set" : "\(summary.sets) sets"
        return "\(day), \(workouts), \(sets)"
    }

    // MARK: - Private helpers

    private func buildDaySummaries(from workouts: [Workout]) -> [Date: DaySummary] {
        var summaries: [Date: DaySummary] = [:]
        for workout in workouts where workout.completedAt != nil {
            let day = calendar.startOfDay(for: workout.startedAt)
            let sets = workout.exercises.flatMap(\.sets).filter(\.isCompleted).count
            let current = summaries[day] ?? DaySummary(workouts: 0, sets: 0)
            summaries[day] = DaySummary(workouts: current.workouts + 1, sets: current.sets + sets)
        }
        return summaries
    }

    private func monthDateRange(for date: Date) -> (start: Date, end: Date) {
        // Non-nil under the Gregorian calendar, but `Calendar` makes no such
        // promise in general and the style rules ban force unwraps in
        // production code (#93). Falling back to the day containing `date`
        // renders a degraded month rather than crashing the History tab.
        guard
            let start = calendar.date(
                from: calendar.dateComponents([.year, .month], from: date)
            ),
            let end = calendar.date(
                byAdding: DateComponents(month: 1, second: -1), to: start
            )
        else {
            let dayStart = calendar.startOfDay(for: date)
            return (dayStart, dayStart.addingTimeInterval(86_400 - 1))
        }
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
