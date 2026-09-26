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
    /// What each operation would do, keyed by operation id (#153, #147).
    private(set) var previews: [String: InboxChangePreview] = [:]
    /// Verdicts staged on the pending-changes screen, not yet sent. They are
    /// committed together by `commit()` so N decisions cost one ack and one
    /// snapshot push instead of N serial syncs.
    private(set) var staged: [String: InboxDecision.Verdict] = [:]
    var errorMessage: String?
    var isLoading = false
    private(set) var isCommitting = false

    private let manager: any InboxApprovalManaging
    private let previewBuilder: (any InboxChangePreviewBuilding)?

    init(
        manager: any InboxApprovalManaging,
        previewBuilder: (any InboxChangePreviewBuilding)? = nil
    ) {
        self.manager = manager
        self.previewBuilder = previewBuilder
    }

    var pendingCount: Int { approvals.count }
    var stagedCount: Int { staged.count }
    var hasUndecided: Bool { approvals.contains { staged[$0.id] == nil } }

    func verdict(for operation: InboxOperationDTO) -> InboxDecision.Verdict? {
        staged[operation.id]
    }

    func preview(for operation: InboxOperationDTO) -> InboxChangePreview? {
        previews[operation.id]
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            approvals = try await manager.fetchPendingApprovals()
            await refreshPreviews()
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
        let live = Set(operations.map(\.id))
        staged = staged.filter { live.contains($0.key) }
        Task { await refreshPreviews() }
    }

    // MARK: - Staged batch (#153)

    func stage(_ operation: InboxOperationDTO, _ verdict: InboxDecision.Verdict) {
        staged[operation.id] = verdict
    }

    func unstage(_ operation: InboxOperationDTO) {
        staged[operation.id] = nil
    }

    func stageAll(_ verdict: InboxDecision.Verdict) {
        for operation in approvals {
            staged[operation.id] = verdict
        }
    }

    /// Sends every staged verdict in one batch. Undecided operations stay
    /// pending. On failure nothing is dropped: the verdicts remain staged and
    /// the operations remain listed, so the user can retry or change them.
    func commit() async {
        let decisions = approvals.compactMap { operation -> InboxDecision? in
            guard let verdict = staged[operation.id] else { return nil }
            return InboxDecision(operation: operation, verdict: verdict)
        }
        guard !decisions.isEmpty, !isCommitting else { return }
        isCommitting = true
        errorMessage = nil
        defer { isCommitting = false }
        do {
            do {
                try await manager.decide(decisions)
            } catch SyncError.syncInProgress {
                // A background sync was mid-flight when the sheet closed.
                // Wait it out once rather than bouncing the user back in.
                try await Task.sleep(for: .seconds(2))
                try await manager.decide(decisions)
            }
            let decided = Set(decisions.map(\.operation.id))
            approvals.removeAll { decided.contains($0.id) }
            staged = staged.filter { !decided.contains($0.key) }
            previews = previews.filter { !decided.contains($0.key) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshPreviews() async {
        guard let previewBuilder else { return }
        var next: [String: InboxChangePreview] = [:]
        for operation in approvals {
            next[operation.id] = await previewBuilder.preview(for: operation)
        }
        previews = next
    }

    private func decide(
        _ operation: InboxOperationDTO,
        action: () async throws -> Void
    ) async {
        errorMessage = nil
        do {
            try await action()
            approvals.removeAll { $0.id == operation.id }
            staged[operation.id] = nil
            previews[operation.id] = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
