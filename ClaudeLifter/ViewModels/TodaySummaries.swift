import Foundation

/// Picks the hero card's workout on the Today screen (1.9.0).
///
/// Templates in the v3 program are named for their weekday ("Mon · Legs 1
/// (squat)" … "Fri · Machines (optional)"). The one named for today wins. On a
/// weekend, or when no name matches, the least recently done template is
/// offered instead, which is what a rotation would pick next.
enum TodayTemplatePicker {
    /// English weekday names in `Calendar` order: index 0 is weekday 1, Sunday.
    private static let weekdayNames = [
        "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
    ]

    /// The weekday (1 = Sunday … 7 = Saturday) a template's first word names,
    /// or nil. The word must be at least three letters and a prefix of a
    /// weekday: "Mon", "Tues", "Thurs" and "Wednesday" match; "Mo",
    /// "Monster" and "Sunrise" do not.
    static func weekday(named name: String) -> Int? {
        let word = name
            .trimmingCharacters(in: .whitespaces)
            .prefix { $0.isLetter }
            .lowercased()
        guard word.count >= 3 else { return nil }
        return weekdayNames.firstIndex { $0.hasPrefix(word) }.map { $0 + 1 }
    }

    static func pick(
        from templates: [WorkoutTemplate],
        lastDone: [UUID: Date],
        now: Date,
        calendar: Calendar
    ) -> WorkoutTemplate? {
        let today = calendar.component(.weekday, from: now)
        let todays = templates.filter { weekday(named: $0.name) == today }
        return leastRecentlyDone(todays.isEmpty ? templates : todays, lastDone: lastDone)
    }

    /// Never-done templates count as the least recent. Ties keep list order.
    private static func leastRecentlyDone(
        _ templates: [WorkoutTemplate],
        lastDone: [UUID: Date]
    ) -> WorkoutTemplate? {
        templates.enumerated().min { lhs, rhs in
            let left = lastDone[lhs.element.id] ?? .distantPast
            let right = lastDone[rhs.element.id] ?? .distantPast
            return (left, lhs.offset) < (right, rhs.offset)
        }?.element
    }

    /// "4 exercises · last done 6 days ago", or "· not done yet".
    static func subtitle(
        exerciseCount: Int,
        lastDone: Date?,
        now: Date,
        calendar: Calendar
    ) -> String {
        let exercises = exerciseCount == 1 ? "1 exercise" : "\(exerciseCount) exercises"
        guard let lastDone else { return "\(exercises) · not done yet" }
        let age = ExerciseRecency.relativeDay(lastDone, now: now, calendar: calendar)
        return "\(exercises) · last done \(age.lowercased())"
    }
}

/// When each template was last done, derived from the workout history
/// (issue #176). The stored `WorkoutTemplate.lastPerformedAt` is not updated
/// on every finish path, so it drifts: Upper A read "2 months ago" a week
/// after it ran.
enum TemplateLastDone {
    /// The start of the latest finished workout for each template id. Drafts
    /// and ad-hoc workouts are skipped.
    static func dates(from workouts: [Workout]) -> [UUID: Date] {
        var latest: [UUID: Date] = [:]
        for workout in workouts where workout.completedAt != nil {
            guard let templateId = workout.templateId else { continue }
            if (latest[templateId] ?? .distantPast) < workout.startedAt {
                latest[templateId] = workout.startedAt
            }
        }
        return latest
    }

    /// The derived date; the stored one only when no finished workout names
    /// the template, because then it is the only evidence there is.
    static func date(for template: WorkoutTemplate, in dates: [UUID: Date]) -> Date? {
        dates[template.id] ?? template.lastPerformedAt
    }
}

/// The Today "Needs you" row: pending approvals and open reports merged into
/// one line (UI-P2). Acknowledged reports are waiting on an install, not on
/// him, so they don't count.
struct NeedsYouSummary: Equatable, Sendable {
    let pendingApprovals: Int
    let openReports: Int

    /// Nil when there is nothing to do, so the row does not render.
    static func make(pendingApprovals: Int, openReports: Int) -> NeedsYouSummary? {
        let summary = NeedsYouSummary(
            pendingApprovals: max(pendingApprovals, 0),
            openReports: max(openReports, 0)
        )
        return summary.total > 0 ? summary : nil
    }

    var total: Int { pendingApprovals + openReports }

    var approvalsText: String? {
        switch pendingApprovals {
        case 0: nil
        case 1: "1 change to approve"
        default: "\(pendingApprovals) changes to approve"
        }
    }

    var reportsText: String? {
        switch openReports {
        case 0: nil
        case 1: "1 open report"
        default: "\(openReports) open reports"
        }
    }

    var title: String {
        [approvalsText, reportsText].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The Today "Body" row: "87.9 kg · 2 days ago · on pace".
enum TodayBodySummary {
    /// A reading this many days old or more is flagged stale (#115).
    static let staleAfterDays = 7

    static func line(
        weight: Double,
        unit: WeightUnit,
        recordedAt: Date,
        status: WeightGoalStatus?,
        goalPercentPerWeek: Double?,
        now: Date,
        calendar: Calendar
    ) -> String {
        let number = weight.formatted(.number.grouping(.never).precision(.fractionLength(1)))
        let age = ExerciseRecency.relativeDay(recordedAt, now: now, calendar: calendar).lowercased()
        var parts = ["\(number) \(unit.rawValue)", age]
        if let status {
            parts.append(paceText(status, holding: goalPercentPerWeek == 0))
        }
        return parts.joined(separator: " · ")
    }

    static func paceText(_ status: WeightGoalStatus, holding: Bool) -> String {
        switch status {
        case .onTrack: "on pace"
        case .tooFast where holding: "off goal"
        case .tooFast: "faster than goal"
        case .tooSlow: "slower than goal"
        }
    }

    static func isStale(recordedAt: Date, now: Date, calendar: Calendar) -> Bool {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: recordedAt),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        return days >= staleAfterDays
    }
}
