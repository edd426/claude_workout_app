import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

@MainActor
private final class MockInboxApprovalManager: InboxApprovalManaging {
    var approvals: [InboxOperationDTO] = []
    var approvedIDs: [String] = []
    var declinedIDs: [String] = []

    func fetchPendingApprovals() async throws -> [InboxOperationDTO] {
        approvals
    }

    func approve(_ operation: InboxOperationDTO) async throws {
        approvedIDs.append(operation.id)
    }

    func decline(_ operation: InboxOperationDTO) async throws {
        declinedIDs.append(operation.id)
    }
}

private func approvalOperation(id: String = "approval") -> InboxOperationDTO {
    InboxOperationDTO(
        id: id,
        createdAt: "2026-07-27T12:00:00.000Z",
        op: "deleteTemplate",
        payload: .object([
            "id": .string(UUID().uuidString),
            "name": .string("Push Day"),
        ]),
        requiresApproval: true,
        status: "awaitingApproval",
        appliedAt: nil,
        error: nil
    )
}

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

@Suite("InboxApprovalViewModel Tests")
@MainActor
struct InboxApprovalViewModelTests {
    @Test("load re-presents server-durable awaiting approvals")
    func loadsAwaitingApprovals() async {
        let manager = MockInboxApprovalManager()
        manager.approvals = [approvalOperation(id: "restart-approval")]
        let vm = InboxApprovalViewModel(manager: manager)

        await vm.load()

        #expect(vm.approvals.map(\.id) == ["restart-approval"])
    }

    @Test("approve delegates and removes only the decided approval")
    func approvesOneOperation() async {
        let manager = MockInboxApprovalManager()
        let first = approvalOperation(id: "first")
        let second = approvalOperation(id: "second")
        manager.approvals = [first, second]
        let vm = InboxApprovalViewModel(manager: manager)
        await vm.load()

        await vm.approve(first)

        #expect(manager.approvedIDs == ["first"])
        #expect(vm.approvals.map(\.id) == ["second"])
    }

    @Test("decline delegates and removes only the decided approval")
    func declinesOneOperation() async {
        let manager = MockInboxApprovalManager()
        let first = approvalOperation(id: "first")
        let second = approvalOperation(id: "second")
        manager.approvals = [first, second]
        let vm = InboxApprovalViewModel(manager: manager)
        await vm.load()

        await vm.decline(second)

        #expect(manager.declinedIDs == ["second"])
        #expect(vm.approvals.map(\.id) == ["first"])
    }
}
