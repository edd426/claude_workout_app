import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class ActiveWorkoutViewModel {
    var workout: Workout? = nil
    var isFinished = false
    var errorMessage: String? = nil
    var lastCompletedSet: WorkoutSet? = nil
    var detectedPRs: [PersonalRecord] = []
    private(set) var previousValues: [UUID: AutoFillResult] = [:]

    private let template: WorkoutTemplate?
    private let adHocName: String?
    private let workoutRepository: any WorkoutRepository
    private let autoFillService: any AutoFillServiceProtocol
    private let prDetectionService: (any PRDetectionServiceProtocol)?
    private let templateRepository: (any TemplateRepository)?
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

    /// Awaits any in-flight save triggered by the last mutation. Useful in
    /// tests and wherever deterministic persistence is required before the
    /// next action.
    func awaitPendingSave() async {
        await pendingSave?.value
    }

    func awaitPreviousValuesLoad() async {
        await pendingPreviousValuesLoad?.value
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
        templateRepository: (any TemplateRepository)? = nil,
        prDetectionService: (any PRDetectionServiceProtocol)? = nil,
        settings: SettingsManager? = nil
    ) {
        self.template = template
        self.adHocName = nil
        self.workoutRepository = workoutRepository
        self.autoFillService = autoFillService
        self.templateRepository = templateRepository
        self.prDetectionService = prDetectionService
        self.settings = settings
    }

    init(
        adHocName: String,
        workoutRepository: any WorkoutRepository,
        autoFillService: any AutoFillServiceProtocol,
        prDetectionService: (any PRDetectionServiceProtocol)? = nil,
        settings: SettingsManager? = nil
    ) {
        self.template = nil
        self.adHocName = adHocName
        self.workoutRepository = workoutRepository
        self.autoFillService = autoFillService
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
        templateRepository: (any TemplateRepository)? = nil,
        prDetectionService: (any PRDetectionServiceProtocol)? = nil,
        settings: SettingsManager? = nil
    ) {
        self.template = nil
        self.adHocName = nil
        self.workoutRepository = workoutRepository
        self.autoFillService = autoFillService
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
        for templateExercise in template.exercises.sorted(by: { $0.order < $1.order }) {
            guard let exercise = templateExercise.exercise else { continue }
            let we = WorkoutExercise(
                order: templateExercise.order,
                exercise: exercise,
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
        }
        do {
            try await saveWorkout(newWorkout)
            workout = newWorkout
            didLoadInitialPreviousValues = true
        } catch {
            errorMessage = error.localizedDescription
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

    func updateSetReps(_ set: WorkoutSet, reps: Int?) {
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

        for (index, set) in sortedSets.enumerated() {
            guard let previous = previousValue(
                at: index,
                autoFills: autoFills,
                templateExercise: templateExercise
            ) else {
                continue
            }
            previousValues[set.id] = previous
        }
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

    func finishWorkout() async {
        guard let workout else { return }

        // Delete empty/unused workouts instead of saving them (#69)
        if workout.exercises.isEmpty || !hasCompletedSets {
            await cancelWorkout()
            isFinished = true
            return
        }

        workout.completedAt = .now
        workout.recordChange()
        do {
            try await saveWorkout(workout)
            if let template, let templateRepository {
                template.timesPerformed += 1
                template.lastPerformedAt = .now
                template.recordChange()
                try? await templateRepository.save(template)
            }
            if let prService = prDetectionService {
                detectedPRs = (try? await prService.detectPRs(for: workout)) ?? []
            }
            isFinished = true
        } catch {
            errorMessage = error.localizedDescription
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
