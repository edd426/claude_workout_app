import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@Suite("HomeViewModel Tests")
@MainActor
struct HomeViewModelTests {

    @Test("loadTemplates populates templates list")
    func loadTemplatesPopulatesList() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let template = TestFixtures.makeTemplate(name: "Push Day")
        context.insert(template)
        try context.save()

        let repo = MockTemplateRepository()
        repo.templates = [template]
        let vm = HomeViewModel(templateRepository: repo)

        await vm.loadTemplates()

        #expect(vm.templates.count == 1)
    }

    @Test("loadTemplates with error sets errorMessage")
    func loadTemplatesErrorSetsMessage() async {
        let repo = MockTemplateRepository()
        repo.errorToThrow = NSError(domain: "test", code: 1)
        let vm = HomeViewModel(templateRepository: repo)

        await vm.loadTemplates()

        #expect(vm.errorMessage != nil)
    }

    @Test("initial state has no active workout")
    func initialStateHasNoActiveWorkout() {
        let vm = HomeViewModel(templateRepository: MockTemplateRepository())
        #expect(vm.templates.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test("createAdHocWorkout returns workout with Quick Workout name")
    func createAdHocWorkoutReturnsNamedWorkout() async throws {
        let workoutRepo = MockWorkoutRepository()
        let vm = HomeViewModel(
            templateRepository: MockTemplateRepository(),
            workoutRepository: workoutRepo
        )

        let workout = try await vm.createAdHocWorkout()

        #expect(workout.name == "Quick Workout")
        #expect(workout.templateId == nil)
        #expect(workoutRepo.saveCallCount == 1)
    }

    @Test("createAdHocWorkout saves workout to repository")
    func createAdHocWorkoutSavesToRepository() async throws {
        let workoutRepo = MockWorkoutRepository()
        let vm = HomeViewModel(
            templateRepository: MockTemplateRepository(),
            workoutRepository: workoutRepo
        )

        _ = try await vm.createAdHocWorkout()

        #expect(workoutRepo.savedWorkouts.count == 1)
        #expect(workoutRepo.savedWorkouts.first?.name == "Quick Workout")
    }
}
