import Foundation
import SwiftData

/// The template plan a workout was started from, frozen at start (#128).
///
/// Post-workout reconciliation needs to know what was *intended*, and the
/// workout itself cannot answer that: mutations erase the evidence, and the
/// logged set values say nothing about intent because auto-fill pre-populates
/// them from history. Hence a snapshot taken before the user touches anything.
///
/// Two deliberate shape choices:
///
/// 1. **A separate model, not properties on `Workout`.** The `VersionedSchema`
///    lists in `AppSchema.swift` name live Swift types, so adding a property to
///    `Workout` also changes what V1–V3 mean; every version then hashes the
///    same and SwiftData throws `Duplicate version checksums detected` on
///    launch. A new model changes only V4's list, which is the one migration
///    shape that works here.
/// 2. **`workoutId` as a plain UUID, not a `@Relationship`.** A relationship
///    would require a stored property on `Workout` and reintroduce (1).
///
/// It is also the better model: a frozen record cannot be mutated by ordinary
/// workout edits.
@Model
final class WorkoutTemplateBaseline {
    @Attribute(.unique) var id: UUID
    /// The workout this baseline describes. Plain reference — see above.
    var workoutId: UUID
    var templateId: UUID
    /// The template's `lastModified` when the workout started. Reconciliation
    /// compares against this: if the template has moved on since, the change
    /// set is a conflict rather than something to apply over someone's edit.
    var templateRevision: Date?
    var templateName: String
    var capturedAt: Date

    init(
        id: UUID = UUID(),
        workoutId: UUID,
        templateId: UUID,
        templateRevision: Date? = nil,
        templateName: String,
        capturedAt: Date = .now
    ) {
        self.id = id
        self.workoutId = workoutId
        self.templateId = templateId
        self.templateRevision = templateRevision
        self.templateName = templateName
        self.capturedAt = capturedAt
    }
}

/// One planned exercise inside a `WorkoutTemplateBaseline` (#128).
///
/// A workout exercise with no matching baseline row was added mid-workout —
/// that absence is precisely how a genuine addition is told apart from a
/// planned one, and it is the signal #129's change detection runs on.
@Model
final class WorkoutExerciseBaseline {
    @Attribute(.unique) var id: UUID
    var workoutId: UUID
    /// The `WorkoutExercise` copied from this plan, when one was created.
    var workoutExerciseId: UUID?
    var sourceTemplateExerciseId: UUID
    var exerciseId: UUID
    /// Stable catalog id, so a baseline still resolves after a reinstall mints
    /// new exercise UUIDs — the identity rule from `infra/MCP_WRITE_PATH.md`.
    var exerciseExternalId: String?
    var exerciseName: String
    var plannedOrder: Int
    var plannedSets: Int
    var plannedReps: Int
    var plannedRestSeconds: Int
    var plannedNotes: String?

    init(
        id: UUID = UUID(),
        workoutId: UUID,
        workoutExerciseId: UUID? = nil,
        sourceTemplateExerciseId: UUID,
        exerciseId: UUID,
        exerciseExternalId: String? = nil,
        exerciseName: String,
        plannedOrder: Int,
        plannedSets: Int,
        plannedReps: Int,
        plannedRestSeconds: Int,
        plannedNotes: String? = nil
    ) {
        self.id = id
        self.workoutId = workoutId
        self.workoutExerciseId = workoutExerciseId
        self.sourceTemplateExerciseId = sourceTemplateExerciseId
        self.exerciseId = exerciseId
        self.exerciseExternalId = exerciseExternalId
        self.exerciseName = exerciseName
        self.plannedOrder = plannedOrder
        self.plannedSets = plannedSets
        self.plannedReps = plannedReps
        self.plannedRestSeconds = plannedRestSeconds
        self.plannedNotes = plannedNotes
    }
}

/// The plan for one exercise, as shown on the workout screen (#144).
///
/// A plain value projected from `WorkoutExerciseBaseline` so views never touch
/// a SwiftData model, and so "there is no plan" is expressible as nil rather
/// than as a row of zeroes.
struct PlannedTarget: Equatable, Sendable {
    let sets: Int
    let reps: Int
    let restSeconds: Int
    let notes: String?

    /// e.g. "3 × 12 · 90s rest" — the whole plan in one glanceable line.
    var summary: String {
        let rest = restSeconds > 0 ? " · \(restSeconds)s rest" : ""
        return "\(sets) × \(reps)\(rest)"
    }
}
