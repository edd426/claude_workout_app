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

    var decidedBatches: [[InboxDecision]] = []
    var decideError: Error?
    /// Consumed one per call, before `decideError`. nil means succeed.
    var decideErrorQueue: [Error?] = []

    func decide(_ decisions: [InboxDecision]) async throws {
        if !decideErrorQueue.isEmpty {
            if let queued = decideErrorQueue.removeFirst() { throw queued }
        } else if let decideError {
            throw decideError
        }
        decidedBatches.append(decisions)
    }
}

@MainActor
private final class MockPreviewBuilder: InboxChangePreviewBuilding {
    var previewedIDs: [String] = []

    func preview(for operation: InboxOperationDTO) async -> InboxChangePreview {
        previewedIDs.append(operation.id)
        return InboxChangePreview(
            title: "Preview \(operation.id)",
            summary: "summary",
            lines: [],
            isDestructive: false
        )
    }
}

private struct StubError: LocalizedError {
    var errorDescription: String? { "network down" }
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

    @Test("failed insight dismissal reports the failure and keeps the insight unread")
    func failedInsightDismissalKeepsInsightUnread() async {
        let insight = TestFixtures.makeInsight(content: "Add a recovery day")
        let insightRepo = MockInsightRepository()
        insightRepo.insights = [insight]
        insightRepo.errorToThrow = NSError(domain: "test", code: 1)
        let vm = HomeViewModel(templateRepository: MockTemplateRepository())

        let dismissed = await vm.dismissInsight(insight, using: insightRepo)

        #expect(dismissed == false)
        #expect(insight.isRead == false)
        #expect(insightRepo.markedReadInsights.isEmpty)
        #expect(vm.errorMessage == "Could not dismiss this insight. Try again.")
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

@Suite("InboxApprovalViewModel batch decisions (#153)")
@MainActor
struct InboxApprovalBatchTests {
    @Test("load builds a preview for every awaiting approval")
    func loadsPreviews() async {
        let manager = MockInboxApprovalManager()
        manager.approvals = [approvalOperation(id: "a"), approvalOperation(id: "b")]
        let previews = MockPreviewBuilder()
        let vm = InboxApprovalViewModel(manager: manager, previewBuilder: previews)

        await vm.load()

        #expect(previews.previewedIDs == ["a", "b"])
        #expect(vm.preview(for: manager.approvals[0])?.title == "Preview a")
    }

    @Test("staging does not touch the manager; commit sends one batch in list order")
    func commitSendsOneBatch() async {
        let manager = MockInboxApprovalManager()
        let a = approvalOperation(id: "a")
        let b = approvalOperation(id: "b")
        let c = approvalOperation(id: "c")
        manager.approvals = [a, b, c]
        let vm = InboxApprovalViewModel(manager: manager)
        await vm.load()

        vm.stage(c, .decline)
        vm.stage(a, .approve)
        #expect(manager.decidedBatches.isEmpty)
        #expect(vm.stagedCount == 2)
        #expect(vm.hasUndecided)

        await vm.commit()

        #expect(manager.decidedBatches.count == 1)
        #expect(manager.decidedBatches[0].map(\.operation.id) == ["a", "c"])
        #expect(manager.decidedBatches[0].map(\.verdict) == [.approve, .decline])
        #expect(vm.approvals.map(\.id) == ["b"])
        #expect(vm.stagedCount == 0)
        #expect(manager.approvedIDs.isEmpty && manager.declinedIDs.isEmpty)
    }

    @Test("stageAll then commit decides everything at once")
    func approveAll() async {
        let manager = MockInboxApprovalManager()
        manager.approvals = [approvalOperation(id: "a"), approvalOperation(id: "b")]
        let vm = InboxApprovalViewModel(manager: manager)
        await vm.load()

        vm.stageAll(.approve)
        await vm.commit()

        #expect(manager.decidedBatches.count == 1)
        #expect(manager.decidedBatches[0].map(\.verdict) == [.approve, .approve])
        #expect(vm.approvals.isEmpty)
        #expect(!vm.hasUndecided)
    }

    @Test("commit with nothing staged is a no-op")
    func commitNothing() async {
        let manager = MockInboxApprovalManager()
        manager.approvals = [approvalOperation(id: "a")]
        let vm = InboxApprovalViewModel(manager: manager)
        await vm.load()

        await vm.commit()

        #expect(manager.decidedBatches.isEmpty)
        #expect(vm.approvals.count == 1)
    }

    @Test("a failed commit keeps the verdicts staged and the operations listed")
    func failedCommitKeepsState() async {
        let manager = MockInboxApprovalManager()
        let a = approvalOperation(id: "a")
        manager.approvals = [a]
        manager.decideError = StubError()
        let vm = InboxApprovalViewModel(manager: manager)
        await vm.load()

        vm.stage(a, .approve)
        await vm.commit()

        #expect(vm.errorMessage == "network down")
        #expect(vm.approvals.map(\.id) == ["a"])
        #expect(vm.verdict(for: a) == .approve)
    }

    @Test("a commit that collides with a background sync retries once")
    func retriesWhenSyncInProgress() async {
        let manager = MockInboxApprovalManager()
        let a = approvalOperation(id: "a")
        manager.approvals = [a]
        manager.decideErrorQueue = [SyncError.syncInProgress, nil]
        let vm = InboxApprovalViewModel(manager: manager)
        await vm.load()

        vm.stage(a, .approve)
        await vm.commit()

        #expect(vm.errorMessage == nil)
        #expect(manager.decidedBatches.count == 1)
        #expect(vm.approvals.isEmpty)
    }

    @Test("unstage clears a verdict; a server refresh drops verdicts for vanished operations")
    func unstageAndRefresh() async {
        let manager = MockInboxApprovalManager()
        let a = approvalOperation(id: "a")
        let b = approvalOperation(id: "b")
        manager.approvals = [a, b]
        let vm = InboxApprovalViewModel(manager: manager)
        await vm.load()

        vm.stage(a, .approve)
        vm.stage(b, .decline)
        vm.unstage(a)
        #expect(vm.verdict(for: a) == nil)

        vm.replaceApprovals([a])
        #expect(vm.verdict(for: b) == nil)
        #expect(vm.stagedCount == 0)
    }
}
