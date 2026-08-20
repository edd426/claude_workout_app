import Foundation
import Observation

/// The receipt for a workout that has been durably saved.
///
/// This is owned by `AppState` and presented over Home rather than by
/// `ActiveWorkoutView`, and that ownership is the whole point (#123).
/// `AppState.endWorkout()` nils `activeWorkoutVM`, which tears down
/// `ActiveWorkoutView` — so a summary sheet attached to that view could only
/// survive if leaving the workout were postponed until the sheet was
/// dismissed. That is exactly what the old code did, and it meant a
/// swipe-dismissed sheet (there was no `interactiveDismissDisabled`) left the
/// user inside a workout that had already been saved and synced, with a
/// one-way `isFinished` flag that no further Finish tap could re-trigger.
///
/// Handing the receipt to `AppState` breaks that circle: ending the workout and
/// showing the summary become independent, so dismissing the summary any way at
/// all — Done, swipe, or never presenting it — cannot strand anyone.
///
/// A reference type so post-commit PR detection can fill `personalRecords` in
/// after the sheet is already onscreen, without disturbing `sheet(item:)`
/// identity.
@Observable
@MainActor
final class WorkoutCompletionSummary: Identifiable {
    let id: UUID
    let workout: Workout

    /// Populated after the critical save by post-commit PR detection (#125),
    /// so a slow or failing detector never delays the return to Home.
    var personalRecords: [PersonalRecord] = []

    /// Proposed template changes detected after the workout was saved (#129),
    /// for the review card in #130. Nil until detection finishes, and nil
    /// forever for an ad-hoc workout or one whose plan produced nothing —
    /// the card must appear only when there is genuinely something to decide.
    var templateChangeSet: TemplateChangeSet?

    init(workout: Workout) {
        self.id = workout.id
        self.workout = workout
    }
}
