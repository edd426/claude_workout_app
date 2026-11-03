import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

/// Template-exercise alternatives: "if the rack is taken, do this instead".
/// Keyed to their template exercise by plain UUID, so nothing deletes them
/// automatically — orphan cleanup on template save/delete is load-bearing.
@Suite("ExerciseAlternativeRepository Tests")
@MainActor
struct ExerciseAlternativeRepositoryTests {

    @MainActor
    final class ChangeCounter {
        var count = 0
    }

    private struct Setup {
        let container: ModelContainer
        let context: ModelContext
        let alternatives: SwiftDataExerciseAlternativeRepository
        let templates: SwiftDataTemplateRepository
        let changes: ChangeCounter
    }

    private func makeSetup() throws -> Setup {
        let container = try makeTestContainer()
        let context = container.mainContext
        let counter = ChangeCounter()
        return Setup(
            container: container,
            context: context,
            alternatives: SwiftDataExerciseAlternativeRepository(
                context: context,
                onDeletion: { counter.count += 1 }
            ),
            templates: SwiftDataTemplateRepository(context: context),
            changes: counter
        )
    }

    /// A saved template with one template exercise per name.
    private func makeTemplate(_ setup: Setup, exercises names: [String]) async throws -> WorkoutTemplate {
        let template = WorkoutTemplate(name: "Lower A")
        for (index, name) in names.enumerated() {
            let exercise = Exercise(name: name, isCustom: false, externalId: name.replacingOccurrences(of: " ", with: "_"))
            setup.context.insert(exercise)
            template.exercises.append(TemplateExercise(order: index, exercise: exercise, defaultSets: 3, defaultReps: 8))
        }
        try await setup.templates.save(template)
        return template
    }

    @Test("Alternatives for a template exercise come back in order")
    func alternativesAreOrdered() async throws {
        let setup = try makeSetup()
        let teId = UUID()
        try await setup.alternatives.save(ExerciseAlternative(templateExerciseId: teId, externalId: "C", order: 2))
        try await setup.alternatives.save(ExerciseAlternative(templateExerciseId: teId, externalId: "A", order: 0))
        try await setup.alternatives.save(ExerciseAlternative(templateExerciseId: teId, externalId: "B", order: 1))
        try await setup.alternatives.save(ExerciseAlternative(templateExerciseId: UUID(), externalId: "Other", order: 0))

        let listed = try await setup.alternatives.alternatives(forTemplateExercise: teId)
        #expect(listed.map(\.externalId) == ["A", "B", "C"])
    }

    @Test("Replace is a full replace, renumbered from 0 in the given order")
    func replaceIsFullReplace() async throws {
        let setup = try makeSetup()
        let teId = UUID()
        try await setup.alternatives.replaceAlternatives(
            forTemplateExercise: teId,
            with: [AlternativeSpec(externalId: "Leg_Press"), AlternativeSpec(externalId: "Hack_Squat")]
        )

        try await setup.alternatives.replaceAlternatives(
            forTemplateExercise: teId,
            with: [AlternativeSpec(externalId: "Goblet_Squat", note: "if both are taken"), AlternativeSpec(externalId: "Leg_Press")]
        )

        let listed = try await setup.alternatives.alternatives(forTemplateExercise: teId)
        #expect(listed.map(\.externalId) == ["Goblet_Squat", "Leg_Press"])
        #expect(listed.map(\.order) == [0, 1])
        #expect(listed.first?.note == "if both are taken")
        #expect(try await setup.alternatives.fetchAll().count == 2)
    }

    @Test("Replacing with an empty list clears the alternatives")
    func replaceWithEmptyClears() async throws {
        let setup = try makeSetup()
        let teId = UUID()
        try await setup.alternatives.replaceAlternatives(forTemplateExercise: teId, with: [AlternativeSpec(externalId: "Leg_Press")])

        try await setup.alternatives.replaceAlternatives(forTemplateExercise: teId, with: [])

        #expect(try await setup.alternatives.alternatives(forTemplateExercise: teId).isEmpty)
        #expect(setup.changes.count >= 1, "a removal leaves no pending row, so it must flag the push itself")
    }

    @Test("Replace touches only the named template exercise")
    func replaceIsScoped() async throws {
        let setup = try makeSetup()
        let first = UUID()
        let second = UUID()
        try await setup.alternatives.replaceAlternatives(forTemplateExercise: first, with: [AlternativeSpec(externalId: "A")])
        try await setup.alternatives.replaceAlternatives(forTemplateExercise: second, with: [AlternativeSpec(externalId: "B")])

        try await setup.alternatives.replaceAlternatives(forTemplateExercise: first, with: [])

        #expect(try await setup.alternatives.alternatives(forTemplateExercise: second).map(\.externalId) == ["B"])
    }

    @Test("Replaced alternatives are pending so they push")
    func replacedArePending() async throws {
        let setup = try makeSetup()
        let teId = UUID()
        try await setup.alternatives.replaceAlternatives(forTemplateExercise: teId, with: [AlternativeSpec(externalId: "A")])

        #expect(try await setup.alternatives.fetchPending().map(\.externalId) == ["A"])
    }

    @Test("Orphan cleanup removes alternatives whose template exercise is in no template")
    func removeOrphans() async throws {
        let setup = try makeSetup()
        let template = try await makeTemplate(setup, exercises: ["Barbell Squat"])
        let live = try #require(template.exercises.first?.id)
        try await setup.alternatives.replaceAlternatives(forTemplateExercise: live, with: [AlternativeSpec(externalId: "Leg_Press")])
        try await setup.alternatives.replaceAlternatives(forTemplateExercise: UUID(), with: [AlternativeSpec(externalId: "Orphan")])

        let removed = try await setup.alternatives.removeOrphans()

        #expect(removed == 1)
        #expect(try await setup.alternatives.fetchAll().map(\.externalId) == ["Leg_Press"])
    }

    @Test("Saving a template that dropped an exercise cleans up that exercise's alternatives")
    func templateSaveCleansOrphans() async throws {
        let setup = try makeSetup()
        let template = try await makeTemplate(setup, exercises: ["Barbell Squat", "Romanian Deadlift"])
        let sorted = template.exercises.sorted { $0.order < $1.order }
        let kept = sorted[0]
        let dropped = sorted[1]
        try await setup.alternatives.replaceAlternatives(forTemplateExercise: kept.id, with: [AlternativeSpec(externalId: "Leg_Press")])
        try await setup.alternatives.replaceAlternatives(forTemplateExercise: dropped.id, with: [AlternativeSpec(externalId: "Good_Morning")])

        // The detached TemplateExercise row still exists in the store — it is
        // simply no longer in any template. That still counts as orphaned.
        template.exercises.removeAll { $0.id == dropped.id }
        try await setup.templates.save(template)

        #expect(try await setup.alternatives.fetchAll().map(\.externalId) == ["Leg_Press"])
    }

    @Test("Deleting a template cleans up its exercises' alternatives")
    func templateDeleteCleansOrphans() async throws {
        let setup = try makeSetup()
        let doomed = try await makeTemplate(setup, exercises: ["Barbell Squat"])
        let survivor = try await makeTemplate(setup, exercises: ["Bench Press"])
        try await setup.alternatives.replaceAlternatives(
            forTemplateExercise: try #require(doomed.exercises.first?.id), with: [AlternativeSpec(externalId: "Leg_Press")]
        )
        try await setup.alternatives.replaceAlternatives(
            forTemplateExercise: try #require(survivor.exercises.first?.id), with: [AlternativeSpec(externalId: "Dumbbell_Bench_Press")]
        )

        try await setup.templates.delete(doomed)

        #expect(try await setup.alternatives.fetchAll().map(\.externalId) == ["Dumbbell_Bench_Press"])
    }
}
