import Foundation
import Observation

@Observable
@MainActor
final class HomeViewModel {
    var templates: [WorkoutTemplate] = []
    var isLoading = false
    var errorMessage: String? = nil

    private let templateRepository: any TemplateRepository
    private let workoutRepository: (any WorkoutRepository)?

    init(templateRepository: any TemplateRepository, workoutRepository: (any WorkoutRepository)? = nil) {
        self.templateRepository = templateRepository
        self.workoutRepository = workoutRepository
    }

    func loadTemplates() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            templates = try await templateRepository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createAdHocWorkout() async throws -> Workout {
        guard let workoutRepository else {
            throw HomeViewModelError.noWorkoutRepository
        }
        let workout = Workout(name: "Quick Workout", startedAt: .now, templateId: nil)
        try await workoutRepository.save(workout)
        return workout
    }

    @discardableResult
    func dismissInsight(
        _ insight: ProactiveInsight,
        using repository: any InsightRepository
    ) async -> Bool {
        errorMessage = nil
        do {
            try await repository.markAsRead(insight)
            return true
        } catch {
            errorMessage = "Could not dismiss this insight. Try again."
            return false
        }
    }

    // MARK: - Crash recovery (#75)

    /// The most recent in-progress workout with actual content, surfaced on
    /// the Home screen with a Resume/Discard prompt. Nil when there is
    /// nothing to recover.
    var resumableWorkout: Workout? = nil

    /// Detects a crash-orphaned or draft-saved in-progress workout
    /// (`completedAt == nil`) so Home can offer Resume / Discard. Empty
    /// ghost sessions are ignored — start-workout cleanup handles those.
    func checkForResumableWorkout() async {
        guard let workoutRepository else { return }
        do {
            let all = try await workoutRepository.fetchAll()
            resumableWorkout = all
                .filter { $0.completedAt == nil && !$0.isEmptyGhostSession }
                .max { $0.startedAt < $1.startedAt }
        } catch {
            // Non-fatal: Home still works without resume detection.
            resumableWorkout = nil
        }
    }

    /// Deletes exactly the surfaced draft — only ever called after the
    /// user's explicit Discard choice — then surfaces the next lingering
    /// draft, if any.
    func discardResumableWorkout() async {
        guard let workout = resumableWorkout, let workoutRepository else { return }
        do {
            try await workoutRepository.delete(workout)
            resumableWorkout = nil
            await checkForResumableWorkout()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum HomeViewModelError: Error {
    case noWorkoutRepository
}

@Observable
@MainActor
final class InboxApprovalViewModel {
    private(set) var approvals: [InboxOperationDTO] = []
    var errorMessage: String?
    var isLoading = false

    private let manager: any InboxApprovalManaging

    init(manager: any InboxApprovalManaging) {
        self.manager = manager
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            approvals = try await manager.fetchPendingApprovals()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func approve(_ operation: InboxOperationDTO) async {
        await decide(operation) {
            try await manager.approve(operation)
        }
    }

    func decline(_ operation: InboxOperationDTO) async {
        await decide(operation) {
            try await manager.decline(operation)
        }
    }

    func replaceApprovals(_ operations: [InboxOperationDTO]) {
        approvals = operations
    }

    private func decide(
        _ operation: InboxOperationDTO,
        action: () async throws -> Void
    ) async {
        errorMessage = nil
        do {
            try await action()
            approvals.removeAll { $0.id == operation.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
