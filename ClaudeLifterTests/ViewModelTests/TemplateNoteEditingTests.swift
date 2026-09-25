import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

/// Reports 31A4983B and E26BBFAA (Hammer Curls, 2026-09-04): "I don't seem to
/// be able to edit the AI notes." The template's note for an exercise — written
/// by the Coach over MCP — arrived read-only, so a wrong one ("with barbells"
/// for a dumbbell curl) could only be complained about.
///
/// It is now edited as this workout's copy, and the existing post-workout
/// review (#129/#130) offers the edit for the template, where the revision
/// check guards against the Coach or the inbox having changed it meanwhile.
@Suite("Editing the template note mid-workout (reports 31A4983B, E26BBFAA)")
@MainActor
struct TemplateNoteEditingTests {

    private struct Fixture {
        let container: ModelContainer
        let exercise: Exercise
        let template: WorkoutTemplate
        let templateRepository: MockTemplateRepository
        let vm: ActiveWorkoutViewModel
    }

    private func makeStartedWorkout(
        templateNote: String? = "Stand tall, barbell at arm's length"
    ) async throws -> Fixture {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = TestFixtures.makeExercise(name: "Hammer Curls")
        context.insert(exercise)
        let template = TestFixtures.makeTemplate(name: "Friday Pump")
        context.insert(template)
        let te = TemplateExercise(
            order: 0, exercise: exercise, defaultSets: 3, defaultReps: 10,
            notes: templateNote
        )
        context.insert(te)
        template.exercises.append(te)
        try context.save()

        let templateRepo = MockTemplateRepository()
        templateRepo.templates = [template]
        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService(),
            exerciseRepository: MockExerciseRepository(),
            templateRepository: templateRepo,
            baselineRepository: MockTemplateBaselineRepository()
        )
        await vm.startWorkout()
        return Fixture(
            container: container,
            exercise: exercise,
            template: template,
            templateRepository: templateRepo,
            vm: vm
        )
    }

    @Test("the template note arrives on the workout's copy")
    func templateNoteIsCopiedToSession() async throws {
        let f = try await makeStartedWorkout()
        let we = try #require(f.vm.workout?.exercises.first)

        #expect(we.notes == "Stand tall, barbell at arm's length")
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("editing it changes this workout's copy and leaves the user's own note alone")
    func editWritesSessionCopyOnly() async throws {
        let f = try await makeStartedWorkout()
        f.exercise.notes = "Seat 3"
        let we = try #require(f.vm.workout?.exercises.first)

        f.vm.updateTemplateNote(we, notes: "Stand tall, a dumbbell in each hand")

        #expect(we.notes == "Stand tall, a dumbbell in each hand")
        #expect(f.exercise.notes == "Seat 3", "The machine note is a different note")
        #expect(f.vm.workout?.syncStatus == .pending)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("editing it does not write the template behind the review's back")
    func editDoesNotTouchTemplateDirectly() async throws {
        let f = try await makeStartedWorkout()
        let we = try #require(f.vm.workout?.exercises.first)
        let saveCountBefore = f.templateRepository.saveCallCount

        f.vm.updateTemplateNote(we, notes: "Stand tall, a dumbbell in each hand")
        await f.vm.awaitPendingSave()

        // A direct write would move the template's revision and turn the
        // post-workout review into a conflict for the user's own edit.
        #expect(f.template.exercises.first?.notes == "Stand tall, barbell at arm's length")
        #expect(f.templateRepository.saveCallCount == saveCountBefore)
        withExtendedLifetime(f.container) {}
    }

    @Test("an emptied note is stored as nil")
    func emptiedNoteIsNil() async throws {
        let f = try await makeStartedWorkout()
        let we = try #require(f.vm.workout?.exercises.first)

        f.vm.updateTemplateNote(we, notes: "  \n ")

        #expect(we.notes == nil)
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }

    @Test("finishing offers the edited note for the template")
    func finishingOffersTheEditForTheTemplate() async throws {
        let f = try await makeStartedWorkout()
        let we = try #require(f.vm.workout?.exercises.first)
        for set in we.sets { f.vm.completeSet(set) }

        f.vm.updateTemplateNote(we, notes: "Stand tall, a dumbbell in each hand")
        await f.vm.finishWorkout()
        await f.vm.awaitPostCommitWork()

        let changeSet = try #require(f.vm.completionSummary?.templateChangeSet)
        let cue = changeSet.changes.compactMap { change -> String? in
            guard case .cueChanged(let c) = change else { return nil }
            return c.to
        }
        #expect(cue == ["Stand tall, a dumbbell in each hand"])
        await f.vm.awaitPendingSave()
        withExtendedLifetime(f.container) {}
    }
}
