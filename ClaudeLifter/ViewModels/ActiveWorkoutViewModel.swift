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

    /// Awaits any in-flight save triggered by the last mutation. Useful in
    /// tests and wherever deterministic persistence is required before the
    /// next action.
    func awaitPendingSave() async {
        await pendingSave?.value
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

    func startWorkout() async {
        // Clean up any prior in-progress workouts before starting a new one.
        // Per product: at most one workout is active at a time. Before today
        // saveDraft() left behind a `completedAt == nil` row for every force-
        // quit or Exit-with-Save, and they piled up forever because the app
        // had no UI to resume or discard them. Just delete them so history
        // only contains genuinely completed sessions.
        await discardStaleInProgressWorkouts()

        if let template {
            await startFromTemplate(template)
        } else if let adHocName {
            await startAdHoc(name: adHocName)
        }
    }

    /// Deletes every in-progress workout (completedAt == nil). Called at the
    /// start of a new session so that drafts from a previous session don't
    /// linger in history. Also exposed to the Coach via the
    /// `discard_stale_workouts` tool.
    private func discardStaleInProgressWorkouts() async {
        do {
            let all = try await workoutRepository.fetchAll()
            for w in all where w.completedAt == nil {
                try? await workoutRepository.delete(w)
            }
        } catch {
            // Non-fatal — if the cleanup fails we still proceed with the new
            // workout. The duplicates aren't preventing the user from
            // starting, they're just ugly in history.
            print("⚠️ discardStaleInProgressWorkouts failed: \(error)")
        }
    }

    private func startAdHoc(name: String) async {
        let newWorkout = Workout(name: name, startedAt: .now, templateId: nil)
        do {
            try await saveWorkout(newWorkout)
            workout = newWorkout
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
            let autoFill = try? await autoFillService.lastPerformed(exerciseId: exercise.id)
            for i in 0..<templateExercise.defaultSets {
                let set = WorkoutSet(
                    order: i,
                    weight: autoFill?.weight ?? templateExercise.defaultWeight,
                    // Last session's unit carries forward (per-set continuity);
                    // without history, fall back to the global preference (#83).
                    weightUnit: autoFill?.weightUnit ?? defaultWeightUnit,
                    reps: autoFill?.reps ?? templateExercise.defaultReps
                )
                we.sets.append(set)
            }
            newWorkout.exercises.append(we)
        }
        do {
            try await saveWorkout(newWorkout)
            workout = newWorkout
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
        set.weight = weight
        persistMutation()
    }

    func updateSetReps(_ set: WorkoutSet, reps: Int?) {
        guard set.reps != reps else { return }
        set.reps = reps
        persistMutation()
    }

    func completeSet(_ set: WorkoutSet) {
        set.isCompleted = true
        set.completedAt = .now
        lastCompletedSet = set
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        persistMutation()
    }

    func addSet(to workoutExercise: WorkoutExercise) {
        let nextOrder = (workoutExercise.sets.map(\.order).max() ?? -1) + 1
        workoutExercise.sets.append(
            WorkoutSet(order: nextOrder, weightUnit: defaultWeightUnit)
        )
        persistMutation()
    }

    func removeSet(_ set: WorkoutSet, from workoutExercise: WorkoutExercise) {
        workoutExercise.sets.removeAll { $0.id == set.id }
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
    }

    func removeExercise(_ workoutExercise: WorkoutExercise) {
        workout?.exercises.removeAll { $0.id == workoutExercise.id }
        persistMutation()
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
