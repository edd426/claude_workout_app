import Foundation
import Observation

@Observable
@MainActor
final class HomeViewModel {
    var templates: [WorkoutTemplate] = []
    var isLoading = false
    var errorMessage: String? = nil

    // MARK: - Today (1.9.0)

    /// The hero card's workout: today's by weekday name, else the least
    /// recently done. Nil while a draft is waiting, because then the hero is
    /// Resume. Stored, not computed, so `body` never re-derives it (UI-E5).
    private(set) var todaysTemplate: WorkoutTemplate?
    /// True when the hero is named for today; false when it is the
    /// least-recently-done fallback (weekends, or no weekday names).
    private(set) var heroIsScheduledToday = false
    /// False until the first `loadToday()`, so the screen shows a spinner
    /// rather than a flash of the empty state (UI-E1).
    private(set) var hasLoadedToday = false
    /// Every template except the hero's, for "Other workouts".
    private(set) var otherTemplates: [WorkoutTemplate] = []
    /// Start date of the latest finished workout per template (#176).
    private(set) var lastDone: [UUID: Date] = [:]
    /// This week's completed sets per muscle (#168). Nil until history loads.
    private(set) var weeklyVolume: WeeklyMuscleVolume?

    private let templateRepository: any TemplateRepository
    private let workoutRepository: (any WorkoutRepository)?
    private let volumeService: any MuscleVolumeCalculating
    private let calendar: Calendar
    private let now: () -> Date

    init(
        templateRepository: any TemplateRepository,
        workoutRepository: (any WorkoutRepository)? = nil,
        volumeService: (any MuscleVolumeCalculating)? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now }
    ) {
        self.templateRepository = templateRepository
        self.workoutRepository = workoutRepository
        self.volumeService = volumeService ?? MuscleVolumeService(calendar: calendar)
        self.calendar = calendar
        self.now = now
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
        refreshToday()
    }

    /// Everything the Today screen shows that comes from templates and
    /// history, in one pass over the workouts.
    func loadToday() async {
        await loadTemplates()
        await checkForResumableWorkout()
        hasLoadedToday = true
    }

    func lastDoneDate(for template: WorkoutTemplate) -> Date? {
        TemplateLastDone.date(for: template, in: lastDone)
    }

    func heroSubtitle(for template: WorkoutTemplate) -> String {
        TodayTemplatePicker.subtitle(
            exerciseCount: template.exercises.count,
            lastDone: lastDoneDate(for: template),
            now: now(),
            calendar: calendar
        )
    }

    private func refreshToday() {
        let hero = resumableWorkout == nil
            ? TodayTemplatePicker.pick(from: templates, lastDone: lastDone, now: now(), calendar: calendar)
            : nil
        todaysTemplate = hero
        heroIsScheduledToday = hero.map {
            TodayTemplatePicker.weekday(named: $0.name) == calendar.component(.weekday, from: now())
        } ?? false
        otherTemplates = templates.filter { $0.id != hero?.id }
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
    var resumableWorkout: Workout? = nil {
        didSet { refreshToday() }
    }

    /// Detects a crash-orphaned or draft-saved in-progress workout
    /// (`completedAt == nil`) so Home can offer Resume / Discard. Empty
    /// ghost sessions are ignored — start-workout cleanup handles those.
    ///
    /// The same pass derives the template last-done dates (#176) and this
    /// week's muscle volume (#168), so history is read once per refresh.
    func checkForResumableWorkout() async {
        guard let workoutRepository else { return }
        do {
            let all = try await workoutRepository.fetchAll()
            resumableWorkout = all
                .filter { $0.completedAt == nil && !$0.isEmptyGhostSession }
                .max { $0.startedAt < $1.startedAt }
            lastDone = TemplateLastDone.dates(from: all)
            weeklyVolume = volumeService.weeklyVolume(from: all, now: now())
        } catch {
            // Non-fatal: Home still works without resume detection.
            resumableWorkout = nil
        }
        refreshToday()
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
    /// A failed approve, decline or commit: something the user just did.
    /// Today and Pending Changes present it as an alert.
    var errorMessage: String?
    /// A failed background `load()`. Shown inline, never as an alert, since
    /// Today reloads on every appearance, foreground and sync (UI-E1, UI-E3).
    private(set) var loadErrorMessage: String?
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
