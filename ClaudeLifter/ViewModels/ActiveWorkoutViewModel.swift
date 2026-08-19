import Foundation
import Observation
import UIKit

/// Where an active workout is in the process of ending.
///
/// This replaces a stored one-way `isFinished` Bool. That Bool was set to true
/// and never reset, and the summary sheet was presented solely by an
/// `onChange` on it — so the presentation could only ever fire once per app
/// run. Combined with `endWorkout()` living behind the summary's Done button,
/// dismissing that sheet any other way left the user inside a workout that was
/// already saved, with a Finish button that could no longer show anything
/// (#123).
enum WorkoutCompletionState {
    case active
    case finishing
    /// Terminal. `summary` is nil when the session was discarded rather than
    /// saved (#69) — there is no receipt, but the UI must still leave.
    case finished(summary: WorkoutCompletionSummary?)
    case failed(message: String)
}

@Observable
@MainActor
final class ActiveWorkoutViewModel {
    var workout: Workout? = nil
    private(set) var completionState: WorkoutCompletionState = .active
    var errorMessage: String? = nil

    /// Derived, not stored. The hazard was never the name — it was that this
    /// was a stored one-way flag doubling as the sole presentation trigger.
    var isFinished: Bool {
        if case .finished = completionState { return true }
        return false
    }

    /// True while the critical save is in flight, so the UI can disable Finish
    /// and show progress instead of accepting taps it will discard.
    var isFinishing: Bool {
        if case .finishing = completionState { return true }
        return false
    }
    var lastCompletedSet: WorkoutSet? = nil
    var detectedPRs: [PersonalRecord] = []
    private(set) var previousValues: [UUID: AutoFillResult] = [:]

    /// The planned target per workout exercise (#144), from the provenance
    /// baseline captured at start. Keyed by `WorkoutExercise.id`; an exercise
    /// added mid-workout is simply absent, because it has no plan.
    private(set) var plannedTargets: [UUID: PlannedTarget] = [:]
    private(set) var pendingPlannedTargetsLoad: Task<Void, Never>?

    /// Set IDs whose reps field the user has decided about — typed a value or
    /// deliberately cleared it (#137). This is the third state that makes
    /// adoption safe: *unset* (adopt the previous session), *decided-empty*
    /// (persist nil), *entered* (leave alone). Without it, "not filled in yet"
    /// and "I mean blank" are the same nil and adoption overwrites intent.
    ///
    /// Transient by design. It is lost across a crash/resume, where the
    /// conservative outcome is that an untouched empty set gets its previous
    /// reps back — harmless, because nil reps on an unlogged set carry no
    /// meaning. The same reasoning does NOT hold for weight, which is why
    /// weight is never adopted.
    private var repsDecidedByUser: Set<UUID> = []

    private let template: WorkoutTemplate?
    private let adHocName: String?
    private let workoutRepository: any WorkoutRepository
    private let autoFillService: any AutoFillServiceProtocol
    private let prDetectionService: (any PRDetectionServiceProtocol)?
    private let templateRepository: (any TemplateRepository)?
    /// Needed to persist per-exercise notes (#136). Optional so existing
    /// construction sites keep compiling; when nil the note is written to the
    /// in-memory model but not saved.
    private let exerciseRepository: (any ExerciseRepository)?
    /// Records the template plan a workout started from (#128). Optional so
    /// existing construction sites keep compiling; when nil, provenance is
    /// simply not captured and post-workout reconciliation has nothing to
    /// offer — the workout itself is unaffected.
    private let baselineRepository: (any TemplateBaselineRepository)?
    /// Global user preferences. Optional so existing construction sites keep
    /// compiling; when nil, newly created sets fall back to kg (#83).
    private let settings: SettingsManager?

    /// The unit newly created sets default to (#83). Reads the live
    /// SettingsManager so mid-workout preference changes are respected.
    /// Per-set override remains possible — this is only the creation default.
    private var defaultWeightUnit: WeightUnit {
        settings?.weightUnit ?? .kg
    }

    /// Handle for any in-flight save triggered by a mutation. Exposed so
    /// tests can `await` it before tearing down the SwiftData container,
    /// otherwise fire-and-forget Tasks outlive the test and crash when the
    /// ModelContext is reset. Cancelled before each new save to coalesce
    /// rapid mutations.
    private(set) var pendingSave: Task<Void, Never>?
    private(set) var pendingPreviousValuesLoad: Task<Void, Never>?
    private var didLoadInitialPreviousValues = false

    /// The in-flight finish attempt, so duplicate taps join it rather than
    /// racing it (#124).
    private var finishTask: Task<Void, Never>?
    /// Follow-up work that runs after the critical save has committed.
    private var postCommitTask: Task<Void, Never>?

    /// Awaits any in-flight save triggered by the last mutation. Useful in
    /// tests and wherever deterministic persistence is required before the
    /// next action.
    func awaitPendingSave() async {
        await pendingSave?.value
    }

    func awaitPlannedTargetsLoad() async {
        await pendingPlannedTargetsLoad?.value
    }

    func awaitPreviousValuesLoad() async {
        await pendingPreviousValuesLoad?.value
    }

    /// Awaits template bookkeeping and PR detection. These run *after* the
    /// workout is durably saved and are deliberately not awaited by
    /// `finishWorkout()`, so tests need an explicit join point — the same
    /// pattern as `awaitPendingSave()`.
    func awaitPostCommitWork() async {
        await postCommitTask?.value
    }

    /// The receipt for the finished workout, or nil when the session was
    /// discarded rather than saved.
    var completionSummary: WorkoutCompletionSummary? {
        if case .finished(let summary) = completionState { return summary }
        return nil
    }

    /// Non-fatal problems from post-commit work. The workout is already saved,
    /// so these are reported rather than thrown — but not silently dropped the
    /// way the previous `try?` calls dropped them (#125).
    private(set) var postCommitWarnings: [String] = []

    /// The plan for this exercise, or nil when there is none — an ad-hoc
    /// workout, or an exercise added mid-session. Nil means "show nothing";
    /// inventing a target would be worse than an empty line.
    func plannedTarget(for workoutExercise: WorkoutExercise) -> PlannedTarget? {
        plannedTargets[workoutExercise.id]
    }

    /// Whether **last session's** reps for this set missed the template target
    /// (#144).
    ///
    /// Deliberately about the previous session, not the current one: this sits
    /// next to the field the user is about to fill in, while there is still
    /// time to correct course. Flagging what they just typed would be a
    /// reprimand after the fact — "in the current session it's too late to do
    /// anything about the drift once you enter the weight."
    func previousDriftedFromTarget(
        _ set: WorkoutSet,
        in workoutExercise: WorkoutExercise
    ) -> Bool {
        guard
            let target = plannedTargets[workoutExercise.id],
            let previousReps = previous(for: set)?.reps
        else {
            // No plan, or no previous session — absence is not disagreement.
            return false
        }
        return previousReps != target.reps
    }

    private func loadPlannedTargets(for workout: Workout) {
        guard let baselineRepository else { return }
        pendingPlannedTargetsLoad = Task { [weak self] in
            guard let self else { return }
            guard let entries = try? await baselineRepository.fetchEntries(
                workoutId: workout.id
            ) else { return }
            var targets: [UUID: PlannedTarget] = [:]
            for entry in entries {
                guard let workoutExerciseId = entry.workoutExerciseId else { continue }
                targets[workoutExerciseId] = PlannedTarget(
                    sets: entry.plannedSets,
                    reps: entry.plannedReps,
                    restSeconds: entry.plannedRestSeconds,
                    notes: entry.plannedNotes
                )
            }
            self.plannedTargets = targets
        }
    }

    func previous(for set: WorkoutSet) -> AutoFillResult? {
        previousValues[set.id]
    }

    var totalSetsCompleted: Int {
        workout?.exercises.flatMap(\.sets).filter(\.isCompleted).count ?? 0
    }

    var hasCompletedSets: Bool {
        workout?.exercises.flatMap(\.sets).contains(where: \.isCompleted) ?? false
    }

    var totalSets: Int {
        workout?.exercises.flatMap(\.sets).count ?? 0
    }

    init(
        template: WorkoutTemplate,
        workoutRepository: any WorkoutRepository,
        autoFillService: any AutoFillServiceProtocol,
        exerciseRepository: (any ExerciseRepository)? = nil,
        templateRepository: (any TemplateRepository)? = nil,
        baselineRepository: (any TemplateBaselineRepository)? = nil,
        prDetectionService: (any PRDetectionServiceProtocol)? = nil,
        settings: SettingsManager? = nil
    ) {
        self.template = template
        self.adHocName = nil
        self.workoutRepository = workoutRepository
        self.autoFillService = autoFillService
        self.exerciseRepository = exerciseRepository
        self.baselineRepository = baselineRepository
        self.templateRepository = templateRepository
        self.prDetectionService = prDetectionService
        self.settings = settings
    }

    init(
        adHocName: String,
        workoutRepository: any WorkoutRepository,
        autoFillService: any AutoFillServiceProtocol,
        exerciseRepository: (any ExerciseRepository)? = nil,
        baselineRepository: (any TemplateBaselineRepository)? = nil,
        prDetectionService: (any PRDetectionServiceProtocol)? = nil,
        settings: SettingsManager? = nil
    ) {
        self.template = nil
        self.adHocName = adHocName
        self.workoutRepository = workoutRepository
        self.autoFillService = autoFillService
        self.exerciseRepository = exerciseRepository
        self.baselineRepository = baselineRepository
        self.templateRepository = nil
        self.prDetectionService = prDetectionService
        self.settings = settings
    }

    /// Resumes an existing in-progress workout (crash recovery, #75). The
    /// workout is adopted as-is — logged sets, exercises, and notes intact —
    /// instead of building a new session from a template.
    init(
        resuming workout: Workout,
        workoutRepository: any WorkoutRepository,
        autoFillService: any AutoFillServiceProtocol,
        exerciseRepository: (any ExerciseRepository)? = nil,
        templateRepository: (any TemplateRepository)? = nil,
        baselineRepository: (any TemplateBaselineRepository)? = nil,
        prDetectionService: (any PRDetectionServiceProtocol)? = nil,
        settings: SettingsManager? = nil
    ) {
        self.template = nil
        self.adHocName = nil
        self.workoutRepository = workoutRepository
        self.autoFillService = autoFillService
        self.exerciseRepository = exerciseRepository
        self.baselineRepository = baselineRepository
        self.templateRepository = templateRepository
        self.prDetectionService = prDetectionService
        self.settings = settings
        self.workout = workout
    }

    func startWorkout() async {
        // A resumed session is already constructed, but its prior-session
        // ghosts are transient ViewModel state and must be rebuilt after a
        // crash/relaunch. Keep the model intact while repopulating that map.
        if let workout {
            guard !didLoadInitialPreviousValues else { return }
            let sourceTemplate = await templateForPreviousValues(in: workout)
            await populatePreviousValues(
                in: workout,
                sourceTemplate: sourceTemplate
            )
            // A resumed session keeps its targets: the baseline is stored, so
            // crash recovery reads back the same plan it started with (#144).
            loadPlannedTargets(for: workout)
            didLoadInitialPreviousValues = true
            return
        }

        // Clean up genuinely empty ghost sessions (no exercises, no notes)
        // left behind by a crash between "start" and the first mutation.
        // Non-empty drafts are deliberately kept: they are surfaced on the
        // Home screen for an explicit Resume/Discard choice (#75). The old
        // blanket delete here silently destroyed "Save progress as draft"
        // data every time a new workout started.
        await discardEmptyGhostSessions()

        if let template {
            await startFromTemplate(template)
        } else if let adHocName {
            await startAdHoc(name: adHocName)
        }
    }

    /// Deletes only in-progress workouts with zero user-visible content —
    /// no exercises (hence no sets, completed or otherwise) and no notes.
    /// Anything with content is the user's data and requires an explicit
    /// Discard on the Home screen's resume prompt (#75).
    private func discardEmptyGhostSessions() async {
        do {
            let all = try await workoutRepository.fetchAll()
            for w in all where w.completedAt == nil && w.isEmptyGhostSession {
                try? await workoutRepository.delete(w)
            }
        } catch {
            // Non-fatal — if the cleanup fails we still proceed with the new
            // workout. The ghosts aren't preventing the user from starting,
            // they're just ugly in history.
            print("⚠️ discardEmptyGhostSessions failed: \(error)")
        }
    }

    private func startAdHoc(name: String) async {
        let newWorkout = Workout(name: name, startedAt: .now, templateId: nil)
        do {
            try await saveWorkout(newWorkout)
            workout = newWorkout
            didLoadInitialPreviousValues = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startFromTemplate(_ template: WorkoutTemplate) async {
        let newWorkout = Workout(
            name: template.name,
            startedAt: .now,
            templateId: template.id
        )
        // Pairs each planned exercise with the session exercise created from
        // it, so the baseline can be linked without a stored property on
        // WorkoutExercise — which would change every VersionedSchema's
        // checksum. See the note on ClaudeLifterSchemaV4.
        var workoutExerciseIdByTemplateExerciseId: [UUID: UUID] = [:]
        for templateExercise in template.exercises.sorted(by: { $0.order < $1.order }) {
            guard let exercise = templateExercise.exercise else { continue }
            let we = WorkoutExercise(
                order: templateExercise.order,
                exercise: exercise,
                // Machine settings live here — seat/pin/pivot numbers the user
                // needs standing at the machine. Never copied until #136.
                notes: templateExercise.notes,
                restSeconds: templateExercise.defaultRestSeconds
            )
            // Per-set-index auto-fill from the previous session (#82):
            // set 1 → set 1, set 2 → set 2, … preserving warm-up → top-set
            // structure. Empty when there's no history → template defaults.
            // The previous-value map remains display-only.
            let autoFills = (try? await autoFillService.autoFillValues(
                exerciseId: exercise.id,
                setCount: templateExercise.defaultSets
            )) ?? []
            for i in 0..<templateExercise.defaultSets {
                let autoFill = i < autoFills.count ? autoFills[i] : nil
                let set = WorkoutSet(
                    order: i,
                    weight: autoFill?.weight
                        ?? templateExercise.defaultWeight,
                    weightUnit: autoFill?.weightUnit
                        ?? defaultWeightUnit,
                    reps: autoFill?.reps
                        ?? templateExercise.defaultReps
                )
                we.sets.append(set)
                if let autoFill {
                    previousValues[set.id] = autoFill
                }
            }
            newWorkout.exercises.append(we)
            workoutExerciseIdByTemplateExerciseId[templateExercise.id] = we.id
        }
        do {
            try await saveWorkout(newWorkout)
            workout = newWorkout
            didLoadInitialPreviousValues = true
            loadPlannedTargets(for: newWorkout)
            await captureBaseline(
                for: newWorkout,
                from: template,
                workoutExerciseIds: workoutExerciseIdByTemplateExerciseId
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Freezes the template plan this workout started from (#128).
    ///
    /// Written once, after the workout is saved, and never updated — an
    /// exercise added later deliberately has no entry, and that absence is how
    /// #129 tells a genuine addition from a planned one.
    ///
    /// A failure here is swallowed on purpose. Provenance buys a post-workout
    /// suggestion; being able to train is not worth risking for it.
    private func captureBaseline(
        for workout: Workout,
        from template: WorkoutTemplate,
        workoutExerciseIds: [UUID: UUID]
    ) async {
        guard let baselineRepository else { return }
        let baseline = WorkoutTemplateBaseline(
            workoutId: workout.id,
            templateId: template.id,
            templateRevision: template.lastModified,
            templateName: template.name
        )
        let entries = template.exercises
            .sorted(by: { $0.order < $1.order })
            .compactMap { te -> WorkoutExerciseBaseline? in
                guard let exercise = te.exercise else { return nil }
                return WorkoutExerciseBaseline(
                    workoutId: workout.id,
                    workoutExerciseId: workoutExerciseIds[te.id],
                    sourceTemplateExerciseId: te.id,
                    exerciseId: exercise.id,
                    exerciseExternalId: exercise.externalId,
                    exerciseName: exercise.name,
                    plannedOrder: te.order,
                    plannedSets: te.defaultSets,
                    plannedReps: te.defaultReps,
                    plannedRestSeconds: te.defaultRestSeconds,
                    plannedNotes: te.notes
                )
            }
        do {
            try await baselineRepository.save(baseline, entries: entries)
        } catch {
            print("⚠️ captureBaseline failed: \(error)")
        }
    }

    // MARK: - Mutation API (#76)
    //
    // EVERY mutation of the active workout — weight/reps edits, set
    // completion, add/remove set, add/remove exercise — must go through one
    // of the methods below so that a single code path (`persistMutation`)
    // bumps the parent Workout's `lastModified`, re-queues it as `.pending`
    // for sync, and persists via the repository. Views must never write to
    // WorkoutSet/WorkoutExercise directly.

    /// Shared tail of every mutation: sync bookkeeping + debounced save.
    /// `recordChange()` runs synchronously so sync state is correct even if
    /// the app dies before the async save lands.
    private func persistMutation() {
        // Once the workout is finished its record is authoritative. A late
        // mutation — from a Coach tool, say — must not re-open it for a draft
        // save that would re-stamp `lastModified` behind the user's back.
        if case .finished = completionState { return }
        workout?.recordChange()
        pendingSave?.cancel()
        // [weak self] so the Task is a no-op if the VM has been released
        // (e.g. at end of a test) — otherwise saveDraft touches `workout`
        // through a SwiftData context that has already been reset and
        // crashes in BackingData.
        pendingSave = Task { [weak self] in
            guard let self else { return }
            await self.saveDraft()
        }
    }

    func updateSetWeight(_ set: WorkoutSet, weight: Double?) {
        guard set.weight != weight else { return }
        if set.weight == nil,
           weight != nil,
           let previous = previous(for: set) {
            set.weightUnit = previous.weightUnit
        }
        set.weight = weight
        persistMutation()
    }

    /// Per-exercise notes — machine settings, cues (#136).
    ///
    /// The note is written to the **library `Exercise`**, not to the session
    /// or the template: "Ankle 4; Seat 4; Pivot 1" describes the machine, so
    /// it must appear in every future workout that uses Seated Leg Curl,
    /// whichever template that workout came from.
    ///
    /// Whitespace-only input clears the note, so an emptied field does not
    /// leave a blank note rendering as an empty row.
    ///
    /// Note this deliberately does not go through `persistMutation()` — the
    /// workout record is unchanged, so a note edit must not re-stamp its
    /// `lastModified` or re-open a finished session (#124).
    func updateExerciseNotes(
        _ workoutExercise: WorkoutExercise,
        notes: String?
    ) async {
        guard let exercise = workoutExercise.exercise else { return }
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (trimmed?.isEmpty ?? true) ? nil : trimmed
        guard exercise.notes != normalized
            || workoutExercise.notes != normalized else { return }

        exercise.notes = normalized

        // Also stamp the session copy. Two reasons, both real: bundled
        // exercises are excluded from sync *and* from backup (BackupService
        // carries only `isCustom`), so the library note is device-local and
        // invisible to the Coach and MCP — the workout is the copy that
        // travels. And what settings were used on a given day is genuinely
        // session data. `persistMutation` handles the sync bookkeeping and
        // already declines to re-open a finished workout (#124).
        if workoutExercise.notes != normalized {
            workoutExercise.notes = normalized
            persistMutation()
        }

        do {
            try await exerciseRepository?.save(exercise)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSetReps(_ set: WorkoutSet, reps: Int?) {
        // Recorded even when the value is unchanged: clearing a field that is
        // already nil is still the user saying "blank is what I meant" (#137).
        repsDecidedByUser.insert(set.id)
        guard set.reps != reps else { return }
        set.reps = reps
        persistMutation()
    }

    @discardableResult
    func completeSet(_ set: WorkoutSet) -> Bool {
        if set.isCompleted {
            set.isCompleted = false
            set.completedAt = nil
            if lastCompletedSet?.id == set.id {
                lastCompletedSet = nil
            }
            persistMutation()
            return false
        }

        set.isCompleted = true
        set.completedAt = .now
        lastCompletedSet = set
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        persistMutation()
        return true
    }

    func addSet(to workoutExercise: WorkoutExercise) {
        let nextOrder = (workoutExercise.sets.map(\.order).max() ?? -1) + 1
        let lastPrevious = workoutExercise.sets
            .sorted(by: { $0.order < $1.order })
            .compactMap { previous(for: $0) }
            .last
        let newSet = WorkoutSet(
            order: nextOrder,
            weight: lastPrevious?.weight,
            weightUnit: lastPrevious?.weightUnit ?? defaultWeightUnit,
            reps: lastPrevious?.reps
        )
        if let lastPrevious {
            previousValues[newSet.id] = lastPrevious
        }
        workoutExercise.sets.append(newSet)
        persistMutation()
        if lastPrevious == nil {
            queuePreviousValuesLoad(for: workoutExercise)
        }
    }

    func removeSet(_ set: WorkoutSet, from workoutExercise: WorkoutExercise) {
        workoutExercise.sets.removeAll { $0.id == set.id }
        previousValues[set.id] = nil
        for (index, survivor) in workoutExercise.sets
            .sorted(by: { $0.order < $1.order })
            .enumerated() {
            survivor.order = index
        }
        persistMutation()
    }

    func addExercise(_ exercise: Exercise) {
        guard let workout else { return }
        let order = workout.exercises.count
        let we = WorkoutExercise(order: order, exercise: exercise)
        workout.exercises.append(we)
        for i in 0..<3 {
            we.sets.append(WorkoutSet(order: i, weightUnit: defaultWeightUnit))
        }
        persistMutation()
        queuePreviousValuesLoad(for: we)
    }

    func removeExercise(_ workoutExercise: WorkoutExercise) {
        for set in workoutExercise.sets {
            previousValues[set.id] = nil
        }
        workout?.exercises.removeAll { $0.id == workoutExercise.id }
        persistMutation()
    }

    private func previousValue(
        at index: Int,
        autoFills: [AutoFillResult],
        templateExercise: TemplateExercise?
    ) -> AutoFillResult? {
        if index < autoFills.count {
            return autoFills[index]
        }
        guard let templateExercise else { return nil }
        return AutoFillResult(
            weight: templateExercise.defaultWeight,
            weightUnit: defaultWeightUnit,
            reps: templateExercise.defaultReps,
            date: .distantPast
        )
    }

    private func templateForPreviousValues(
        in workout: Workout
    ) async -> WorkoutTemplate? {
        if let template {
            return template
        }
        guard
            let templateID = workout.templateId,
            let templateRepository
        else {
            return nil
        }
        return try? await templateRepository.fetch(id: templateID)
    }

    /// Rebuilds transient ghosts for every set in a newly started or resumed
    /// workout without mutating any committed set-entry value.
    private func populatePreviousValues(
        in workout: Workout,
        sourceTemplate: WorkoutTemplate?
    ) async {
        for workoutExercise in workout.exercises {
            let templateExercise = sourceTemplate?.exercises.first {
                $0.exercise?.id == workoutExercise.exercise?.id
            }
            await populatePreviousValues(
                for: workoutExercise,
                templateExercise: templateExercise
            )
        }
    }

    private func populatePreviousValues(
        for workoutExercise: WorkoutExercise,
        templateExercise: TemplateExercise? = nil
    ) async {
        guard let exerciseID = workoutExercise.exercise?.id else { return }
        let sortedSets = workoutExercise.sets.sorted(by: { $0.order < $1.order })
        let autoFills = (try? await autoFillService.autoFillValues(
            exerciseId: exerciseID,
            setCount: sortedSets.count,
            excludingWorkoutId: workout?.id
        )) ?? []

        var didAdopt = false
        for (index, set) in sortedSets.enumerated() {
            guard let previous = previousValue(
                at: index,
                autoFills: autoFills,
                templateExercise: templateExercise
            ) else {
                continue
            }
            previousValues[set.id] = previous
            if adoptPreviousReps(into: set, from: previous) {
                didAdopt = true
            }
        }
        if didAdopt {
            persistMutation()
        }
    }

    /// Writes the previous session's reps into a set the user has not decided
    /// about yet (#137). Returns whether anything changed.
    ///
    /// Reps only. `WorkoutSet.weight == nil` already means bodyweight, so
    /// adopting a previous weight would log 80kg for a bodyweight set — the
    /// exact data-corruption bug that got ghost adoption cut the first time.
    /// A nil rep count has no such second meaning.
    @discardableResult
    private func adoptPreviousReps(
        into set: WorkoutSet,
        from previous: AutoFillResult
    ) -> Bool {
        // A logged set is a record, not a draft.
        guard !set.isCompleted else { return false }
        guard !repsDecidedByUser.contains(set.id) else { return false }
        guard set.reps == nil, let reps = previous.reps else { return false }
        set.reps = reps
        return true
    }

    private func queuePreviousValuesLoad(for workoutExercise: WorkoutExercise) {
        let precedingLoad = pendingPreviousValuesLoad
        pendingPreviousValuesLoad = Task { [weak self] in
            await precedingLoad?.value
            guard let self else { return }
            await self.populatePreviousValues(for: workoutExercise)
        }
    }

    func saveDraft() async {
        guard let workout else { return }
        // Don't persist a draft with no user-visible progress. This was the
        // source of the "Quick Workout — 0 exercises, 0 sets (in progress)"
        // rows piling up in history. If nothing's been done yet, the user
        // backing out should leave history untouched, not create a ghost.
        if workout.exercises.isEmpty && workout.notes?.isEmpty != false {
            try? await workoutRepository.delete(workout)
            return
        }
        workout.recordChange()
        do {
            try await saveWorkout(workout)
        } catch {
            // Never swallow a failed draft save — the user would silently
            // lose logged sets on the next crash/force-quit (#76).
            errorMessage = error.localizedDescription
        }
    }

    func cancelWorkout() async {
        guard let workout else { return }
        do {
            try await workoutRepository.delete(workout)
            self.workout = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Ends the workout. Idempotent: repeated taps join the in-flight attempt
    /// or return immediately once it has succeeded (#124). Returns as soon as
    /// the critical save has committed — post-commit work continues in the
    /// background so slow PR detection cannot hold the user in the workout.
    func finishWorkout() async {
        // Already done. Re-entering used to re-stamp `completedAt`, save again,
        // bump `timesPerformed` again and re-run PR detection — all invisibly,
        // because the presentation trigger could not fire twice.
        if case .finished = completionState { return }

        // A second tap while the first is still saving waits for that attempt
        // rather than starting a competing one.
        if let finishTask {
            await finishTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performFinish()
        }
        finishTask = task
        await task.value
        finishTask = nil
    }

    private func performFinish() async {
        guard let workout else { return }
        completionState = .finishing

        // #69: a session with nothing logged is discarded, not saved. It has no
        // receipt to show. The old code still routed it through the summary
        // sheet, which then rendered an empty view with no Done button.
        if workout.exercises.isEmpty || !hasCompletedSets {
            await cancelWorkout()
            completionState = .finished(summary: nil)
            return
        }

        // #121: `persistMutation` leaves a draft save in flight. It must not
        // land after completion — `saveDraft` re-stamps `lastModified` and
        // deletes sessions it considers empty. Cancel it and let the
        // authoritative save below be the one that counts.
        pendingSave?.cancel()
        pendingSave = nil

        // Stamped once per successful attempt. A retry after a failed save
        // re-stamps deliberately; a duplicate tap never reaches here.
        if workout.completedAt == nil {
            workout.completedAt = .now
        }
        workout.recordChange()

        do {
            try await saveWorkout(workout)
        } catch {
            // The workout stays intact and active so the user can retry
            // without losing logged sets.
            workout.completedAt = nil
            errorMessage = error.localizedDescription
            completionState = .failed(message: error.localizedDescription)
            return
        }

        // The critical transaction has committed. Publishing the receipt here
        // — before any of the follow-up work — is what lets the UI leave the
        // workout immediately.
        let summary = WorkoutCompletionSummary(workout: workout)
        completionState = .finished(summary: summary)

        postCommitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runPostCommitWork(for: workout, summary: summary)
        }
    }

    /// Template bookkeeping and PR detection. Everything here happens after the
    /// workout is durably saved, so failures are recorded and surfaced but can
    /// never reopen, delay or discard a completed workout (#125).
    private func runPostCommitWork(
        for workout: Workout,
        summary: WorkoutCompletionSummary
    ) async {
        if let template, let templateRepository {
            template.timesPerformed += 1
            template.lastPerformedAt = .now
            template.recordChange()
            do {
                try await templateRepository.save(template)
            } catch {
                // Previously `try?`, so a broken template save was invisible.
                template.timesPerformed -= 1
                postCommitWarnings.append(
                    "Template usage wasn't updated: \(error.localizedDescription)"
                )
            }
        }

        if let prService = prDetectionService {
            do {
                let prs = try await prService.detectPRs(for: workout)
                detectedPRs = prs
                summary.personalRecords = prs
            } catch {
                postCommitWarnings.append(
                    "Couldn't check for personal records: \(error.localizedDescription)"
                )
            }
        }

        await detectTemplateChanges(for: workout, summary: summary)
    }

    /// Compares the finished workout to the plan it started from (#129).
    ///
    /// Runs here, after the durable save, for the same reason PR detection
    /// does: the workout is already safe, so nothing this finds — or fails to
    /// find — can delay or endanger it. The result lands on the summary, which
    /// is a reference type precisely so it can be filled in after the sheet is
    /// already on screen.
    private func detectTemplateChanges(
        for workout: Workout,
        summary: WorkoutCompletionSummary
    ) async {
        guard let baselineRepository, let templateRepository else { return }
        do {
            guard
                let baseline = try await baselineRepository.fetchBaseline(
                    workoutId: workout.id
                ),
                let currentTemplate = try await templateRepository.fetch(
                    id: baseline.templateId
                )
            else { return }
            let entries = try await baselineRepository.fetchEntries(
                workoutId: workout.id
            )
            let changeSet = TemplateChangeDetector().detect(
                workout: workout,
                baseline: baseline,
                entries: entries,
                template: currentTemplate
            )
            // Nil rather than an empty set, so the review card has one simple
            // condition to test and cannot appear with nothing in it.
            summary.templateChangeSet = changeSet.isEmpty ? nil : changeSet
        } catch {
            postCommitWarnings.append(
                "Couldn't check for template changes: \(error.localizedDescription)"
            )
        }
    }

    private func saveWorkout(_ w: Workout) async throws {
        try await workoutRepository.save(w)
    }
}

extension Workout {
    /// True when this session contains nothing the user could miss: no
    /// exercises (hence no sets) and no notes. Only such sessions may be
    /// deleted without an explicit user choice (#75). Shared by the
    /// start-workout cleanup and the Home screen's resume detection.
    var isEmptyGhostSession: Bool {
        exercises.isEmpty && (notes ?? "").isEmpty
    }
}
