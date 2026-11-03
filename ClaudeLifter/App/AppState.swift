import Foundation
import Observation

/// The tab bar (1.9.0). Settings is not a tab: it is a sheet from the gear in
/// Today's toolbar, because the HIG reserves the tab bar for navigation and
/// five tabs is the iPhone limit.
enum AppTab: String, CaseIterable, Hashable, Sendable {
    case today, history, body, exercises, coach

    var title: String {
        switch self {
        case .today: "Today"
        case .history: "History"
        case .body: "Body"
        case .exercises: "Exercises"
        case .coach: "Coach"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "house"
        case .history: "calendar"
        case .body: "figure"
        case .exercises: "dumbbell"
        case .coach: "bubble.left.and.bubble.right"
        }
    }
}

@Observable
@MainActor
final class AppState {
    var isWorkoutActive: Bool = false
    var activeWorkoutId: UUID? = nil
    var activeWorkoutVM: ActiveWorkoutViewModel? = nil

    /// The selected tab, so a Today row can hand off to another tab (the Body
    /// row opens the Body tab).
    var selectedTab: AppTab = .today

    /// The receipt for the most recently finished workout, presented over Home.
    ///
    /// It lives here rather than on `ActiveWorkoutView` because `endWorkout()`
    /// tears that view down. Owning it at this level lets the workout end the
    /// instant its save commits, independently of whether the summary is shown
    /// or how it is dismissed (#123).
    var completedWorkoutSummary: WorkoutCompletionSummary? = nil

    func show(_ tab: AppTab) {
        selectedTab = tab
    }

    func startWorkout(id: UUID, vm: ActiveWorkoutViewModel) {
        activeWorkoutId = id
        activeWorkoutVM = vm
        isWorkoutActive = true
        completedWorkoutSummary = nil
    }

    /// Leaves the active workout and, when there is one, publishes its receipt.
    /// Callers that discard a session pass no summary, which also clears any
    /// stale receipt still onscreen.
    func endWorkout(showing summary: WorkoutCompletionSummary? = nil) {
        activeWorkoutId = nil
        activeWorkoutVM = nil
        isWorkoutActive = false
        completedWorkoutSummary = summary
    }
}
