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
    requiresApproval: Bool = false
) throws -> InboxOperationDTO {
    let data = try JSONEncoder().encode(payload)
    let payloadJSON = try JSONDecoder().decode(InboxJSONValue.self, from: data)
    return InboxOperationDTO(
        id: id,
        createdAt: "2026-07-27T12:00:00.000Z",
        op: op,
        payload: payloadJSON,
        requiresApproval: requiresApproval,
        status: "pending",
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
            requiresApproval: true
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
            requiresApproval: true,
            status: "pending",
            appliedAt: nil,
            error: nil
        )
        let valid = try makeOperation(
            id: "good-operation",
            op: "createCustomExercise",
            payload: CreateCustomExercisePayload(
                name: "Cable Cross",
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
        #expect(try await env.exerciseRepository.fetchByExternalId("custom:cable-cross") != nil)
    }

    @Test("deleteTemplate ignores the approval flag and applies immediately")
    func deleteAppliesImmediately() async throws {
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
        #expect(results.first?.status == .applied)
        #expect(try await env.templateRepository.fetch(id: template.id) == nil)
    }

    @Test("updateTemplate ignores the approval flag and replaces ordered exercises immediately")
    func updateAppliesAndReplacesExercises() async throws {
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
        #expect(results.first?.status == .applied)
        #expect(template.name == "New Name")
        #expect(template.notes == "updated")
        #expect(template.exercises.count == 1)
        #expect(template.exercises.first?.exercise?.externalId == "squat")
        #expect(template.exercises.first?.defaultSets == 5)
        #expect(template.exercises.first?.defaultRestSeconds == 90)
        #expect(template.syncStatus == .pending)
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
            requiresApproval: true
        )

        // Act
        let results = await env.applier.process([operation])

        // Assert
        let result = try #require(results.first)
        #expect(result.status == .failed)
        #expect(result.error?.contains("missing-update-exercise") == true)
        #expect(template.name == "Original")
        #expect(template.notes == "keep")
        #expect(template.exercises.first?.exercise?.externalId == "bench")
        #expect(template.syncStatus == .synced)
    }

    @Test("syncIfNeeded auto-applies and pushes a delete end-to-end")
    func syncAutoAppliesAndPushesDelete() async throws {
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
        #expect(try await env.templateRepository.fetch(id: template.id) == nil)
        #expect(env.network.lastInboxAckRequest?.results.first?.status == .applied)
        #expect(env.network.pushSnapshotCallCount == 1)
        #expect(
            env.network.lastSnapshotRequest?.snapshot.templates.contains(
                where: { $0.id == template.id }
            ) == false
        )
        #expect(env.manager.syncError == nil)
    }

    @Test("createCustomExercise assigns custom identity")
    func createsCustomExerciseIdentity() async throws {
        // Arrange
        let env = try InboxTestEnv()
        let operation = try makeOperation(
            op: "createCustomExercise",
            payload: CreateCustomExercisePayload(
                name: "Belt Squat (Machine)",
                equipment: "machine",
                primaryMuscles: ["quadriceps"],
                secondaryMuscles: ["glutes"],
                instructions: ["Stand tall"],
                notes: "custom setup"
            ),
            requiresApproval: true
        )

        // Act
        let results = await env.applier.process([operation])

        // Assert
        let exercise = try #require(
            try await env.exerciseRepository.fetchByExternalId(
                "custom:belt-squat-machine"
            )
        )
        #expect(results.first?.status == .applied)
        #expect(exercise.isCustom == true)
        #expect(exercise.externalId?.hasPrefix("custom:") == true)
        #expect(exercise.equipment == "machine")
        #expect(exercise.primaryMuscles == ["quadriceps"])
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
                    id: "idle-create",
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
                    id: "idle-custom",
                    op: "createCustomExercise",
                    payload: CreateCustomExercisePayload(
                        name: "Reverse Sled Drag",
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
                .externalId == "custom:reverse-sled-drag"
        )
    }

}
