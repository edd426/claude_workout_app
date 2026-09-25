import Foundation

/// Decides when a workout left open should finish itself (report 07B1AD96).
///
/// From the gym, 2026-09-18: "I keep accidentally not clicking finish on my
/// workouts. Can you please design something so that it auto completes after a
/// long period like 3 hours? … It should shorten the metadata for how long the
/// workout was from the first recorded set to the last recorded one."
///
/// The clock runs from the last *logged* set, not from Start, so a long
/// session is never cut off while it is still being trained. The recorded
/// duration becomes first logged set → last logged set, because Start-to-now
/// would count the hours the phone sat in a pocket.
enum WorkoutAutoFinishPolicy {
    /// Three hours without a logged set.
    static let idleThreshold: TimeInterval = 3 * 60 * 60

    /// The window to record for `workout` if it should be finished now, or nil
    /// if it should be left alone.
    ///
    /// Only sets that are ticked AND timestamped count: an unticked set was
    /// never logged, and a ticked one without `completedAt` (legacy or synced
    /// data) carries no evidence of when training stopped. A workout with no
    /// such set is never auto-finished — finishing it would discard it (#69),
    /// and deleting a session stays the user's choice on the Resume card (#75).
    static func window(
        for workout: Workout,
        now: Date,
        idleThreshold: TimeInterval = idleThreshold
    ) -> DateInterval? {
        guard workout.completedAt == nil else { return nil }
        let loggedAt = workout.exercises
            .flatMap(\.sets)
            .filter(\.isCompleted)
            .compactMap(\.completedAt)
        guard
            let first = loggedAt.min(),
            let last = loggedAt.max(),
            now.timeIntervalSince(last) >= idleThreshold
        else { return nil }
        return DateInterval(start: first, end: last)
    }
}
