import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

/// Retains the ModelContainer for every context-backed inbox test. A context
/// outliving its container traps on-device, so these tests use the shared
/// factory and keep both alive in one environment value.
@MainActor
private struct InboxTestEnv {
    let container: ModelContainer
    let context: ModelContext
    let workoutRepository: SwiftDataWorkoutRepository
    let templateRepository: SwiftDataTemplateRepository
    let exerciseRepository: SwiftDataExerciseRepository
    let bodyWeightRepository: SwiftDataBodyWeightRepository
    let applier: InboxApplier
    let network: MockNetworkService
    let settings: SettingsManager
    let manager: SyncManager

    init() throws {
        container = try makeTestContainer()
        context = container.mainContext
        workoutRepository = SwiftDataWorkoutRepository(context: context)
        templateRepository = SwiftDataTemplateRepository(context: context)
        exerciseRepository = SwiftDataExerciseRepository(context: context)
        bodyWeightRepository = SwiftDataBodyWeightRepository(context: context)
        applier = InboxApplier(
            templateRepository: templateRepository,
            exerciseRepository: exerciseRepository
        )
        network = MockNetworkService()
        settings = SettingsManager(
            defaults: UserDefaults(suiteName: "inbox-tests-\(UUID().uuidString)")!
        )
        settings.serverURL = "https://example.com"
        manager = SyncManager(
            workoutRepository: workoutRepository,
            templateRepository: templateRepository,
            exerciseRepository: exerciseRepository,
            bodyWeightRepository: bodyWeightRepository,
            networkService: network,
            settings: settings,
            inboxApplier: applier
        )
    }
}

private func makeOperation<Payload: Encodable>(
    id: String = UUID().uuidString,
    op: String,
    payload: Payload,
    requiresApproval: Bool = false,
    status: String = "pending"
) throws -> InboxOperationDTO {
    let data = try JSONEncoder().encode(payload)
    let payloadJSON = try JSONDecoder().decode(InboxJSONValue.self, from: data)
    return InboxOperationDTO(
        id: id,
        createdAt: "2026-07-27T12:00:00.000Z",
        op: op,
        payload: payloadJSON,
        requiresApproval: requiresApproval,
        status: status,
        appliedAt: nil,
        error: nil
    )
}

private func makeInboxPushResponse() -> SnapshotPushResponse {
    SnapshotPushResponse(
        revision: 1,
        serverTime: Date(timeIntervalSinceReferenceDate: 800_000_000),
        counts: [
            "workouts": SnapshotCollectionCounts(upserted: 0, deleted: 0),
            "templates": SnapshotCollectionCounts(upserted: 1, deleted: 0),
            "customExercises": SnapshotCollectionCounts(upserted: 0, deleted: 0),
            "bodyWeightEntries": SnapshotCollectionCounts(upserted: 0, deleted: 0),
        ]
    )
}

@Suite("InboxApplier")
@MainActor
struct InboxApplierTests {
    @Test("createTemplate resolves external ids and preserves ordered targets")
    func createsResolvedTemplateInOrder() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let squat = Exercise(name: "Squat", externalId: "squat")
        let bench = Exercise(name: "Bench Press", externalId: "bench")
        try await env.exerciseRepository.save(squat)
        try await env.exerciseRepository.save(bench)
        let payload = CreateTemplatePayload(
            name: "Strength A",
            notes: "Heavy day",
            exercises: [
                InboxTemplateExercisePayload(
                    externalId: "bench",
                    order: 1,
                    defaultSets: 4,
                    defaultReps: 6,
                    defaultWeight: 80,
                    defaultRestSeconds: 120,
                    notes: "pause"
                ),
                InboxTemplateExercisePayload(
                    externalId: "squat",
                    order: 0,
                    defaultSets: 5,
                    defaultReps: 5,
                    defaultWeight: 100,
                    defaultRestSeconds: 180,
                    notes: nil
                ),
            ]
        )
        let operation = try makeOperation(
            op: "createTemplate",
            payload: payload,
            requiresApproval: false
        )

        // Act
        let results = await env.applier.process([operation])

        // Assert
        let template = try #require(try await env.templateRepository.fetchAll().first)
        let exercises = template.exercises.sorted { $0.order < $1.order }
        #expect(results.first?.status == .applied)
        #expect(template.name == "Strength A")
        #expect(template.notes == "Heavy day")
        #expect(exercises.map { $0.exercise?.externalId } == ["squat", "bench"])
        #expect(exercises.map(\.defaultSets) == [5, 4])
        #expect(exercises.map(\.defaultReps) == [5, 6])
        #expect(exercises.map(\.defaultRestSeconds) == [180, 120])
        #expect(exercises.map(\.defaultWeight) == [100, 80])
    }

    @Test("createTemplate defaults omitted rest seconds to 90")
    func defaultsMissingRestSeconds() async throws {
        // Arrange
        let env = try InboxTestEnv()
        try await env.exerciseRepository.save(
            Exercise(name: "Bench Press", externalId: "bench")
        )
        let payload = CreateTemplatePayload(
            name: "Push",
            notes: nil,
            exercises: [
                InboxTemplateExercisePayload(
                    externalId: "bench",
                    order: 0,
                    defaultSets: 3,
                    defaultReps: 8,
                    defaultWeight: nil,
                    defaultRestSeconds: nil,
                    notes: nil
                )
            ]
        )

        // Act
        _ = await env.applier.process([
            try makeOperation(op: "createTemplate", payload: payload)
        ])

        // Assert
        let template = try #require(try await env.templateRepository.fetchAll().first)
        #expect(template.exercises.first?.defaultRestSeconds == 90)
    }

    @Test("replaying createTemplate uses the operation id and does not duplicate")
    func replayedTemplateCreateIsIdempotent() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let bench = Exercise(name: "Bench Press", externalId: "bench")
        let row = Exercise(name: "Cable Row", externalId: "row")
        try await env.exerciseRepository.save(bench)
        try await env.exerciseRepository.save(row)
        let operationID = UUID()
        let operation = try makeOperation(
            id: operationID.uuidString,
            op: "createTemplate",
            payload: CreateTemplatePayload(
                name: "Replay Safe",
                notes: nil,
                exercises: [
                    InboxTemplateExercisePayload(
                        externalId: "bench",
                        order: 0,
                        defaultSets: 3,
                        defaultReps: 8,
                        defaultWeight: nil,
                        defaultRestSeconds: 90,
                        notes: nil
                    ),
                    InboxTemplateExercisePayload(
                        externalId: "row",
                        order: 1,
                        defaultSets: 4,
                        defaultReps: 10,
                        defaultWeight: nil,
                        defaultRestSeconds: 60,
                        notes: nil
                    ),
                ]
            )
        )

        // Act
        let first = await env.applier.process([operation])
        let firstTemplate = try #require(
            try await env.templateRepository.fetch(id: operationID)
        )
        let originalRelationshipIDs = Set(firstTemplate.exercises.map(\.id))
        let replay = await env.applier.process([operation])

        // Assert
        let templates = try await env.templateRepository.fetchAll()
        let replayedTemplate = try #require(templates.first)
        let storedRelationships = try env.context.fetch(
            FetchDescriptor<TemplateExercise>()
        )
        #expect(first.first?.status == .applied)
        #expect(replay.first?.status == .applied)
        #expect(templates.count == 1)
        #expect(replayedTemplate.id == operationID)
        #expect(replayedTemplate.exercises.count == 2)
        #expect(Set(replayedTemplate.exercises.map(\.id)) == originalRelationshipIDs)
        #expect(storedRelationships.count == 2)
    }

    @Test("an unresolved external id fails the whole template")
    func unresolvedExerciseFailsAtomically() async throws {
        // Arrange
        let env = try InboxTestEnv()
        try await env.exerciseRepository.save(
            Exercise(name: "Bench Press", externalId: "bench")
        )
        let badExternalId = "missing-row"
        let payload = CreateTemplatePayload(
            name: "Must Not Exist",
            notes: nil,
            exercises: [
                InboxTemplateExercisePayload(
                    externalId: "bench",
                    order: 0,
                    defaultSets: 3,
                    defaultReps: 8,
                    defaultWeight: nil,
                    defaultRestSeconds: 90,
                    notes: nil
                ),
                InboxTemplateExercisePayload(
                    externalId: badExternalId,
                    order: 1,
                    defaultSets: 3,
                    defaultReps: 10,
                    defaultWeight: nil,
                    defaultRestSeconds: 90,
                    notes: nil
                ),
            ]
        )

        // Act
        let results = await env.applier.process([
            try makeOperation(op: "createTemplate", payload: payload)
        ])

        // Assert
        #expect(try await env.templateRepository.fetchAll().isEmpty)
        #expect(results.first?.status == .failed)
        #expect(results.first?.error?.contains(badExternalId) == true)
    }

    @Test("one malformed operation does not stop the rest of its batch")
    func malformedOperationDoesNotAbortBatch() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let malformed = InboxOperationDTO(
            id: "bad-operation",
            createdAt: "2026-07-27T12:00:00.000Z",
            op: "createTemplate",
            payload: .object(["name": .string("Missing exercises")]),
            requiresApproval: false,
            status: "pending",
            appliedAt: nil,
            error: nil
        )
        let valid = try makeOperation(
            id: "10000000-0000-4000-8000-000000000001",
            op: "createCustomExercise",
            payload: CreateCustomExercisePayload(
                name: "Cable Cross",
                externalId: "custom:cable-cross:10000000-0000-4000-8000-000000000001",
                equipment: "cable",
                primaryMuscles: ["chest"],
                secondaryMuscles: [],
                instructions: [],
                notes: nil
            )
        )

        // Act
        let results = await env.applier.process([malformed, valid])

        // Assert
        #expect(results.map(\.status) == [.failed, .applied])
        #expect(
            try await env.exerciseRepository.fetchByExternalId(
                "custom:cable-cross:10000000-0000-4000-8000-000000000001"
            ) != nil
        )
    }

    @Test("an approval-required delete is acknowledged before any mutation")
    func deleteAwaitsApprovalWithoutMutation() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let template = WorkoutTemplate(name: "Push Day", syncStatus: .synced)
        try await env.templateRepository.save(template)
        let operation = try makeOperation(
            id: "delete-push",
            op: "deleteTemplate",
            payload: DeleteTemplatePayload(id: template.id.uuidString, name: template.name),
            requiresApproval: true
        )

        // Act
        let results = await env.applier.process([operation])

        // Assert
        #expect(results.first?.status.rawValue == "awaitingApproval")
        #expect(try await env.templateRepository.fetch(id: template.id) != nil)
    }

    @Test("an approval-required update is acknowledged before any mutation")
    func updateAwaitsApprovalWithoutMutation() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let bench = Exercise(name: "Bench Press", externalId: "bench")
        let squat = Exercise(name: "Squat", externalId: "squat")
        try await env.exerciseRepository.save(bench)
        try await env.exerciseRepository.save(squat)
        let template = WorkoutTemplate(name: "Old Name", syncStatus: .synced)
        template.exercises = [
            TemplateExercise(
                order: 0,
                exercise: bench,
                defaultSets: 3,
                defaultReps: 8
            )
        ]
        try await env.templateRepository.save(template)
        let operation = try makeOperation(
            id: "update-template",
            op: "updateTemplate",
            payload: UpdateTemplatePayload(
                id: template.id.uuidString,
                name: "New Name",
                notes: "updated",
                exercises: [
                    InboxTemplateExercisePayload(
                        externalId: "squat",
                        order: 0,
                        defaultSets: 5,
                        defaultReps: 5,
                        defaultWeight: 100,
                        defaultRestSeconds: nil,
                        notes: nil
                    )
                ]
            ),
            requiresApproval: true
        )

        // Act
        let results = await env.applier.process([operation])

        // Assert
        #expect(results.first?.status.rawValue == "awaitingApproval")
        #expect(template.name == "Old Name")
        #expect(template.notes == nil)
        #expect(template.exercises.count == 1)
        #expect(template.exercises.first?.exercise?.externalId == "bench")
        #expect(template.exercises.first?.defaultSets == 3)
        #expect(template.exercises.first?.defaultRestSeconds == 90)
        #expect(template.syncStatus == .synced)
    }

    @Test("update and delete types cannot bypass approval with a false flag")
    func approvalTypesRejectFalseApprovalFlags() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let template = WorkoutTemplate(name: "Protected", syncStatus: .synced)
        try await env.templateRepository.save(template)
        let update = try makeOperation(
            id: "mismatched-update",
            op: "updateTemplate",
            payload: UpdateTemplatePayload(
                id: template.id.uuidString,
                name: "Must Not Apply",
                notes: nil,
                exercises: nil
            ),
            requiresApproval: false
        )
        let delete = try makeOperation(
            id: "mismatched-delete",
            op: "deleteTemplate",
            payload: DeleteTemplatePayload(
                id: template.id.uuidString,
                name: template.name
            ),
            requiresApproval: false
        )

        // Act
        let results = await env.applier.process([update, delete])

        // Assert
        #expect(results.map(\.status) == [.failed, .failed])
        #expect(
            results.allSatisfy {
                $0.error?.localizedCaseInsensitiveContains("approval") == true
            }
        )
        #expect(template.name == "Protected")
        #expect(try await env.templateRepository.fetch(id: template.id) != nil)
        #expect(template.syncStatus == .synced)
    }

    @Test("a create type with a true approval flag fails instead of being held")
    func createRejectsTrueApprovalFlag() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let operation = try makeOperation(
            op: "createTemplate",
            payload: CreateTemplatePayload(
                name: "Mismatched Create",
                notes: nil,
                exercises: []
            ),
            requiresApproval: true
        )

        // Act
        let result = await env.applier.process([operation]).first

        // Assert
        #expect(result?.status == .failed)
        #expect(
            result?.error?.localizedCaseInsensitiveContains("approval") == true
        )
        #expect(try await env.templateRepository.fetchAll().isEmpty)
    }

    @Test("an unresolved update leaves every template field unchanged")
    func unresolvedUpdateIsAtomic() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let bench = Exercise(name: "Bench Press", externalId: "bench")
        try await env.exerciseRepository.save(bench)
        let template = WorkoutTemplate(
            name: "Original",
            notes: "keep",
            syncStatus: .synced
        )
        template.exercises = [
            TemplateExercise(
                order: 0,
                exercise: bench,
                defaultSets: 3,
                defaultReps: 8
            )
        ]
        try await env.templateRepository.save(template)
        let operation = try makeOperation(
            id: "bad-update",
            op: "updateTemplate",
            payload: UpdateTemplatePayload(
                id: template.id.uuidString,
                name: "Must Not Apply",
                notes: "must not apply",
                exercises: [
                    InboxTemplateExercisePayload(
                        externalId: "missing-update-exercise",
                        order: 0,
                        defaultSets: 4,
                        defaultReps: 6,
                        defaultWeight: nil,
                        defaultRestSeconds: 60,
                        notes: nil
                    )
                ]
            ),
            requiresApproval: true,
            status: "awaitingApproval"
        )

        // Act
        let result = await env.applier.approve(operation)

        // Assert
        #expect(result.status == .failed)
        #expect(result.error?.contains("missing-update-exercise") == true)
        #expect(template.name == "Original")
        #expect(template.notes == "keep")
        #expect(template.exercises.first?.exercise?.externalId == "bench")
        #expect(template.syncStatus == .synced)
    }

    @Test("approving an awaiting update applies it locally")
    func approveAppliesAwaitingUpdate() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let template = WorkoutTemplate(name: "Old Name", syncStatus: .synced)
        try await env.templateRepository.save(template)
        let operation = try makeOperation(
            id: "approved-update",
            op: "updateTemplate",
            payload: UpdateTemplatePayload(
                id: template.id.uuidString,
                name: "Approved Name",
                notes: nil,
                exercises: nil
            ),
            requiresApproval: true,
            status: "awaitingApproval"
        )

        // Act
        let result = await env.applier.approve(operation)

        // Assert
        #expect(result.status == .applied)
        #expect(template.name == "Approved Name")
        #expect(template.syncStatus == .pending)
    }

    @Test("the correct approval sequence never reports failed")
    func correctApprovalSequenceNeverFails() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let template = WorkoutTemplate(name: "Before", syncStatus: .synced)
        try await env.templateRepository.save(template)
        let pending = try makeOperation(
            id: "correct-update-sequence",
            op: "updateTemplate",
            payload: UpdateTemplatePayload(
                id: template.id.uuidString,
                name: "After",
                notes: nil,
                exercises: nil
            ),
            requiresApproval: true
        )
        let awaiting = try makeOperation(
            id: pending.id,
            op: pending.op,
            payload: UpdateTemplatePayload(
                id: template.id.uuidString,
                name: "After",
                notes: nil,
                exercises: nil
            ),
            requiresApproval: true,
            status: "awaitingApproval"
        )

        // Act
        let pendingResult = await env.applier.process([pending]).first
        let approvalResult = await env.applier.approve(awaiting)

        // Assert
        #expect(pendingResult?.status == .awaitingApproval)
        #expect(approvalResult.status == .applied)
        #expect(pendingResult?.status != .failed)
        #expect(approvalResult.status != .failed)
        #expect(template.name == "After")
    }

    @Test("declining an awaiting delete rejects it without local mutation")
    func declineRejectsAwaitingDeleteWithoutMutation() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let template = WorkoutTemplate(name: "Keep Me", syncStatus: .synced)
        try await env.templateRepository.save(template)
        let operation = try makeOperation(
            id: "declined-delete",
            op: "deleteTemplate",
            payload: DeleteTemplatePayload(
                id: template.id.uuidString,
                name: template.name
            ),
            requiresApproval: true,
            status: "awaitingApproval"
        )

        // Act
        let result = env.applier.decline(operation)

        // Assert
        #expect(result.status == .rejected)
        #expect(try await env.templateRepository.fetch(id: template.id) != nil)
        #expect(template.syncStatus == .synced)
    }

    @Test("syncIfNeeded holds a delete for approval without pushing")
    func syncHoldsDeleteForApproval() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let template = WorkoutTemplate(name: "Delete Me", syncStatus: .synced)
        try await env.templateRepository.save(template)
        env.network.fetchInboxResult = InboxListResponse(
            operations: [
                try makeOperation(
                    id: "auto-delete",
                    op: "deleteTemplate",
                    payload: DeleteTemplatePayload(
                        id: template.id.uuidString,
                        name: template.name
                    ),
                    requiresApproval: true
                )
            ]
        )
        env.network.pushSnapshotResult = makeInboxPushResponse()

        // Act
        await env.manager.syncIfNeeded()

        // Assert
        #expect(try await env.templateRepository.fetch(id: template.id) != nil)
        #expect(
            env.network.lastInboxAckRequest?.results.first?.status.rawValue
                == "awaitingApproval"
        )
        #expect(env.network.pushSnapshotCallCount == 0)
        #expect(env.manager.syncError == nil)
    }

    @Test("syncIfNeeded refetches awaiting approvals so restart re-presents them")
    func syncRefetchesDurableAwaitingApprovals() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let operation = try makeOperation(
            id: "durable-approval",
            op: "deleteTemplate",
            payload: DeleteTemplatePayload(
                id: UUID().uuidString,
                name: "Durable Delete"
            ),
            requiresApproval: true,
            status: "awaitingApproval"
        )
        env.network.awaitingApprovalInboxResult = InboxListResponse(
            operations: [operation]
        )

        // Act
        await env.manager.syncIfNeeded()

        // Assert
        #expect(env.manager.pendingApprovals.map(\.id) == ["durable-approval"])
        #expect(
            env.network.fetchedInboxStatuses
                .contains(.awaitingApproval)
        )
    }

    @Test("approving through SyncManager applies, acks, and pushes")
    func managerApprovesAndPushes() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let template = WorkoutTemplate(name: "Before", syncStatus: .synced)
        try await env.templateRepository.save(template)
        let operation = try makeOperation(
            id: "approved-manager-update",
            op: "updateTemplate",
            payload: UpdateTemplatePayload(
                id: template.id.uuidString,
                name: "After",
                notes: nil,
                exercises: nil
            ),
            requiresApproval: true,
            status: "awaitingApproval"
        )
        env.network.pushSnapshotResult = makeInboxPushResponse()
        var wasDirtyWhenSnapshotStarted = false
        env.network.onPushSnapshot = {
            wasDirtyWhenSnapshotStarted = env.settings.isSnapshotDirty
        }

        // Act
        try await env.manager.approve(operation)

        // Assert
        #expect(template.name == "After")
        #expect(env.network.lastInboxAckRequest?.results.first?.status == .applied)
        #expect(env.network.pushSnapshotCallCount == 1)
        #expect(wasDirtyWhenSnapshotStarted == true)
        #expect(env.settings.isSnapshotDirty == false)
    }

    @Test("declining through SyncManager acks rejected and mutates nothing")
    func managerDeclinesWithoutMutation() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let template = WorkoutTemplate(name: "Keep", syncStatus: .synced)
        try await env.templateRepository.save(template)
        let operation = try makeOperation(
            id: "declined-manager-delete",
            op: "deleteTemplate",
            payload: DeleteTemplatePayload(
                id: template.id.uuidString,
                name: template.name
            ),
            requiresApproval: true,
            status: "awaitingApproval"
        )

        // Act
        try await env.manager.decline(operation)

        // Assert
        #expect(try await env.templateRepository.fetch(id: template.id) != nil)
        #expect(env.network.lastInboxAckRequest?.results.first?.status == .rejected)
        #expect(env.network.pushSnapshotCallCount == 0)
    }

    @Test("createCustomExercise assigns custom identity")
    func createsCustomExerciseIdentity() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let operation = try makeOperation(
            id: "10000000-0000-4000-8000-000000000004",
            op: "createCustomExercise",
            payload: CreateCustomExercisePayload(
                name: "Belt Squat (Machine)",
                externalId: "custom:belt-squat-machine:10000000-0000-4000-8000-000000000004",
                equipment: "machine",
                primaryMuscles: ["quadriceps"],
                secondaryMuscles: ["glutes"],
                instructions: ["Stand tall"],
                notes: "custom setup"
            ),
            requiresApproval: false
        )

        // Act
        let results = await env.applier.process([operation])

        // Assert
        let exercise = try #require(
            try await env.exerciseRepository.fetchByExternalId(
                "custom:belt-squat-machine:10000000-0000-4000-8000-000000000004"
            )
        )
        #expect(results.first?.status == .applied)
        #expect(exercise.isCustom == true)
        #expect(exercise.externalId?.hasPrefix("custom:") == true)
        #expect(exercise.equipment == "machine")
        #expect(exercise.primaryMuscles == ["quadriceps"])
    }

    @Test("replaying createCustomExercise uses the operation id and does not duplicate")
    func replayedCustomExerciseCreateIsIdempotent() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let operationID = UUID()
        let operation = try makeOperation(
            id: operationID.uuidString,
            op: "createCustomExercise",
            payload: CreateCustomExercisePayload(
                name: "Replay Curl",
                externalId: "custom:replay-curl:\(operationID.uuidString.lowercased())",
                equipment: nil,
                primaryMuscles: nil,
                secondaryMuscles: nil,
                instructions: nil,
                notes: nil
            )
        )

        // Act
        let first = await env.applier.process([operation])
        let saved = try #require(
            try await env.exerciseRepository.fetch(id: operationID)
        )
        saved.name = "Locally Renamed Replay Curl"
        saved.equipment = "band"
        try env.context.save()
        let replay = await env.applier.process([operation])

        // Assert
        let exercises = try await env.exerciseRepository.fetchAll()
            .filter(\.isCustom)
        #expect(first.first?.status == .applied)
        #expect(replay.first?.status == .applied)
        #expect(exercises.count == 1)
        #expect(exercises.first?.id == operationID)
        #expect(exercises.first?.name == "Locally Renamed Replay Curl")
        #expect(exercises.first?.equipment == "band")
    }

    @Test("custom external ids enforce one bounded operation identity grammar")
    func validatesCustomExternalIdGrammar() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let operationID = UUID()
        let operationIdText = operationID.uuidString.lowercased()
        let invalidExternalIds = [
            "custom:",
            "custom:row",
            "custom:Bad_Slug:\(operationIdText)",
            "custom:\(String(repeating: "a", count: 65)):\(operationIdText)",
            "custom:row:00000000-0000-4000-8000-000000000000",
        ]

        // Act
        var results: [InboxAckResult] = []
        for externalId in invalidExternalIds {
            let operation = try makeOperation(
                id: operationID.uuidString,
                op: "createCustomExercise",
                payload: CreateCustomExercisePayload(
                    name: "Invalid Identity",
                    externalId: externalId,
                    equipment: nil,
                    primaryMuscles: nil,
                    secondaryMuscles: nil,
                    instructions: nil,
                    notes: nil
                )
            )
            results.append(contentsOf: await env.applier.process([operation]))
        }

        // Assert
        #expect(results.count == invalidExternalIds.count)
        #expect(results.allSatisfy { $0.status == .failed })
        #expect(
            results.allSatisfy {
                $0.error?.localizedCaseInsensitiveContains("externalId") == true
            }
        )
        #expect(try await env.exerciseRepository.fetchAll().isEmpty)
    }

    @Test("custom external ids accept a 64-character slug and matching UUID")
    func acceptsMaximumCustomExternalIdSlug() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let operationID = UUID()
        let externalId = "custom:\(String(repeating: "a", count: 64)):"
            + operationID.uuidString.lowercased()
        let operation = try makeOperation(
            id: operationID.uuidString,
            op: "createCustomExercise",
            payload: CreateCustomExercisePayload(
                name: "Maximum Slug",
                externalId: externalId,
                equipment: nil,
                primaryMuscles: nil,
                secondaryMuscles: nil,
                instructions: nil,
                notes: nil
            )
        )

        // Act
        let result = await env.applier.process([operation]).first

        // Assert
        #expect(result?.status == .applied)
        #expect(
            try await env.exerciseRepository.fetch(id: operationID)?
                .externalId == externalId
        )
    }

    @Test("a server-issued custom external id resolves in a later template operation")
    func customExerciseResolvesInLaterTemplate() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let customOperationID = UUID()
        let externalId =
            "custom:deja-vu-row:\(customOperationID.uuidString.lowercased())"
        let custom = InboxOperationDTO(
            id: customOperationID.uuidString,
            createdAt: "2026-07-27T12:00:00.000Z",
            op: "createCustomExercise",
            payload: .object([
                "name": .string("Déjà Vu Row"),
                "externalId": .string(externalId),
            ]),
            requiresApproval: false,
            status: "pending",
            appliedAt: nil,
            error: nil
        )
        let template = try makeOperation(
            op: "createTemplate",
            payload: CreateTemplatePayload(
                name: "Custom Pull",
                notes: nil,
                exercises: [
                    InboxTemplateExercisePayload(
                        externalId: externalId,
                        order: 0,
                        defaultSets: 3,
                        defaultReps: 10,
                        defaultWeight: nil,
                        defaultRestSeconds: nil,
                        notes: nil
                    )
                ]
            )
        )

        // Act
        let results = await env.applier.process([custom, template])

        // Assert
        #expect(results.map(\.status) == [.applied, .applied])
        let saved = try #require(
            try await env.templateRepository.fetchAll().first
        )
        #expect(saved.exercises.first?.exercise?.externalId == externalId)
    }

    @Test("a custom exercise without a server-issued external id fails loudly")
    func missingCustomExternalIdFailsLoudly() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let operation = InboxOperationDTO(
            id: UUID().uuidString,
            createdAt: "2026-07-27T12:00:00.000Z",
            op: "createCustomExercise",
            payload: .object([
                "name": .string("Legacy Inert Exercise"),
            ]),
            requiresApproval: false,
            status: "pending",
            appliedAt: nil,
            error: nil
        )

        // Act
        let result = await env.applier.process([operation]).first

        // Assert
        #expect(result?.status == .failed)
        #expect(
            result?.error?.localizedCaseInsensitiveContains("externalId")
                == true
        )
        #expect(try await env.exerciseRepository.fetchAll().isEmpty)
    }

    @Test("idle phone drains inbox before the pending guard and pushes the create")
    func idlePhoneAppliesAndPushesInboxCreate() async throws {
        // Arrange — no local record is pending before this sync.
        let env = try InboxTestEnv()
        try await env.exerciseRepository.save(
            Exercise(name: "Bench Press", externalId: "bench")
        )
        env.network.fetchInboxResult = InboxListResponse(
            operations: [
                try makeOperation(
                    id: "10000000-0000-4000-8000-000000000002",
                    op: "createTemplate",
                    payload: CreateTemplatePayload(
                        name: "Arrived While Idle",
                        notes: nil,
                        exercises: [
                            InboxTemplateExercisePayload(
                                externalId: "bench",
                                order: 0,
                                defaultSets: 3,
                                defaultReps: 8,
                                defaultWeight: nil,
                                defaultRestSeconds: nil,
                                notes: nil
                            )
                        ]
                    )
                )
            ]
        )
        env.network.pushSnapshotResult = makeInboxPushResponse()

        // Act
        await env.manager.syncIfNeeded()

        // Assert
        #expect(
            try await env.templateRepository.fetchAll().contains {
                $0.name == "Arrived While Idle"
            }
        )
        #expect(env.network.ackInboxCallCount == 1)
        #expect(env.network.lastInboxAckRequest?.results.first?.status == .applied)
        #expect(env.network.pushSnapshotCallCount == 1)
        #expect(
            env.network.lastSnapshotRequest?.snapshot.templates.contains {
                $0.name == "Arrived While Idle"
            } == true
        )
    }

    @Test("idle phone pushes an inbox-created custom exercise")
    func idlePhonePushesCustomExercise() async throws {
        // Arrange
        let env = try InboxTestEnv()
        env.network.fetchInboxResult = InboxListResponse(
            operations: [
                try makeOperation(
                    id: "10000000-0000-4000-8000-000000000003",
                    op: "createCustomExercise",
                    payload: CreateCustomExercisePayload(
                        name: "Reverse Sled Drag",
                        externalId: "custom:reverse-sled-drag:10000000-0000-4000-8000-000000000003",
                        equipment: "sled",
                        primaryMuscles: ["quadriceps"],
                        secondaryMuscles: [],
                        instructions: [],
                        notes: nil
                    )
                )
            ]
        )
        env.network.pushSnapshotResult = makeInboxPushResponse()

        // Act
        await env.manager.syncIfNeeded()

        // Assert
        #expect(env.network.pushSnapshotCallCount == 1)
        #expect(
            env.network.lastSnapshotRequest?.snapshot.customExercises.first?
                .externalId
                == "custom:reverse-sled-drag:10000000-0000-4000-8000-000000000003"
        )
    }

}
