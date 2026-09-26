import Foundation

/// One proposed change to a template, inferred from a finished workout (#129).
///
/// Every case represents something the user did *deliberately* — added an
/// exercise and trained it, removed one, reordered, changed how many sets were
/// planned, or rewrote a cue. Nothing here is inferred from performance.
enum TemplateChange: Identifiable, Equatable, Sendable {
    case addedExercise(AddedExercise)
    case removedExercise(RemovedExercise)
    case reordered(Reorder)
    case setCountChanged(SetCountChange)
    case cueChanged(CueChange)

    struct AddedExercise: Equatable, Sendable {
        let exerciseId: UUID
        let externalId: String?
        let name: String
        let order: Int
        let sets: Int
        let reps: Int?
        let restSeconds: Int
    }

    struct RemovedExercise: Equatable, Sendable {
        let sourceTemplateExerciseId: UUID
        let exerciseId: UUID
        let name: String
    }

    struct Reorder: Equatable, Sendable {
        /// Planned exercises in the order the workout actually ran them.
        let sourceTemplateExerciseIds: [UUID]
        let names: [String]
    }

    struct SetCountChange: Equatable, Sendable {
        let sourceTemplateExerciseId: UUID
        let name: String
        let from: Int
        let to: Int
    }

    struct CueChange: Equatable, Sendable {
        let sourceTemplateExerciseId: UUID
        let name: String
        let from: String?
        let to: String?
    }

    var id: String {
        switch self {
        case .addedExercise(let c): return "added-\(c.exerciseId)"
        case .removedExercise(let c): return "removed-\(c.sourceTemplateExerciseId)"
        case .reordered: return "reordered"
        case .setCountChanged(let c): return "sets-\(c.sourceTemplateExerciseId)"
        case .cueChanged(let c): return "cue-\(c.sourceTemplateExerciseId)"
        }
    }
}

/// The outcome of comparing a finished workout to the template it started from.
struct TemplateChangeSet: Equatable, Sendable {
    let templateId: UUID
    let templateName: String
    let changes: [TemplateChange]
    /// The template's `lastModified` when the workout started. Carried here so
    /// apply can re-check for a conflict at the moment the user taps Apply,
    /// which may be minutes after detection ran.
    let capturedRevision: Date?
    /// The template moved on since this workout started, so applying these
    /// changes would overwrite an edit made elsewhere — from the Coach, the MCP
    /// inbox, or the template editor. Surfaced instead of silently winning.
    let hasConflict: Bool

    var isEmpty: Bool { changes.isEmpty }
}

/// Compares a finished workout against the plan it started from (#129).
///
/// Pure and synchronous: no repositories, no SwiftData fetches, no clock. It
/// takes the workout, the frozen baseline (#128) and the template as it stands
/// now, and returns proposals. That makes every rule below directly testable,
/// which matters because the rules are the whole product.
///
/// ## What is deliberately NOT detected
///
/// - **Logged weights and reps, ever.** `AutoFillService` pre-populates sets
///   from history, so a set's values reflect what the user did last time, not
///   what the template asked for. Diffing them against template defaults is
///   semantically meaningless — it would propose a "change" on every workout.
/// - **Skipped or incomplete exercises as removals.** Not finishing an exercise
///   is the most ordinary thing in a gym. Only an explicit removal counts.
/// - **Target reps and rest seconds.** There is no UI that changes either
///   mid-workout — `WorkoutExercise.restSeconds` is written once at
///   construction and never mutated — so any difference would be noise, not
///   intent. When such a control exists, this is where it plugs in.
struct TemplateChangeDetector {

    /// - Parameters:
    ///   - workout: the finished session.
    ///   - baseline: the plan frozen at start, and its per-exercise entries.
    ///   - template: the template **as it stands now**, for conflict detection.
    func detect(
        workout: Workout,
        baseline: WorkoutTemplateBaseline,
        entries: [WorkoutExerciseBaseline],
        template: WorkoutTemplate
    ) -> TemplateChangeSet {
        var changes: [TemplateChange] = []

        let workoutExercises = workout.exercises.sorted { $0.order < $1.order }
        let entryByWorkoutExerciseId = Dictionary(
            entries.compactMap { entry in
                entry.workoutExerciseId.map { ($0, entry) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        // 1. Additions. An exercise with no baseline entry was added
        //    mid-workout — but only propose it if it was actually trained.
        //    Adding an exercise and leaving it untouched is not a plan.
        for we in workoutExercises where entryByWorkoutExerciseId[we.id] == nil {
            guard let exercise = we.exercise else { continue }
            guard we.sets.contains(where: { $0.isCompleted }) else { continue }
            let completed = we.sets.filter(\.isCompleted)
            changes.append(.addedExercise(.init(
                exerciseId: exercise.id,
                externalId: exercise.externalId,
                name: exercise.name,
                order: we.order,
                sets: completed.count,
                // Modal logged reps, as a starting suggestion only — the user
                // confirms it in review. This is not diffing against a target.
                reps: modalReps(of: completed),
                restSeconds: we.restSeconds
            )))
        }

        // 2. Removals — only explicit ones. A planned exercise whose
        //    WorkoutExercise is gone from the session was removed by hand; one
        //    that is still present but unfinished was merely skipped.
        let survivingWorkoutExerciseIds = Set(workoutExercises.map(\.id))
        for entry in entries.sorted(by: { $0.plannedOrder < $1.plannedOrder }) {
            guard let plannedWorkoutExerciseId = entry.workoutExerciseId else { continue }
            if !survivingWorkoutExerciseIds.contains(plannedWorkoutExerciseId) {
                changes.append(.removedExercise(.init(
                    sourceTemplateExerciseId: entry.sourceTemplateExerciseId,
                    exerciseId: entry.exerciseId,
                    name: entry.exerciseName
                )))
            }
        }

        // 3. Reorder, judged only across the planned exercises that survived.
        //    A mid-workout addition landing at the end is an addition, not a
        //    reordering of the plan.
        let survivingPlanned = workoutExercises.compactMap {
            entryByWorkoutExerciseId[$0.id]
        }
        let plannedOrderIds = survivingPlanned
            .sorted { $0.plannedOrder < $1.plannedOrder }
            .map(\.sourceTemplateExerciseId)
        let actualOrderIds = survivingPlanned.map(\.sourceTemplateExerciseId)
        if plannedOrderIds != actualOrderIds, actualOrderIds.count > 1 {
            changes.append(.reordered(.init(
                sourceTemplateExerciseIds: actualOrderIds,
                names: survivingPlanned.map(\.exerciseName)
            )))
        }

        // 4. Set count — the number of set rows, not how many were completed.
        //    Adding or deleting a row is an explicit act; leaving one unticked
        //    is not.
        for we in workoutExercises {
            guard let entry = entryByWorkoutExerciseId[we.id] else { continue }
            if we.sets.count != entry.plannedSets {
                changes.append(.setCountChanged(.init(
                    sourceTemplateExerciseId: entry.sourceTemplateExerciseId,
                    name: entry.exerciseName,
                    from: entry.plannedSets,
                    to: we.sets.count
                )))
            }
        }

        // 5. Cue text. Rewriting a note during a workout is deliberate, and
        //    it is exactly the machine-setting case from #136.
        for we in workoutExercises {
            guard let entry = entryByWorkoutExerciseId[we.id] else { continue }
            let before = normalized(entry.plannedNotes)
            let after = normalized(we.notes)
            if before != after, after != nil {
                changes.append(.cueChanged(.init(
                    sourceTemplateExerciseId: entry.sourceTemplateExerciseId,
                    name: entry.exerciseName,
                    from: before,
                    to: after
                )))
            }
        }

        return TemplateChangeSet(
            templateId: baseline.templateId,
            templateName: template.name,
            changes: changes,
            capturedRevision: baseline.templateRevision,
            hasConflict: hasConflict(baseline: baseline, template: template)
        )
    }

    /// The template has moved on since the workout started. Compared against
    /// the revision captured at start rather than "is it different from what I
    /// expect", so an edit from the Coach or the MCP inbox is caught too.
    private func hasConflict(
        baseline: WorkoutTemplateBaseline,
        template: WorkoutTemplate
    ) -> Bool {
        guard let captured = baseline.templateRevision else { return false }
        return template.lastModified > captured
    }

    private func normalized(_ value: String?) -> String? {
        guard
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// The rep count performed most often, ties broken by the lower value —
    /// a conservative suggestion for a brand-new template entry.
    private func modalReps(of sets: [WorkoutSet]) -> Int? {
        let reps = sets.compactMap(\.reps)
        guard !reps.isEmpty else { return nil }
        let counts = reps.reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }
        return counts.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
        }?.key
    }
}
