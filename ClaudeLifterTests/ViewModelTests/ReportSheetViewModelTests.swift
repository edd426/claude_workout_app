import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

/// Retains the container alongside the context — a context outliving its
/// container traps message-lessly on iOS 26.
@MainActor
private struct ReportEnv {
    let container: ModelContainer
    let repository: SwiftDataExerciseReportRepository

    init() throws {
        container = try makeTestContainer()
        repository = SwiftDataExerciseReportRepository(context: container.mainContext)
    }
}

@Suite("ReportSheetViewModel Tests")
@MainActor
struct ReportSheetViewModelTests {

    @Test("Submitting stores the captured context, not just the typed text")
    func submitPersistsCapturedContext() async throws {
        let env = try ReportEnv()
        let workoutId = UUID()
        let context = ReportContext(
            exerciseExternalId: "Barbell_Bench_Press_-_Medium_Grip",
            exerciseName: "Barbell Bench Press",
            workoutId: workoutId,
            workoutExerciseId: UUID(),
            templateId: UUID(),
            contextSummary: "Push Day · Barbell Bench Press · 60kg×8 ✓"
        )
        let vm = ReportSheetViewModel(context: context, repository: env.repository)
        vm.category = .wrongExercise
        vm.detail = "This is really the iso-lateral press"
        vm.suggestedReplacement = "Hammer Strength Iso-Lateral Press"

        let saved = await vm.submit()

        #expect(saved)
        let stored = try #require(try await env.repository.fetchAll().first)
        #expect(stored.category == .wrongExercise)
        #expect(stored.detail == "This is really the iso-lateral press")
        #expect(stored.exerciseExternalId == "Barbell_Bench_Press_-_Medium_Grip")
        #expect(stored.workoutId == workoutId)
        #expect(stored.contextSummary == "Push Day · Barbell Bench Press · 60kg×8 ✓")
        #expect(stored.suggestedReplacement == "Hammer Strength Iso-Lateral Press")
        #expect(stored.appVersion != nil)
        #expect(stored.status == .open)
        #expect(stored.syncStatus == .pending)
    }

    @Test("An empty complaint cannot be submitted")
    func blankDetailBlocksSubmit() async throws {
        let env = try ReportEnv()
        let vm = ReportSheetViewModel(
            context: ReportContext(exerciseName: "Squat"),
            repository: env.repository
        )
        vm.detail = "   \n "

        #expect(!vm.canSubmit)
        #expect(await vm.submit() == false)
        #expect(try await env.repository.fetchAll().isEmpty)
    }

    @Test("A replacement typed then hidden by a category change is not stored")
    func replacementIgnoredForCategoriesThatDoNotAskForIt() async throws {
        let env = try ReportEnv()
        let vm = ReportSheetViewModel(
            context: ReportContext(exerciseName: "Squat"),
            repository: env.repository
        )
        vm.category = .swapRequest
        vm.suggestedReplacement = "Leg press"
        vm.category = .bug
        vm.detail = "The set wouldn't tick off"

        #expect(!vm.showsReplacementField)
        #expect(await vm.submit())
        let stored = try #require(try await env.repository.fetchAll().first)
        #expect(stored.suggestedReplacement == nil)
    }

    @Test("The starting category matches how the sheet was opened")
    func defaultCategoryDependsOnEntryPoint() throws {
        let env = try ReportEnv()
        let fromExercise = ReportSheetViewModel(
            context: ReportContext(exerciseName: "Squat"),
            repository: env.repository
        )
        let fromWorkout = ReportSheetViewModel(
            context: ReportContext(workoutId: UUID()),
            repository: env.repository
        )

        #expect(fromExercise.category == .swapRequest)
        #expect(fromWorkout.category == .bug)
    }

    @Test("Exercise context captures externalId and the set state, never the local UUID")
    func exerciseContextCapturesExternalIdAndSets() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "Barbell Bench Press",
            externalId: "Barbell_Bench_Press_-_Medium_Grip"
        )
        context.insert(exercise)
        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise)
        workoutExercise.sets = [
            WorkoutSet(order: 0, weight: 60, reps: 8, isCompleted: true),
            WorkoutSet(order: 1, weight: 60, reps: 6)
        ]
        let workout = Workout(
            name: "Push Day", startedAt: .now, templateId: UUID()
        )
        workout.exercises = [workoutExercise]
        context.insert(workout)

        let reportContext = ReportContext.forExercise(workoutExercise, in: workout)

        #expect(reportContext.exerciseExternalId == "Barbell_Bench_Press_-_Medium_Grip")
        #expect(reportContext.exerciseName == "Barbell Bench Press")
        #expect(reportContext.workoutId == workout.id)
        #expect(reportContext.templateId == workout.templateId)
        let summary = try #require(reportContext.contextSummary)
        #expect(summary.contains("Push Day"))
        #expect(summary.contains("60kg×8 ✓"))
        #expect(summary.contains("60kg×6"))
        _ = container
    }

    @Test("Workout context carries no exercise and still summarizes the session")
    func workoutContextHasNoExercise() throws {
        let container = try makeTestContainer()
        let workout = Workout(name: "Leg Day", startedAt: .now)
        let exercise = Exercise(name: "Back Squat")
        container.mainContext.insert(exercise)
        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise)
        workoutExercise.sets = [WorkoutSet(order: 0, weight: 100, reps: 5, isCompleted: true)]
        workout.exercises = [workoutExercise]
        container.mainContext.insert(workout)

        let reportContext = ReportContext.forWorkout(workout)

        #expect(reportContext.exerciseExternalId == nil)
        #expect(reportContext.subject == "This workout")
        let summary = try #require(reportContext.contextSummary)
        #expect(summary.contains("Leg Day"))
        #expect(summary.contains("1 sets completed"))
        _ = container
    }
}

@Suite("ReportListViewModel Tests")
@MainActor
struct ReportListViewModelTests {

    @Test("Open count and visible list exclude resolved reports")
    func resolvedReportsLeaveTheBacklog() async throws {
        let env = try ReportEnv()
        try await env.repository.save(
            ExerciseReport(category: .bug, detail: "open")
        )
        let resolved = ExerciseReport(category: .bug, detail: "done")
        resolved.status = .resolved
        try await env.repository.save(resolved)

        let vm = ReportListViewModel(repository: env.repository)
        await vm.load()

        #expect(vm.openCount == 1)
        #expect(vm.visibleReports.count == 1)
        // `showsResolved` became a status filter in #146 — the old boolean
        // keyed on a state nothing ever produced.
        vm.statusFilter = .all
        #expect(vm.visibleReports.count == 2)
    }

    @Test("Resolving locally re-queues the report for sync")
    func resolvingLocallyMarksPending() async throws {
        let env = try ReportEnv()
        let report = ExerciseReport(
            category: .bug, detail: "open", syncStatus: .synced
        )
        try await env.repository.save(report)

        let vm = ReportListViewModel(repository: env.repository)
        await vm.load()
        await vm.setStatus(.resolved, for: report)

        #expect(vm.openCount == 0)
        #expect(report.status == .resolved)
        #expect(report.syncStatus == .pending)
    }
}
