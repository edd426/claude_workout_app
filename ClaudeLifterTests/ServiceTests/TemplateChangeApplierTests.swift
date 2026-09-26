import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

/// #130's apply step. The acceptance criteria that matter are the negative
/// ones: declining changes nothing, and a failure cannot touch the workout.
@Suite("TemplateChangeApplier Tests")
@MainActor
struct TemplateChangeApplierTests {

    private struct Env {
        let container: ModelContainer
        let template: WorkoutTemplate
        let templateRepo: MockTemplateRepository
        let exerciseRepo: MockExerciseRepository
        let applier: TemplateChangeApplier
        let changeSet: TemplateChangeSet
        var exercises: [Exercise]
    }

    private func makeEnv() throws -> Env {
        let container = try makeTestContainer()
        let context = container.mainContext

        let template = WorkoutTemplate(name: "Lower B")
        context.insert(template)

        var exercises: [Exercise] = []
        for (index, name) in ["Trap Bar Deadlift", "Split Squat with Dumbbells", "Seated Leg Curl"].enumerated() {
            let exercise = TestFixtures.makeExercise(name: name)
            exercise.externalId = name.replacingOccurrences(of: " ", with: "_")
            context.insert(exercise)
            exercises.append(exercise)
            let te = TemplateExercise(order: index, exercise: exercise, defaultSets: 3, defaultReps: 10)
            context.insert(te)
            template.exercises.append(te)
        }
        try context.save()

        let templateRepo = MockTemplateRepository()
        templateRepo.templates = [template]
        let exerciseRepo = MockExerciseRepository()
        exerciseRepo.exercises = exercises

        return Env(
            container: container,
            template: template,
            templateRepo: templateRepo,
            exerciseRepo: exerciseRepo,
            applier: TemplateChangeApplier(
                templateRepository: templateRepo,
                exerciseRepository: exerciseRepo
            ),
            changeSet: TemplateChangeSet(
                templateId: template.id,
                templateName: template.name,
                changes: [],
                capturedRevision: template.lastModified,
                hasConflict: false
            ),
            exercises: exercises
        )
    }

    @Test("Applying nothing writes nothing — declining leaves the template untouched")
    func applyingNothingWritesNothing() async throws {
        let env = try makeEnv()
        let before = env.template.lastModified

        try await env.applier.apply([], from: env.changeSet, capturedRevision: before)

        #expect(env.templateRepo.savedTemplates.isEmpty)
        #expect(env.template.lastModified == before)
        #expect(env.template.exercises.count == 3)
        withExtendedLifetime(env.container) {}
    }

    @Test("An addition is appended and resolved by externalId")
    func additionIsAppended() async throws {
        var env = try makeEnv()
        let context = env.container.mainContext
        let crunch = TestFixtures.makeExercise(name: "Ab Crunch Machine")
        crunch.externalId = "Ab_Crunch_Machine"
        context.insert(crunch)
        try context.save()
        env.exerciseRepo.exercises.append(crunch)

        let change = TemplateChange.addedExercise(.init(
            exerciseId: crunch.id,
            externalId: "Ab_Crunch_Machine",
            name: "Ab Crunch Machine",
            order: 4,
            sets: 3,
            reps: 10,
            restSeconds: 90
        ))

        try await env.applier.apply([change], from: env.changeSet, capturedRevision: env.template.lastModified)

        #expect(env.template.exercises.count == 4)
        let added = try #require(env.template.exercises.sorted { $0.order < $1.order }.last)
        #expect(added.exercise?.name == "Ab Crunch Machine")
        #expect(added.defaultSets == 3)
        #expect(added.defaultReps == 10)
        #expect(added.order == 3, "orders are normalised, never left with gaps")
        #expect(env.template.syncStatus == .pending)
        withExtendedLifetime(env.container) {}
    }

    @Test("A removal drops the exercise and renumbers the survivors")
    func removalRenumbers() async throws {
        let env = try makeEnv()
        let middle = try #require(env.template.exercises.first { $0.order == 1 })

        let change = TemplateChange.removedExercise(.init(
            sourceTemplateExerciseId: middle.id,
            exerciseId: env.exercises[1].id,
            name: "Split Squat with Dumbbells"
        ))
        try await env.applier.apply([change], from: env.changeSet, capturedRevision: env.template.lastModified)

        let remaining = env.template.exercises.sorted { $0.order < $1.order }
        #expect(remaining.count == 2)
        #expect(remaining.map(\.order) == [0, 1])
        #expect(remaining.allSatisfy { $0.exercise?.name != "Split Squat with Dumbbells" })
        withExtendedLifetime(env.container) {}
    }

    @Test("A reorder applies the workout's order and keeps unmentioned exercises")
    func reorderKeepsUnmentioned() async throws {
        let env = try makeEnv()
        let sorted = env.template.exercises.sorted { $0.order < $1.order }
        // Only the first two are mentioned, swapped.
        let change = TemplateChange.reordered(.init(
            sourceTemplateExerciseIds: [sorted[1].id, sorted[0].id],
            names: ["Split Squat with Dumbbells", "Trap Bar Deadlift"]
        ))

        try await env.applier.apply([change], from: env.changeSet, capturedRevision: env.template.lastModified)

        let after = env.template.exercises.sorted { $0.order < $1.order }
        #expect(after.count == 3, "an exercise the workout never mentioned must not vanish")
        #expect(after[0].exercise?.name == "Split Squat with Dumbbells")
        #expect(after[1].exercise?.name == "Trap Bar Deadlift")
        #expect(after[2].exercise?.name == "Seated Leg Curl")
        withExtendedLifetime(env.container) {}
    }

    @Test("Set count and cue changes are applied to the right exercise")
    func setCountAndCueApplied() async throws {
        let env = try makeEnv()
        let target = try #require(env.template.exercises.first { $0.order == 2 })

        try await env.applier.apply(
            [
                .setCountChanged(.init(
                    sourceTemplateExerciseId: target.id,
                    name: "Seated Leg Curl",
                    from: 3,
                    to: 4
                )),
                .cueChanged(.init(
                    sourceTemplateExerciseId: target.id,
                    name: "Seated Leg Curl",
                    from: nil,
                    to: "Ankle 4; Seat 4; Pivot 1"
                )),
            ],
            from: env.changeSet,
            capturedRevision: env.template.lastModified
        )

        #expect(target.defaultSets == 4)
        #expect(target.notes == "Ankle 4; Seat 4; Pivot 1")
        #expect(env.template.exercises.first { $0.order == 0 }?.defaultSets == 3)
        withExtendedLifetime(env.container) {}
    }

    @Test("A template changed since the workout started is refused, not overwritten")
    func conflictIsRefused() async throws {
        let env = try makeEnv()
        let captured = env.template.lastModified
        env.template.lastModified = Date(timeIntervalSinceNow: 120)
        let removal = try #require(env.template.exercises.first)

        await #expect(throws: TemplateChangeApplyError.conflict) {
            try await env.applier.apply(
                [.removedExercise(.init(
                    sourceTemplateExerciseId: removal.id,
                    exerciseId: env.exercises[0].id,
                    name: "Trap Bar Deadlift"
                ))],
                from: env.changeSet,
                capturedRevision: captured
            )
        }
        #expect(env.template.exercises.count == 3, "nothing applied")
        #expect(env.templateRepo.savedTemplates.isEmpty)
        withExtendedLifetime(env.container) {}
    }

    @Test("An unresolvable addition aborts before anything is written")
    func unresolvableAdditionAbortsWholeApply() async throws {
        let env = try makeEnv()
        let removal = try #require(env.template.exercises.first { $0.order == 0 })

        // A valid removal alongside an addition that cannot resolve. The
        // removal must not land on its own.
        await #expect(throws: TemplateChangeApplyError.unresolvedExercise("Ghost Machine")) {
            try await env.applier.apply(
                [
                    .removedExercise(.init(
                        sourceTemplateExerciseId: removal.id,
                        exerciseId: env.exercises[0].id,
                        name: "Trap Bar Deadlift"
                    )),
                    .addedExercise(.init(
                        exerciseId: UUID(),
                        externalId: "Ghost_Machine",
                        name: "Ghost Machine",
                        order: 3,
                        sets: 3,
                        reps: 10,
                        restSeconds: 90
                    )),
                ],
                from: env.changeSet,
                capturedRevision: env.template.lastModified
            )
        }

        #expect(env.template.exercises.count == 3, "all or nothing")
        #expect(env.templateRepo.savedTemplates.isEmpty)
        withExtendedLifetime(env.container) {}
    }

    @Test("A missing template is reported without crashing")
    func missingTemplateIsReported() async throws {
        let env = try makeEnv()
        env.templateRepo.templates = []

        await #expect(throws: TemplateChangeApplyError.templateNotFound) {
            try await env.applier.apply(
                [.cueChanged(.init(
                    sourceTemplateExerciseId: UUID(),
                    name: "Gone",
                    from: nil,
                    to: "x"
                ))],
                from: env.changeSet,
                capturedRevision: nil
            )
        }
        withExtendedLifetime(env.container) {}
    }
}
