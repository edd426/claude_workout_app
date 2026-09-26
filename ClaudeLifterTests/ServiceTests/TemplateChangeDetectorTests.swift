import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

/// #129. The rules here are the product, so they are tested directly rather
/// than through a ViewModel: what counts as a deliberate change to a template,
/// and — more importantly — what does not.
@Suite("TemplateChangeDetector Tests")
@MainActor
struct TemplateChangeDetectorTests {

    private struct Scenario {
        let container: ModelContainer
        let workout: Workout
        let template: WorkoutTemplate
        let baseline: WorkoutTemplateBaseline
        var entries: [WorkoutExerciseBaseline]
    }

    /// Builds a workout that started from a template of `plan`, with every
    /// planned exercise present and its sets completed. Individual tests then
    /// deviate from it — that deviation is what is under test.
    private func makeScenario(
        plan: [(name: String, sets: Int, reps: Int, notes: String?)] = [
            ("Trap Bar Deadlift", 3, 5, nil),
            ("Split Squat with Dumbbells", 2, 8, nil),
            ("Seated Leg Curl", 3, 12, nil),
        ]
    ) throws -> Scenario {
        let container = try makeTestContainer()
        let context = container.mainContext

        let template = WorkoutTemplate(name: "Lower B")
        context.insert(template)
        let workout = Workout(name: "Lower B", startedAt: .now, templateId: template.id)
        context.insert(workout)

        let baseline = WorkoutTemplateBaseline(
            workoutId: workout.id,
            templateId: template.id,
            templateRevision: template.lastModified,
            templateName: template.name
        )
        context.insert(baseline)

        var entries: [WorkoutExerciseBaseline] = []
        for (index, planned) in plan.enumerated() {
            let exercise = TestFixtures.makeExercise(name: planned.name)
            exercise.externalId = planned.name.replacingOccurrences(of: " ", with: "_")
            context.insert(exercise)

            let te = TemplateExercise(
                order: index,
                exercise: exercise,
                defaultSets: planned.sets,
                defaultReps: planned.reps,
                notes: planned.notes
            )
            context.insert(te)
            template.exercises.append(te)

            let we = WorkoutExercise(order: index, exercise: exercise, notes: planned.notes)
            context.insert(we)
            for i in 0..<planned.sets {
                let set = WorkoutSet(
                    order: i,
                    weight: 50,
                    weightUnit: .kg,
                    reps: planned.reps,
                    isCompleted: true,
                    completedAt: .now
                )
                context.insert(set)
                we.sets.append(set)
            }
            workout.exercises.append(we)

            entries.append(WorkoutExerciseBaseline(
                workoutId: workout.id,
                workoutExerciseId: we.id,
                sourceTemplateExerciseId: te.id,
                exerciseId: exercise.id,
                exerciseExternalId: exercise.externalId,
                exerciseName: exercise.name,
                plannedOrder: index,
                plannedSets: planned.sets,
                plannedReps: planned.reps,
                plannedRestSeconds: 90,
                plannedNotes: planned.notes
            ))
        }
        for entry in entries { context.insert(entry) }
        try context.save()

        return Scenario(
            container: container,
            workout: workout,
            template: template,
            baseline: baseline,
            entries: entries
        )
    }

    private func detect(_ s: Scenario) -> TemplateChangeSet {
        TemplateChangeDetector().detect(
            workout: s.workout,
            baseline: s.baseline,
            entries: s.entries,
            template: s.template
        )
    }

    // MARK: - The null case

    @Test("A workout performed exactly as planned proposes nothing")
    func workoutAsPlannedProposesNothing() throws {
        let s = try makeScenario()
        let result = detect(s)
        #expect(result.isEmpty, "changes: \(result.changes.map(\.id))")
        #expect(result.hasConflict == false)
        withExtendedLifetime(s.container) {}
    }

    // MARK: - The rules that keep it quiet

    @Test("A skipped exercise alone produces no change — not finishing is not removing")
    func skippedExerciseProducesNothing() throws {
        let s = try makeScenario()
        // Barbell Ab Rollout on 2026-08-19: present, untouched, zero completed.
        let skipped = try #require(s.workout.exercises.first { $0.order == 2 })
        for set in skipped.sets {
            set.isCompleted = false
            set.completedAt = nil
        }

        let result = detect(s)

        #expect(result.isEmpty, "changes: \(result.changes.map(\.id))")
        withExtendedLifetime(s.container) {}
    }

    @Test("Logged weights and reps are never diffed against the template")
    func loggedValuesAreNeverDiffed() throws {
        let s = try makeScenario()
        // Auto-fill pre-populates from history, so this is what a normal
        // session looks like — heavier than planned, different rep counts.
        for we in s.workout.exercises {
            for set in we.sets {
                set.weight = 137.5
                set.reps = 3
            }
        }

        let result = detect(s)

        #expect(result.isEmpty, "performance is not a template target")
        withExtendedLifetime(s.container) {}
    }

    @Test("An exercise added but never trained is not proposed")
    func untrainedAdditionIsNotProposed() throws {
        let s = try makeScenario()
        let context = s.container.mainContext
        let extra = TestFixtures.makeExercise(name: "Ab Crunch Machine")
        context.insert(extra)
        let we = WorkoutExercise(order: 3, exercise: extra)
        context.insert(we)
        let set = WorkoutSet(order: 0, weightUnit: .kg)
        context.insert(set)
        we.sets.append(set)
        s.workout.exercises.append(we)

        let result = detect(s)

        #expect(result.isEmpty, "adding an exercise and not doing it is not a plan")
        withExtendedLifetime(s.container) {}
    }

    // MARK: - Additions

    @Test("The 2026-08-19 Lower B case: one addition, zero removals")
    func lowerBAcceptanceCase() throws {
        let s = try makeScenario()
        let context = s.container.mainContext

        // Ab Rollout was present and untouched — a skip, not a removal.
        let rollout = try #require(s.workout.exercises.first { $0.order == 2 })
        for set in rollout.sets {
            set.isCompleted = false
            set.completedAt = nil
        }

        // Ab Crunch Machine was added mid-workout and trained, in every
        // session, and has never made it into the template.
        let crunch = TestFixtures.makeExercise(name: "Ab Crunch Machine")
        crunch.externalId = "Ab_Crunch_Machine"
        context.insert(crunch)
        let we = WorkoutExercise(order: 4, exercise: crunch)
        context.insert(we)
        for i in 0..<3 {
            let set = WorkoutSet(order: i, weight: 50, weightUnit: .kg, reps: 10, isCompleted: true, completedAt: .now)
            context.insert(set)
            we.sets.append(set)
        }
        s.workout.exercises.append(we)

        let result = detect(s)

        #expect(result.changes.count == 1)
        guard case .addedExercise(let added) = try #require(result.changes.first) else {
            Issue.record("expected an addition, got \(result.changes)")
            return
        }
        #expect(added.name == "Ab Crunch Machine")
        #expect(added.externalId == "Ab_Crunch_Machine")
        #expect(added.sets == 3)
        #expect(added.reps == 10)
        withExtendedLifetime(s.container) {}
    }

    @Test("The 2026-08-07 Upper A case: two additions, zero removals")
    func upperAAcceptanceCase() throws {
        let s = try makeScenario(plan: [
            ("Barbell Bench Press", 3, 8, nil),
            ("Lat Pulldown", 3, 10, nil),
            ("Seated Cable Row", 3, 10, nil),
            ("Dumbbell Curl", 3, 12, nil),
            ("Triceps Pushdown", 3, 12, nil),
            ("Lateral Raise", 3, 15, nil),
        ])
        let context = s.container.mainContext

        // Six planned exercises left incomplete.
        for we in s.workout.exercises {
            for set in we.sets {
                set.isCompleted = false
                set.completedAt = nil
            }
        }

        for (index, name) in ["Leverage Chest Press", "Leverage Shoulder Press"].enumerated() {
            let exercise = TestFixtures.makeExercise(name: name)
            context.insert(exercise)
            let we = WorkoutExercise(order: 6 + index, exercise: exercise)
            context.insert(we)
            let set = WorkoutSet(order: 0, weight: 40, weightUnit: .kg, reps: 10, isCompleted: true, completedAt: .now)
            context.insert(set)
            we.sets.append(set)
            s.workout.exercises.append(we)
        }

        let result = detect(s)

        let additions = result.changes.filter { if case .addedExercise = $0 { return true }; return false }
        let removals = result.changes.filter { if case .removedExercise = $0 { return true }; return false }
        #expect(additions.count == 2)
        #expect(removals.isEmpty, "six incomplete exercises must not become removals")
        withExtendedLifetime(s.container) {}
    }

    // MARK: - Removals, reorders, set counts, cues

    @Test("An explicitly removed exercise is proposed as a removal")
    func explicitRemovalIsProposed() throws {
        let s = try makeScenario()
        let removed = try #require(s.workout.exercises.first { $0.order == 1 })
        s.workout.exercises.removeAll { $0.id == removed.id }

        let result = detect(s)

        #expect(result.changes.count == 1)
        guard case .removedExercise(let removal) = try #require(result.changes.first) else {
            Issue.record("expected a removal, got \(result.changes)")
            return
        }
        #expect(removal.name == "Split Squat with Dumbbells")
        withExtendedLifetime(s.container) {}
    }

    @Test("Reordering the planned exercises is proposed once")
    func reorderIsProposed() throws {
        let s = try makeScenario()
        // Seated Leg Curl was performed before Split Squat — the actual
        // 2026-08-19 ordering.
        let sorted = s.workout.exercises.sorted { $0.order < $1.order }
        sorted[1].order = 2
        sorted[2].order = 1

        let result = detect(s)

        let reorders = result.changes.filter { if case .reordered = $0 { return true }; return false }
        #expect(reorders.count == 1)
        withExtendedLifetime(s.container) {}
    }

    @Test("Adding a set row changes the planned set count; leaving one unticked does not")
    func setCountChangeIsExplicit() throws {
        let s = try makeScenario()
        let context = s.container.mainContext
        let we = try #require(s.workout.exercises.first { $0.order == 1 })
        let extra = WorkoutSet(order: 2, weight: 50, weightUnit: .kg, reps: 8)
        context.insert(extra)
        we.sets.append(extra)

        let result = detect(s)

        #expect(result.changes.count == 1)
        guard case .setCountChanged(let change) = try #require(result.changes.first) else {
            Issue.record("expected a set-count change, got \(result.changes)")
            return
        }
        #expect(change.from == 2)
        #expect(change.to == 3)
        withExtendedLifetime(s.container) {}
    }

    @Test("A rewritten cue is proposed; clearing one is not")
    func cueChangeIsProposed() throws {
        let s = try makeScenario(plan: [
            ("Seated Leg Curl", 3, 12, "Ankle 3"),
            ("Trap Bar Deadlift", 3, 5, "Grip bar is down."),
        ])
        let first = try #require(s.workout.exercises.first { $0.order == 0 })
        first.notes = "Ankle 4; Seat 4; Pivot 1"
        let second = try #require(s.workout.exercises.first { $0.order == 1 })
        second.notes = nil

        let result = detect(s)

        #expect(result.changes.count == 1, "a cleared cue is not a template change")
        guard case .cueChanged(let change) = try #require(result.changes.first) else {
            Issue.record("expected a cue change, got \(result.changes)")
            return
        }
        #expect(change.from == "Ankle 3")
        #expect(change.to == "Ankle 4; Seat 4; Pivot 1")
        withExtendedLifetime(s.container) {}
    }

    // MARK: - Conflict

    @Test("A template edited since the workout started raises a conflict")
    func templateEditedSinceStartConflicts() throws {
        let s = try makeScenario()
        // Someone edited the template while the workout ran — the Coach, the
        // MCP inbox, or the template editor.
        s.template.lastModified = Date(timeIntervalSinceNow: 60)

        let result = detect(s)

        #expect(result.hasConflict, "applying over a newer template would silently overwrite it")
        withExtendedLifetime(s.container) {}
    }

    @Test("An unchanged template does not raise a conflict")
    func unchangedTemplateHasNoConflict() throws {
        let s = try makeScenario()
        #expect(detect(s).hasConflict == false)
        withExtendedLifetime(s.container) {}
    }
}
