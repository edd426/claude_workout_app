import Foundation

/// The muscles the weekly volume card tracks (issue #168). Raw values are the
/// exercise catalog's own muscle names (free-exercise-db), so most names map
/// straight across; `init(catalogName:)` holds the few aliases.
enum TrackedMuscle: String, CaseIterable, Sendable, Identifiable {
    case chest
    case lats
    case middleBack = "middle back"
    case shoulders
    case biceps
    case triceps
    case quadriceps
    case hamstrings
    case glutes
    case calves
    case abdominals
    case adductors

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .middleBack: "Middle back"
        case .quadriceps: "Quads"
        case .abdominals: "Abs"
        default: rawValue.capitalized
        }
    }

    /// The one mapping table from an exercise's muscle names onto tracked
    /// muscles. Catalog names map to themselves. The aliases cover the custom
    /// exercise picker ("abs", "back") and common shorthand. Untracked catalog
    /// muscles (forearms, traps, lower back, neck, abductors) map to nothing.
    static func from(catalogName name: String) -> [TrackedMuscle] {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let direct = TrackedMuscle(rawValue: key) { return [direct] }
        switch key {
        case "abs", "core": return [.abdominals]
        case "quads": return [.quadriceps]
        case "delts", "deltoids": return [.shoulders]
        case "pecs": return [.chest]
        // The custom-exercise picker offers a single "back"; it trains both.
        case "back", "upper back": return [.lats, .middleBack]
        default: return []
        }
    }
}

/// Weekly set targets per muscle (issue #168). Constants, not settings.
///
/// Sources: Pelland et al. 2025, a dose-response meta-regression of weekly
/// set volume and hypertrophy (about 4 sets a week is the floor for a useful
/// effect, and 6–10 the most efficient range), and the 2026 ACSM position
/// stand on resistance training, which favours 10 or more for maximal growth.
enum MuscleVolumeTargets {
    static let minimumSets: Double = 4
    static let targetBand: ClosedRange<Double> = 6...10
}

/// Completed sets per tracked muscle in one Monday-to-Sunday week.
///
/// Value types only, so a view can hold one across a SwiftData save.
struct WeeklyMuscleVolume: Equatable, Sendable {
    enum Role: String, Equatable, Sendable {
        case primary, secondary
    }

    /// One exercise in one workout, as it counted towards one muscle.
    struct Contribution: Equatable, Sendable, Identifiable {
        let id: String
        let exerciseName: String
        let workoutName: String
        let date: Date
        let completedSets: Int
        let role: Role

        /// 1 per completed set when the muscle is primary, 0.5 when secondary.
        var sets: Double {
            role == .primary ? Double(completedSets) : Double(completedSets) * 0.5
        }
    }

    struct Muscle: Equatable, Sendable, Identifiable {
        let muscle: TrackedMuscle
        let sets: Double
        /// Oldest first, so the list reads Monday to Sunday.
        let contributions: [Contribution]

        var id: String { muscle.id }
        var isUnderMinimum: Bool { sets < MuscleVolumeTargets.minimumSets }
        var isInTargetBand: Bool { MuscleVolumeTargets.targetBand.contains(sets) }
    }

    /// Monday 00:00 local to the next Monday 00:00.
    let week: DateInterval
    /// Every tracked muscle, in `TrackedMuscle.allCases` order, zero included.
    let muscles: [Muscle]

    var hasAnySets: Bool { muscles.contains { $0.sets > 0 } }

    /// Muscles under the minimum, lowest first; ties keep the tracked order.
    var underMinimum: [Muscle] {
        muscles.enumerated()
            .filter { $0.element.isUnderMinimum }
            .sorted { ($0.element.sets, $0.offset) < ($1.element.sets, $1.offset) }
            .map(\.element)
    }

    func sets(for muscle: TrackedMuscle) -> Double {
        muscles.first { $0.muscle == muscle }?.sets ?? 0
    }

    /// The card's text, at most two lines: "Under 4 sets: Calves 0 ·
    /// Hamstrings 2 · +3 more", or "All muscles ≥ 4 sets this week".
    func cardSummary(maxNames: Int = 3) -> String {
        let under = underMinimum
        let minimum = Self.format(MuscleVolumeTargets.minimumSets)
        guard !under.isEmpty else { return "All muscles ≥ \(minimum) sets this week" }
        var parts = under.prefix(maxNames).map { "\($0.muscle.displayName) \(Self.format($0.sets))" }
        if under.count > maxNames {
            parts.append("+\(under.count - maxNames) more")
        }
        return "Under \(minimum) sets: " + parts.joined(separator: " · ")
    }

    /// The detail chart for VoiceOver (UI-A4): "5 of 12 muscles under 4
    /// sets. Lowest: Calves 0, Abs 1, Hamstrings 2. 4 in the 6 to 10 range.
    /// Most: Chest 9."
    var accessibilitySummary: String {
        let under = underMinimum
        let lowest = under.prefix(3)
            .map { "\($0.muscle.displayName) \(Self.format($0.sets))" }
            .joined(separator: ", ")
        let inBand = muscles.filter(\.isInTargetBand).count
        var parts = ["\(under.count) of \(muscles.count) muscles under \(Self.format(MuscleVolumeTargets.minimumSets)) sets"]
        if !lowest.isEmpty { parts.append("Lowest: \(lowest)") }
        parts.append("\(inBand) in the 6 to 10 range")
        if let top = muscles.max(by: { $0.sets < $1.sets }), top.sets > 0 {
            parts.append("Most: \(top.muscle.displayName) \(Self.format(top.sets))")
        }
        return parts.joined(separator: ". ") + "."
    }

    /// "2", "1.5". Set counts are whole or halves.
    static func format(_ sets: Double) -> String {
        sets.formatted(.number.grouping(.never).precision(.fractionLength(0...1)))
    }
}

protocol MuscleVolumeCalculating {
    @MainActor
    func weeklyVolume(from workouts: [Workout], now: Date) -> WeeklyMuscleVolume
}

/// Counts completed sets per muscle for the current local calendar week
/// (issue #168).
///
/// - The week starts Monday 00:00 local, whatever the locale's first weekday.
/// - Only finished workouts count: a draft has no `completedAt`.
/// - A workout belongs to the week it started in, the same rule as the
///   "last done" panel (#167), so a session that runs past midnight on
///   Sunday stays in one week.
/// - Only completed sets count: 1 for each primary muscle of the exercise,
///   0.5 for each secondary muscle. A muscle listed as both counts once, as
///   primary.
struct MuscleVolumeService: MuscleVolumeCalculating {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        var monday = calendar
        monday.firstWeekday = 2
        self.calendar = monday
    }

    func week(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 86_400)
    }

    @MainActor
    func weeklyVolume(from workouts: [Workout], now: Date) -> WeeklyMuscleVolume {
        let week = week(containing: now)
        var contributions: [TrackedMuscle: [WeeklyMuscleVolume.Contribution]] = [:]
        let inWeek = workouts.filter {
            $0.completedAt != nil && $0.startedAt >= week.start && $0.startedAt < week.end
        }
        for workout in inWeek {
            for workoutExercise in workout.exercises {
                for (muscle, contribution) in Self.contributions(of: workoutExercise, in: workout) {
                    contributions[muscle, default: []].append(contribution)
                }
            }
        }
        let muscles = TrackedMuscle.allCases.map { muscle in
            let list = (contributions[muscle] ?? []).sorted { $0.date < $1.date }
            return WeeklyMuscleVolume.Muscle(
                muscle: muscle,
                sets: list.reduce(0) { $0 + $1.sets },
                contributions: list
            )
        }
        return WeeklyMuscleVolume(week: week, muscles: muscles)
    }

    @MainActor
    private static func contributions(
        of workoutExercise: WorkoutExercise,
        in workout: Workout
    ) -> [(TrackedMuscle, WeeklyMuscleVolume.Contribution)] {
        guard let exercise = workoutExercise.exercise else { return [] }
        let completed = workoutExercise.sets.filter(\.isCompleted).count
        guard completed > 0 else { return [] }
        let primaries = Set(exercise.primaryMuscles.flatMap(TrackedMuscle.from(catalogName:)))
        let secondaries = Set(exercise.secondaryMuscles.flatMap(TrackedMuscle.from(catalogName:)))
            .subtracting(primaries)
        let roles = primaries.map { ($0, WeeklyMuscleVolume.Role.primary) }
            + secondaries.map { ($0, WeeklyMuscleVolume.Role.secondary) }
        return roles.map { muscle, role in
            (muscle, WeeklyMuscleVolume.Contribution(
                id: "\(workoutExercise.id.uuidString)-\(muscle.rawValue)",
                exerciseName: exercise.name,
                workoutName: workout.name,
                date: workout.startedAt,
                completedSets: completed,
                role: role
            ))
        }
    }
}
