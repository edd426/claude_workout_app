import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

/// Regression tests for Phase 1.5 — every mutation path must update
/// `lastModified` and reset `syncStatus` to `.pending` via `recordChange()`.
/// The original bug (issue #32, closed prematurely) was that set completion,
/// template rename, insight read, and preference upsert all silently skipped
/// this, making sync last-write-wins subtly wrong.
@Suite("lastModified Propagation Tests")
@MainActor
struct LastModifiedPropagationTests {

    // MARK: - Protocol

    @Test("recordChange updates timestamp and marks pending")
    func recordChangeWorks() {
        let workout = Workout(name: "X", startedAt: .now, lastModified: .distantPast)
        workout.syncStatus = .synced
        workout.recordChange()
        #expect(workout.lastModified > .distantPast)
        #expect(workout.syncStatus == .pending)
    }

    // MARK: - ActiveWorkoutViewModel mutation paths

    @Test("completeSet bumps Workout.lastModified")
    func completeSetBumpsLastModified() async throws {
        let (vm, workout, set, container) = try await makeActiveWorkout()
        let before = workout.lastModified
        try await Task.sleep(for: .milliseconds(5))
        vm.completeSet(set)
        #expect(workout.lastModified > before)
        #expect(workout.syncStatus == .pending)
        await vm.awaitPendingSave()
        withExtendedLifetime(container) {}
    }

    @Test("addExercise bumps Workout.lastModified")
    func addExerciseBumpsLastModified() async throws {
        let (vm, workout, _, container) = try await makeActiveWorkout()
        // Exercise must be in the same context as the workout, otherwise
        // SwiftData crashes when setting up the relationship.
        let exercise = Exercise(name: "Overhead Press", isCustom: false)
        container.mainContext.insert(exercise)
        let before = workout.lastModified
        try await Task.sleep(for: .milliseconds(5))
        vm.addExercise(exercise)
        #expect(workout.lastModified > before)
        await vm.awaitPendingSave()
        withExtendedLifetime(container) {}
    }

    @Test("removeExercise bumps Workout.lastModified")
    func removeExerciseBumpsLastModified() async throws {
        let (vm, workout, _, container) = try await makeActiveWorkout()
        let before = workout.lastModified
        try await Task.sleep(for: .milliseconds(5))
        if let we = workout.exercises.first {
            vm.removeExercise(we)
        }
        #expect(workout.lastModified > before)
        await vm.awaitPendingSave()
        withExtendedLifetime(container) {}
    }

    @Test("removeSet bumps Workout.lastModified")
    func removeSetBumpsLastModified() async throws {
        let (vm, workout, _, container) = try await makeActiveWorkout()
        let before = workout.lastModified
        try await Task.sleep(for: .milliseconds(5))
        if let we = workout.exercises.first, let s = we.sets.first {
            vm.removeSet(s, from: we)
        }
        #expect(workout.lastModified > before)
        await vm.awaitPendingSave()
        withExtendedLifetime(container) {}
    }

    @Test("finishWorkout bumps parent template.lastModified")
    func finishBumpsTemplateLastModified() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Bench Press", isCustom: false)
        context.insert(exercise)
        let template = WorkoutTemplate(name: "Push", lastModified: .distantPast)
        template.exercises = [TemplateExercise(order: 0, exercise: exercise, defaultSets: 1, defaultReps: 5)]
        template.syncStatus = .synced
        context.insert(template)
        try context.save()

        let repo = SwiftDataWorkoutRepository(context: context)
        let autoFill = AutoFillService(workoutRepository: repo)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: repo,
            autoFillService: autoFill,
            templateRepository: templateRepo
        )
        await vm.startWorkout()
        // Complete one set so finish doesn't treat as empty.
        if let we = vm.workout?.exercises.first, let s = we.sets.first {
            vm.completeSet(s)
        }

        let beforeTemplate = template.lastModified
        try await Task.sleep(for: .milliseconds(5))
        await vm.finishWorkout()
        #expect(template.lastModified > beforeTemplate,
                "Template.lastModified must update when a workout from it completes")
        #expect(template.syncStatus == .pending)
        withExtendedLifetime(container) {}
    }

    // MARK: - TemplateEditorViewModel

    @Test("TemplateEditor.save bumps template.lastModified")
    func templateEditorSaveBumpsLastModified() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataTemplateRepository(context: context)
        let template = WorkoutTemplate(name: "Old Name", lastModified: .distantPast)
        template.syncStatus = .synced
        context.insert(template)
        try context.save()

        let vm = TemplateEditorViewModel(template: template, templateRepository: repo)
        vm.name = "New Name"
        await vm.save()

        #expect(template.lastModified > .distantPast)
        #expect(template.syncStatus == .pending)
        withExtendedLifetime(container) {}
    }

    // MARK: - InsightRepository

    @Test("markAsRead bumps insight.lastModified")
    func markAsReadBumps() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataInsightRepository(context: context)
        let insight = ProactiveInsight(
            content: "Train legs",
            type: .suggestion,
            lastModified: .distantPast
        )
        insight.syncStatus = .synced
        context.insert(insight)
        try context.save()

        try await repo.markAsRead(insight)
        #expect(insight.lastModified > .distantPast)
        #expect(insight.syncStatus == .pending)
        withExtendedLifetime(container) {}
    }

    // MARK: - TrainingPreferenceRepository

    @Test("preference upsert on existing bumps lastModified")
    func preferenceUpsertBumps() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataTrainingPreferenceRepository(context: context)

        try await repo.upsert(key: "style", value: "hypertrophy", source: "user_stated")
        let first = try await repo.fetchAll().first!
        first.lastModified = .distantPast
        first.syncStatus = .synced
        try context.save()

        try await repo.upsert(key: "style", value: "strength", source: "user_stated")
        let after = try await repo.fetchAll().first!
        #expect(after.value == "strength")
        #expect(after.lastModified > .distantPast)
        #expect(after.syncStatus == .pending)
        withExtendedLifetime(container) {}
    }

    // MARK: - Helpers

    /// Builds a real SwiftData-backed ActiveWorkoutViewModel with one exercise
    /// containing three sets. Returns the container too so the caller can
    /// keep it alive for the duration of the test — otherwise SwiftData
    /// resets the context when the container is released and every model
    /// reference crashes on access.
    private func makeActiveWorkout() async throws -> (ActiveWorkoutViewModel, Workout, WorkoutSet, ModelContainer) {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "Bench", isCustom: false)
        context.insert(exercise)
        let template = WorkoutTemplate(name: "Chest Day")
        template.exercises = [TemplateExercise(order: 0, exercise: exercise, defaultSets: 3, defaultReps: 8)]
        context.insert(template)
        try context.save()

        let repo = SwiftDataWorkoutRepository(context: context)
        let autoFill = AutoFillService(workoutRepository: repo)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let vm = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: repo,
            autoFillService: autoFill,
            templateRepository: templateRepo
        )
        await vm.startWorkout()
        let workout = try #require(vm.workout)
        let set = try #require(workout.exercises.first?.sets.first)
        // Age the timestamp so subsequent mutations can be seen to move it.
        workout.lastModified = .distantPast
        workout.syncStatus = .synced
        return (vm, workout, set, container)
    }
}
