import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

/// Everything a snapshot-sync test needs, built around one in-memory store.
/// A struct (not locals) so the ModelContainer is RETAINED for the whole test —
/// iOS traps message-lessly when a ModelContext outlives its container.
@MainActor
private struct SyncTestEnv {
    let container: ModelContainer
    let context: ModelContext
    let workoutRepo: SwiftDataWorkoutRepository
    let templateRepo: SwiftDataTemplateRepository
    let exerciseRepo: SwiftDataExerciseRepository
    let bodyWeightRepo: SwiftDataBodyWeightRepository
    let reportRepo: SwiftDataExerciseReportRepository
    let inboxApplier: InboxApplier
    let network: MockNetworkService
    let settings: SettingsManager
    let manager: SyncManager

    init(
        serverURL: String = "https://example.com",
        defaults: UserDefaults? = nil
    ) throws {
        container = try makeTestContainer()
        context = container.mainContext
        workoutRepo = SwiftDataWorkoutRepository(context: context)
        templateRepo = SwiftDataTemplateRepository(context: context)
        exerciseRepo = SwiftDataExerciseRepository(context: context)
        bodyWeightRepo = SwiftDataBodyWeightRepository(context: context)
        reportRepo = SwiftDataExerciseReportRepository(context: context)
        inboxApplier = InboxApplier(
            templateRepository: templateRepo,
            exerciseRepository: exerciseRepo,
            reportRepository: reportRepo
        )
        network = MockNetworkService()
        settings = SettingsManager(
            defaults: defaults
                ?? UserDefaults(suiteName: "sync-test-\(UUID())")!
        )
        settings.serverURL = serverURL
        manager = SyncManager(
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            exerciseRepository: exerciseRepo,
            bodyWeightRepository: bodyWeightRepo,
            exerciseReportRepository: reportRepo,
            networkService: network,
            settings: settings,
            inboxApplier: inboxApplier
        )
    }
}

private func makePushResponse(revision: Int = 1, serverTime: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) -> SnapshotPushResponse {
    SnapshotPushResponse(
        revision: revision,
        serverTime: serverTime,
        counts: [
            "workouts": SnapshotCollectionCounts(upserted: 0, deleted: 0),
            "templates": SnapshotCollectionCounts(upserted: 0, deleted: 0),
            "customExercises": SnapshotCollectionCounts(upserted: 0, deleted: 0),
            "bodyWeightEntries": SnapshotCollectionCounts(upserted: 0, deleted: 0),
        ]
    )
}

// Inbox operation ids must parse as UUIDs — the applier derives the created
// entity's identity from them so a replayed operation is a no-op. The server
// mints them with randomUUID(), so fixtures must be real UUIDs too.
private let requestedOperationID = "11111111-1111-4111-8111-111111111111"
private let validOperationID = "22222222-2222-4222-8222-222222222222"
private let extraOperationID = "33333333-3333-4333-8333-333333333333"
private let conflictingOperationID = "44444444-4444-4444-8444-444444444444"

private func makePendingInboxCreate(id: String) -> InboxOperationDTO {
    InboxOperationDTO(
        id: id,
        createdAt: "2026-07-27T12:00:00.000Z",
        op: "createTemplate",
        payload: .object([
            "name": .string("Ack Validation \(id)"),
            "exercises": .array([]),
        ]),
        requiresApproval: false,
        status: "pending",
        appliedAt: nil,
        error: nil
    )
}

@MainActor
private func runAckValidationScenario(
    _ response: InboxAckResponse
) async throws -> (syncError: String?, pushCount: Int) {
    let env = try SyncTestEnv()
    env.network.fetchInboxResult = InboxListResponse(
        operations: [makePendingInboxCreate(id: requestedOperationID)]
    )
    env.network.ackInboxResult = response
    env.network.pushSnapshotResult = makePushResponse()

    await env.manager.syncIfNeeded()

    return (env.manager.syncError, env.network.pushSnapshotCallCount)
}

@Suite("SyncManager Snapshot Push")
@MainActor
struct SyncManagerSnapshotPushTests {
    @Test("snapshot push serializes full state: all five types, nothing else")
    func snapshotContainsAllFiveTypesAndNothingElse() async throws {
        // Arrange — one of everything, including types that must NOT sync
        let env = try SyncTestEnv()
        let custom = TestFixtures.makeExercise(name: "My Cable Fly", isCustom: true)
        let bundled = TestFixtures.makeExercise(name: "Bench Press", isCustom: false)
        env.context.insert(custom)
        env.context.insert(bundled)
        env.context.insert(Workout(name: "Push Day", startedAt: .now, syncStatus: .pending))
        env.context.insert(WorkoutTemplate(name: "Push Template"))
        env.context.insert(BodyWeightEntry(weightKg: 82.5))
        env.context.insert(ExerciseReport(category: .bug, detail: "timer double-fired"))
        env.context.insert(TestFixtures.makeChatMessage(content: "not synced"))
        env.context.insert(TestFixtures.makeInsight(content: "not synced"))
        env.context.insert(TestFixtures.makeTrainingPreference(key: "style", value: "not synced"))
        try env.context.save()
        env.network.pushSnapshotResult = makePushResponse()

        // Act
        try await env.manager.pushSnapshot()

        // Assert — request carries exactly the five mirrored collections
        let request = try #require(env.network.lastSnapshotRequest)
        #expect(request.schemaVersion == 3)
        #expect(request.snapshot.workouts.count == 1)
        #expect(request.snapshot.templates.count == 1)
        #expect(request.snapshot.customExercises.count == 1)
        #expect(request.snapshot.customExercises.first?.name == "My Cable Fly")
        #expect(request.snapshot.bodyWeightEntries.count == 1)
        #expect(request.snapshot.exerciseReports.count == 1)
    }

    @Test("snapshot is full state even when only some records are pending")
    func snapshotIsFullStateNotDelta() async throws {
        // Arrange — one already-synced and one pending workout
        let env = try SyncTestEnv()
        env.context.insert(Workout(name: "Old Synced", startedAt: .now, syncStatus: .synced))
        env.context.insert(Workout(name: "New Pending", startedAt: .now, syncStatus: .pending))
        let syncedTemplate = WorkoutTemplate(name: "Synced Template")
        syncedTemplate.syncStatus = .synced
        env.context.insert(syncedTemplate)
        try env.context.save()
        env.network.pushSnapshotResult = makePushResponse()

        // Act
        try await env.manager.pushSnapshot()

        // Assert — both workouts and the synced template are in the snapshot
        let request = try #require(env.network.lastSnapshotRequest)
        #expect(request.snapshot.workouts.count == 2)
        #expect(request.snapshot.templates.count == 1)
    }

    @Test("successful push marks records synced and stores revision + timestamp")
    func successfulPushMarksSyncedAndStoresRevision() async throws {
        // Arrange
        let env = try SyncTestEnv()
        let workout = Workout(name: "Push Day", startedAt: .now, syncStatus: .pending)
        let template = WorkoutTemplate(name: "Template")
        let entry = BodyWeightEntry(weightKg: 81.0)
        env.context.insert(workout)
        env.context.insert(template)
        env.context.insert(entry)
        try env.context.save()
        let serverTime = Date(timeIntervalSinceReferenceDate: 790_000_000)
        env.network.pushSnapshotResult = makePushResponse(revision: 42, serverTime: serverTime)

        // Act
        try await env.manager.pushSnapshot()

        // Assert
        #expect(workout.syncStatus == .synced)
        #expect(template.syncStatus == .synced)
        #expect(entry.syncStatus == .synced)
        #expect(env.manager.lastRevision == 42)
        #expect(env.settings.lastSyncRevision == 42)
        #expect(env.manager.lastSyncDate == serverTime)
        #expect(env.settings.lastSyncTimestamp == serverTime)
    }

    @Test("failed push keeps records pending and stores no revision")
    func failedPushKeepsPending() async throws {
        // Arrange
        let env = try SyncTestEnv()
        let workout = Workout(name: "Keep Pending", startedAt: .now, syncStatus: .pending)
        env.context.insert(workout)
        try env.context.save()
        env.network.errorToThrow = SyncError.serverError(500)

        // Act + Assert
        await #expect(throws: SyncError.self) {
            try await env.manager.pushSnapshot()
        }
        #expect(workout.syncStatus == .pending)
        #expect(env.manager.lastRevision == nil)
        #expect(env.settings.lastSyncRevision == nil)
    }

    @Test("record edited while push is in flight stays pending")
    func inFlightEditStaysPending() async throws {
        // Arrange
        let env = try SyncTestEnv()
        let edited = Workout(name: "Edited Mid-Push", startedAt: .now, syncStatus: .pending)
        let untouched = Workout(name: "Untouched", startedAt: .now, syncStatus: .pending)
        env.context.insert(edited)
        env.context.insert(untouched)
        try env.context.save()
        env.network.pushSnapshotResult = makePushResponse()
        env.network.onPushSnapshot = {
            edited.recordChange()
        }

        // Act
        try await env.manager.pushSnapshot()

        // Assert — server acknowledged the OLD payload; the edit must re-push
        #expect(edited.syncStatus == .pending)
        #expect(untouched.syncStatus == .synced)
    }

    @Test("double push is idempotent: same full state both times, records stay synced")
    func doublePushIsIdempotent() async throws {
        // Arrange
        let env = try SyncTestEnv()
        env.context.insert(Workout(name: "Push Day", startedAt: .now, syncStatus: .pending))
        env.context.insert(WorkoutTemplate(name: "Template"))
        try env.context.save()
        env.network.pushSnapshotResult = makePushResponse(revision: 7)

        // Act
        try await env.manager.pushSnapshot()
        let firstRequest = try #require(env.network.lastSnapshotRequest)
        env.network.pushSnapshotResult = makePushResponse(revision: 8)
        try await env.manager.pushSnapshot()
        let secondRequest = try #require(env.network.lastSnapshotRequest)

        // Assert — identical record sets both times, latest revision wins
        #expect(env.network.pushSnapshotCallCount == 2)
        #expect(firstRequest.snapshot.workouts.map(\.id) == secondRequest.snapshot.workouts.map(\.id))
        #expect(firstRequest.snapshot.templates.map(\.id) == secondRequest.snapshot.templates.map(\.id))
        let workouts = try await env.workoutRepo.fetchAll()
        #expect(workouts.allSatisfy { $0.syncStatus == .synced })
        #expect(env.manager.lastRevision == 8)
    }
}

@Suite("SyncManager syncIfNeeded")
@MainActor
struct SyncIfNeededTests {
    @Test("does nothing when server URL not configured")
    func skipsWhenNotConfigured() async throws {
        let env = try SyncTestEnv(serverURL: "")
        env.context.insert(Workout(name: "Pending", startedAt: .now, syncStatus: .pending))
        try env.context.save()

        await env.manager.syncIfNeeded()

        #expect(env.network.fetchInboxCallCount == 0)
        #expect(env.network.pushSnapshotCallCount == 0)
    }

    @Test("skips snapshot push when inbox is empty and nothing is pending")
    func skipsWhenNothingPending() async throws {
        let env = try SyncTestEnv()
        env.context.insert(Workout(name: "Synced", startedAt: .now, syncStatus: .synced))
        try env.context.save()

        await env.manager.syncIfNeeded()

        #expect(env.network.fetchInboxCallCount == 2)
        #expect(env.network.pushSnapshotCallCount == 0)
    }

    @Test("pushes a snapshot when any record is pending")
    func pushesWhenPending() async throws {
        let env = try SyncTestEnv()
        env.context.insert(BodyWeightEntry(weightKg: 80.0, syncStatus: .pending))
        try env.context.save()
        env.network.pushSnapshotResult = makePushResponse()

        await env.manager.syncIfNeeded()

        #expect(env.network.pushSnapshotCallCount == 1)
        #expect(env.manager.syncError == nil)
    }

    @Test("records the error message when the push fails")
    func recordsErrorOnFailure() async throws {
        let env = try SyncTestEnv()
        env.context.insert(Workout(name: "Pending", startedAt: .now, syncStatus: .pending))
        try env.context.save()
        env.network.errorToThrow = SyncError.unauthorized

        await env.manager.syncIfNeeded()

        #expect(env.manager.syncError != nil)
    }

    @Test("an ack conflict surfaces an error after valid batch-mates are pushed")
    func recordsInboxAckConflict() async throws {
        // Arrange
        let env = try SyncTestEnv()
        env.network.fetchInboxResult = InboxListResponse(
            operations: [
                makePendingInboxCreate(id: validOperationID),
                InboxOperationDTO(
                    id: conflictingOperationID,
                    createdAt: "2026-07-27T12:00:00.000Z",
                    op: "deleteTemplate",
                    payload: .object([
                        "id": .string(UUID().uuidString),
                        "name": .string("Already handled"),
                    ]),
                    requiresApproval: true,
                    status: "pending",
                    appliedAt: nil,
                    error: nil
                )
            ]
        )
        let responseJSON = Data(
            """
            {
              "counts": {
                "updated": 1,
                "unchanged": 0,
                "notFound": 0,
                "invalid": 1
              },
              "results": [
                {
                  "id": "\(validOperationID)",
                  "requestedStatus": "applied",
                  "resultingStatus": "applied",
                  "outcome": "updated"
                },
                {
                  "id": "\(conflictingOperationID)",
                  "requestedStatus": "awaitingApproval",
                  "resultingStatus": "applied",
                  "outcome": "conflict",
                  "conflict": "applied deleteTemplate cannot transition to awaitingApproval"
                }
              ]
            }
            """.utf8
        )
        env.network.ackInboxResult = try JSONDecoder().decode(
            InboxAckResponse.self,
            from: responseJSON
        )
        env.network.pushSnapshotResult = makePushResponse()

        // Act
        await env.manager.syncIfNeeded()

        // Assert
        #expect(env.manager.syncError?.localizedCaseInsensitiveContains("conflict") == true)
        #expect(env.network.pushSnapshotCallCount == 1)
        #expect(
            env.network.lastSnapshotRequest?.snapshot.templates.contains {
                $0.name == "Ack Validation \(validOperationID)"
            } == true
        )
    }

    @Test("ack responses are validated against the exact request without blocking push")
    func rejectsIncompleteMismatchedAndExtraAckResults() async throws {
        let correct = InboxAckOperationResult(
            id: requestedOperationID,
            requestedStatus: .applied,
            resultingStatus: "applied",
            outcome: .updated,
            conflict: nil
        )
        let scenarios: [(String, InboxAckResponse)] = [
            (
                "missing",
                InboxAckResponse(
                    counts: InboxAckCounts(
                        updated: 1,
                        unchanged: 0,
                        notFound: 0,
                        invalid: 0
                    ),
                    results: []
                )
            ),
            (
                "not found",
                InboxAckResponse(
                    counts: InboxAckCounts(
                        updated: 0,
                        unchanged: 0,
                        notFound: 1,
                        invalid: 0
                    ),
                    results: [
                        InboxAckOperationResult(
                            id: requestedOperationID,
                            requestedStatus: .applied,
                            resultingStatus: nil,
                            outcome: .notFound,
                            conflict: nil
                        ),
                    ]
                )
            ),
            (
                "requested status",
                InboxAckResponse(
                    counts: InboxAckCounts(
                        updated: 1,
                        unchanged: 0,
                        notFound: 0,
                        invalid: 0
                    ),
                    results: [
                        InboxAckOperationResult(
                            id: requestedOperationID,
                            requestedStatus: .failed,
                            resultingStatus: "failed",
                            outcome: .updated,
                            conflict: nil
                        ),
                    ]
                )
            ),
            (
                "extra",
                InboxAckResponse(
                    counts: InboxAckCounts(
                        updated: 2,
                        unchanged: 0,
                        notFound: 0,
                        invalid: 0
                    ),
                    results: [
                        correct,
                        InboxAckOperationResult(
                            id: extraOperationID,
                            requestedStatus: .applied,
                            resultingStatus: "applied",
                            outcome: .updated,
                            conflict: nil
                        ),
                    ]
                )
            ),
            (
                "exactly one",
                InboxAckResponse(
                    counts: InboxAckCounts(
                        updated: 2,
                        unchanged: 0,
                        notFound: 0,
                        invalid: 0
                    ),
                    results: [correct, correct]
                )
            ),
        ]

        for (expectedDiagnostic, response) in scenarios {
            let result = try await runAckValidationScenario(response)
            #expect(
                result.syncError?
                    .localizedCaseInsensitiveContains(expectedDiagnostic) == true
            )
            #expect(result.pushCount == 1)
        }
    }

    @Test("an inbox-applied custom exercise retries snapshot push after restart")
    func customExercisePushRetriesAfterRestart() async throws {
        // Arrange
        let defaults = UserDefaults(
            suiteName: "sync-dirty-restart-\(UUID())"
        )!
        let env = try SyncTestEnv(defaults: defaults)
        env.network.fetchInboxResult = InboxListResponse(
            operations: [
                InboxOperationDTO(
                    id: "10000000-0000-4000-8000-000000000005",
                    createdAt: "2026-07-27T12:00:00.000Z",
                    op: "createCustomExercise",
                    payload: .object([
                        "name": .string("Restart Sled Drag"),
                        "externalId": .string(
                            "custom:restart-sled-drag:10000000-0000-4000-8000-000000000005"
                        ),
                    ]),
                    requiresApproval: false,
                    status: "pending",
                    appliedAt: nil,
                    error: nil
                )
            ]
        )
        env.network.pushSnapshotError = SyncError.serverError(500)

        // Act — local apply succeeds, but the first snapshot push fails.
        await env.manager.syncIfNeeded()

        // Assert — the durable trigger survives a new SettingsManager and
        // causes a push even though the restarted app sees an empty inbox.
        #expect(env.settings.isSnapshotDirty == true)
        env.network.fetchInboxResult = InboxListResponse(operations: [])
        env.network.pushSnapshotError = nil
        env.network.pushSnapshotResult = makePushResponse(revision: 2)
        let reloadedSettings = SettingsManager(defaults: defaults)
        let restarted = SyncManager(
            workoutRepository: env.workoutRepo,
            templateRepository: env.templateRepo,
            exerciseRepository: env.exerciseRepo,
            bodyWeightRepository: env.bodyWeightRepo,
            exerciseReportRepository: env.reportRepo,
            networkService: env.network,
            settings: reloadedSettings,
            inboxApplier: env.inboxApplier
        )
        await restarted.syncIfNeeded()

        #expect(env.network.pushSnapshotCallCount == 2)
        #expect(
            env.network.lastSnapshotRequest?.snapshot.customExercises
                .contains { $0.name == "Restart Sled Drag" } == true
        )
        #expect(reloadedSettings.isSnapshotDirty == false)
        #expect(restarted.syncError == nil)
    }
}

@Suite("SyncManager Restore")
@MainActor
struct SyncManagerRestoreTests {
    /// Snapshot used by most restore tests: one custom exercise, one template
    /// referencing it, one workout referencing a bundled exercise plus one
    /// UNKNOWN exercise id, and one body-weight entry.
    private func makeServerSnapshot(
        bundledExerciseId: UUID,
        customExerciseId: UUID = UUID(),
        unknownExerciseId: UUID = UUID()
    ) -> SnapshotFetchResponse {
        let customDTO = ExerciseDTO(
            id: customExerciseId,
            name: "Cloud Custom Fly",
            force: "push", level: nil, mechanic: "isolation", equipment: "cable",
            instructions: ["Squeeze"], primaryMuscles: ["chest"], secondaryMuscles: [],
            isCustom: true, externalId: nil, notes: "seat at 4",
            imageURL: nil, photoURL: nil,
            tags: [ExerciseTagDTO(category: "muscle_group", value: "chest")]
        )
        let templateDTO = TemplateDTO(
            id: UUID(), name: "Cloud Template", notes: nil,
            createdAt: .now, updatedAt: .now, lastPerformedAt: nil,
            timesPerformed: 2, lastModified: .now,
            exercises: [
                TemplateExerciseDTO(
                    id: UUID(), exerciseId: customExerciseId, order: 0,
                    defaultSets: 3, defaultReps: 12, defaultWeight: 25,
                    defaultRestSeconds: 60, notes: nil
                )
            ]
        )
        let workoutDTO = WorkoutDTO(
            id: UUID(), templateId: nil, name: "Cloud Workout",
            startedAt: .now, completedAt: .now, notes: nil, lastModified: .now,
            exercises: [
                WorkoutExerciseDTO(
                    id: UUID(), exerciseId: bundledExerciseId, order: 0,
                    notes: nil, restSeconds: 90,
                    sets: [WorkoutSetDTO(
                        id: UUID(), order: 0, weight: 80, weightUnit: "kg",
                        reps: 8, isCompleted: true, completedAt: .now, notes: nil
                    )]
                ),
                WorkoutExerciseDTO(
                    id: UUID(), exerciseId: unknownExerciseId, order: 1,
                    notes: nil, restSeconds: 90,
                    sets: [WorkoutSetDTO(
                        id: UUID(), order: 0, weight: 40, weightUnit: "kg",
                        reps: 10, isCompleted: true, completedAt: .now, notes: nil
                    )]
                ),
            ]
        )
        let bodyWeightDTO = BodyWeightEntryDTO(
            id: UUID(), weightKg: 79.5, recordedAt: .now,
            source: "manual", healthKitSampleUUID: nil, lastModified: .now
        )
        return SnapshotFetchResponse(
            revision: 42,
            serverTime: Date(timeIntervalSinceReferenceDate: 795_000_000),
            snapshot: SyncSnapshot(
                workouts: [workoutDTO],
                templates: [templateDTO],
                customExercises: [customDTO],
                bodyWeightEntries: [bodyWeightDTO]
            )
        )
    }

    @Test("restore replaces local workouts, templates, custom exercises, and body weight")
    func restoreReplacesLocalState() async throws {
        // Arrange — local state that must all disappear
        let env = try SyncTestEnv()
        let bundled = TestFixtures.makeExercise(name: "Bench Press", isCustom: false)
        let localCustom = TestFixtures.makeExercise(name: "Doomed Custom", isCustom: true)
        env.context.insert(bundled)
        env.context.insert(localCustom)
        env.context.insert(Workout(name: "Doomed Workout", startedAt: .now))
        env.context.insert(WorkoutTemplate(name: "Doomed Template"))
        env.context.insert(BodyWeightEntry(weightKg: 99.9))
        try env.context.save()
        env.network.fetchSnapshotResult = makeServerSnapshot(bundledExerciseId: bundled.id)

        // Act
        let summary = try await env.manager.restoreFromSnapshot()

        // Assert — cloud state replaced local state wholesale
        let workouts = try await env.workoutRepo.fetchAll()
        #expect(workouts.count == 1)
        #expect(workouts.first?.name == "Cloud Workout")
        let templates = try await env.templateRepo.fetchAll()
        #expect(templates.count == 1)
        #expect(templates.first?.name == "Cloud Template")
        let customs = try await env.exerciseRepo.fetchAll().filter(\.isCustom)
        #expect(!customs.contains { $0.name == "Doomed Custom" })
        #expect(customs.contains { $0.name == "Cloud Custom Fly" })
        let entries = try await env.bodyWeightRepo.fetchAll()
        #expect(entries.count == 1)
        #expect(entries.first?.weightKg == 79.5)
        // Bundled library untouched
        #expect(try await env.exerciseRepo.fetch(id: bundled.id) != nil)
        #expect(summary.workouts == 1)
        #expect(summary.templates == 1)
        #expect(summary.customExercises == 1)
        #expect(summary.bodyWeightEntries == 1)
        #expect(summary.revision == 42)
    }

    @Test("restore creates a placeholder exercise for unresolvable exerciseIds")
    func restorePlaceholdersUnknownExercises() async throws {
        // Arrange
        let env = try SyncTestEnv()
        let bundled = TestFixtures.makeExercise(name: "Bench Press", isCustom: false)
        env.context.insert(bundled)
        try env.context.save()
        let unknownId = UUID()
        env.network.fetchSnapshotResult = makeServerSnapshot(
            bundledExerciseId: bundled.id, unknownExerciseId: unknownId
        )

        // Act
        let summary = try await env.manager.restoreFromSnapshot()

        // Assert — the workout kept BOTH exercises; sets survived on the placeholder
        let workout = try #require(try await env.workoutRepo.fetchAll().first)
        #expect(workout.exercises.count == 2)
        let placeholder = try #require(try await env.exerciseRepo.fetch(id: unknownId))
        #expect(placeholder.name == "Unknown exercise (restored)")
        #expect(placeholder.isCustom == true)
        let placeholderWE = try #require(workout.exercises.first { $0.exercise?.id == unknownId })
        #expect(placeholderWE.sets.count == 1)
        #expect(placeholderWE.sets.first?.weight == 40)
        #expect(summary.placeholderExercises == 1)
    }

    @Test("restore never touches chat, insights, or preferences")
    func restoreNeverTouchesChatInsightsPreferences() async throws {
        // Arrange
        let env = try SyncTestEnv()
        let bundled = TestFixtures.makeExercise(name: "Bench Press", isCustom: false)
        env.context.insert(bundled)
        let chat = TestFixtures.makeChatMessage(content: "keep me")
        let insight = TestFixtures.makeInsight(content: "keep me too")
        let pref = TestFixtures.makeTrainingPreference(key: "injury", value: "bad shoulder")
        env.context.insert(chat)
        env.context.insert(insight)
        env.context.insert(pref)
        try env.context.save()
        env.network.fetchSnapshotResult = makeServerSnapshot(bundledExerciseId: bundled.id)

        // Act
        _ = try await env.manager.restoreFromSnapshot()

        // Assert
        let chats = try env.context.fetch(FetchDescriptor<AIChatMessage>())
        #expect(chats.count == 1)
        let insights = try env.context.fetch(FetchDescriptor<ProactiveInsight>())
        #expect(insights.count == 1)
        let prefs = try env.context.fetch(FetchDescriptor<TrainingPreference>())
        #expect(prefs.count == 1)
        #expect(prefs.first?.value == "bad shoulder")
    }

    @Test("restored records are synced — restore does not trigger an immediate re-push")
    func restoredRecordsAreSynced() async throws {
        // Arrange
        let env = try SyncTestEnv()
        let bundled = TestFixtures.makeExercise(name: "Bench Press", isCustom: false)
        env.context.insert(bundled)
        try env.context.save()
        env.network.fetchSnapshotResult = makeServerSnapshot(bundledExerciseId: bundled.id)

        // Act
        _ = try await env.manager.restoreFromSnapshot()

        // Assert — local state now equals the mirror at that revision
        let workouts = try await env.workoutRepo.fetchAll()
        #expect(workouts.allSatisfy { $0.syncStatus == .synced })
        let templates = try await env.templateRepo.fetchAll()
        #expect(templates.allSatisfy { $0.syncStatus == .synced })
        let entries = try await env.bodyWeightRepo.fetchAll()
        #expect(entries.allSatisfy { $0.syncStatus == .synced })
        #expect(env.manager.lastRevision == 42)
        #expect(env.settings.lastSyncRevision == 42)
        await env.manager.syncIfNeeded()
        #expect(env.network.pushSnapshotCallCount == 0)
    }

    @Test("restored custom exercise carries its tags")
    func restoredCustomExerciseCarriesTags() async throws {
        // Arrange
        let env = try SyncTestEnv()
        let bundled = TestFixtures.makeExercise(name: "Bench Press", isCustom: false)
        env.context.insert(bundled)
        try env.context.save()
        let customId = UUID()
        env.network.fetchSnapshotResult = makeServerSnapshot(
            bundledExerciseId: bundled.id, customExerciseId: customId
        )

        // Act
        _ = try await env.manager.restoreFromSnapshot()

        // Assert
        let custom = try #require(try await env.exerciseRepo.fetch(id: customId))
        #expect(custom.tags.count == 1)
        #expect(custom.tags.first?.category == "muscle_group")
        #expect(custom.tags.first?.value == "chest")
    }

    @Test("restore from a fresh mirror (revision 0, empty arrays) refuses to wipe local data")
    func restoreFromFreshMirrorRefusesToWipe() async throws {
        // Arrange — server has never received a push: revision 0, all empty
        let env = try SyncTestEnv()
        env.context.insert(Workout(name: "Precious Local Workout", startedAt: .now))
        try env.context.save()
        env.network.fetchSnapshotResult = SnapshotFetchResponse(
            revision: 0,
            serverTime: .now,
            snapshot: SyncSnapshot(
                workouts: [], templates: [], customExercises: [], bodyWeightEntries: []
            )
        )

        // Act + Assert — treated as "nothing to restore", local data survives
        await #expect(throws: SyncError.self) {
            _ = try await env.manager.restoreFromSnapshot()
        }
        let workouts = try await env.workoutRepo.fetchAll()
        #expect(workouts.count == 1)
        #expect(workouts.first?.name == "Precious Local Workout")
    }

    @Test("failed snapshot fetch leaves local data untouched")
    func failedFetchLeavesLocalDataUntouched() async throws {
        // Arrange
        let env = try SyncTestEnv()
        env.context.insert(Workout(name: "Safe Workout", startedAt: .now))
        try env.context.save()
        env.network.errorToThrow = SyncError.serverError(503)

        // Act + Assert
        await #expect(throws: SyncError.self) {
            _ = try await env.manager.restoreFromSnapshot()
        }
        let workouts = try await env.workoutRepo.fetchAll()
        #expect(workouts.count == 1)
        #expect(workouts.first?.name == "Safe Workout")
    }
}

@Suite("SyncManager State")
@MainActor
struct SyncStateTests {
    /// Build a SyncManager with isolated UserDefaults; only `settings.serverURL`
    /// matters for these tests. Returns the env so the container stays retained.
    private func makeEnv(serverURL: String = "") throws -> SyncTestEnv {
        try SyncTestEnv(serverURL: serverURL)
    }

    @Test("status is .disabled when serverURL is empty")
    func disabledWhenNoServerURL() throws {
        let env = try makeEnv(serverURL: "")
        #expect(env.manager.state == SyncState.disabled)
    }

    @Test("status is .pending when configured but never synced and online")
    func pendingWhenConfiguredAndIdle() throws {
        let env = try makeEnv(serverURL: "https://example.com")
        env.manager.isConnected = true
        #expect(env.manager.state == SyncState.pending)
    }

    @Test("status is .offline when configured but no connectivity")
    func offlineWhenDisconnected() throws {
        let env = try makeEnv(serverURL: "https://example.com")
        env.manager.isConnected = false
        #expect(env.manager.state == SyncState.offline)
    }

    @Test("status is .syncing while a sync is in flight")
    func syncingWhenInFlight() throws {
        let env = try makeEnv(serverURL: "https://example.com")
        env.manager.isConnected = true
        env.manager.isSyncing = true
        #expect(env.manager.state == SyncState.syncing)
    }

    @Test("status is .error when last attempt failed")
    func errorAfterFailure() throws {
        let env = try makeEnv(serverURL: "https://example.com")
        env.manager.isConnected = true
        env.manager.syncError = "401 Unauthorized"
        if case .error(let msg) = env.manager.state {
            #expect(msg == "401 Unauthorized")
        } else {
            Issue.record("expected .error, got \(env.manager.state)")
        }
    }

    @Test("status is .synced when a successful sync timestamp exists")
    func syncedWhenTimestampSet() throws {
        let env = try makeEnv(serverURL: "https://example.com")
        env.manager.isConnected = true
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        env.manager.lastSyncDate = when
        if case .synced(let date) = env.manager.state {
            #expect(date == when)
        } else {
            Issue.record("expected .synced, got \(env.manager.state)")
        }
    }

    @Test("manager seeds lastRevision from settings on init")
    func seedsRevisionFromSettings() throws {
        let defaults = UserDefaults(suiteName: "sync-seed-\(UUID())")!
        let settings = SettingsManager(defaults: defaults)
        settings.lastSyncRevision = 17
        let container = try makeTestContainer()
        let context = container.mainContext
        let manager = SyncManager(
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: SwiftDataTemplateRepository(context: context),
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            bodyWeightRepository: SwiftDataBodyWeightRepository(context: context),
            exerciseReportRepository: SwiftDataExerciseReportRepository(context: context),
            networkService: MockNetworkService(),
            settings: settings,
            inboxApplier: InboxApplier(
                templateRepository: SwiftDataTemplateRepository(context: context),
                exerciseRepository: SwiftDataExerciseRepository(context: context),
                reportRepository: SwiftDataExerciseReportRepository(context: context)
            )
        )
        #expect(manager.lastRevision == 17)
        _ = container
    }

    // Priority order: disabled > offline > syncing > error > synced > pending.

    @Test("disabled wins over every other condition")
    func disabledOverridesAll() throws {
        let env = try makeEnv(serverURL: "")
        env.manager.isConnected = false
        env.manager.isSyncing = true
        env.manager.syncError = "boom"
        env.manager.lastSyncDate = .now
        #expect(env.manager.state == SyncState.disabled)
    }

    @Test("offline beats error and synced when connectivity is gone")
    func offlineBeatsLowerPriority() throws {
        let env = try makeEnv(serverURL: "https://example.com")
        env.manager.isConnected = false
        env.manager.syncError = "previous failure"
        env.manager.lastSyncDate = .now
        #expect(env.manager.state == SyncState.offline)
    }

    @Test("syncing beats error and synced while running")
    func syncingBeatsLowerPriority() throws {
        let env = try makeEnv(serverURL: "https://example.com")
        env.manager.isConnected = true
        env.manager.isSyncing = true
        env.manager.syncError = "previous failure"
        env.manager.lastSyncDate = .now
        #expect(env.manager.state == SyncState.syncing)
    }

    @Test("error beats synced when both are present and online idle")
    func errorBeatsSynced() throws {
        let env = try makeEnv(serverURL: "https://example.com")
        env.manager.isConnected = true
        env.manager.syncError = "401"
        env.manager.lastSyncDate = .now
        if case .error = env.manager.state {} else {
            Issue.record("expected .error, got \(env.manager.state)")
        }
    }
}

@Suite("SyncManager — exercise reports in the snapshot (#135)")
@MainActor
struct SyncManagerReportTests {

    @Test("Push carries reports and marks them synced")
    func pushIncludesReports() async throws {
        // Arrange
        let env = try SyncTestEnv()
        let report = ExerciseReport(
            category: .wrongExercise,
            detail: "Mislabeled machine",
            exerciseExternalId: "Barbell_Bench_Press_-_Medium_Grip"
        )
        try await env.reportRepo.save(report)
        env.network.pushSnapshotResult = SnapshotPushResponse(
            revision: 3,
            serverTime: Date(timeIntervalSinceReferenceDate: 800_000_000),
            counts: [:]
        )

        // Act
        try await env.manager.pushSnapshot()

        // Assert
        let sent = try #require(env.network.lastSnapshotRequest)
        #expect(sent.snapshot.exerciseReports.count == 1)
        #expect(sent.snapshot.exerciseReports.first?.category == "wrongExercise")
        #expect(sent.snapshot.exerciseReports.first?.detail == "Mislabeled machine")
        #expect(report.syncStatus == .synced)
    }

    @Test("A pending report alone is enough to trigger a push")
    func pendingReportTriggersPush() async throws {
        let env = try SyncTestEnv()
        try await env.reportRepo.save(
            ExerciseReport(category: .bug, detail: "timer double-fired")
        )
        env.network.fetchInboxResult = InboxListResponse(operations: [])
        env.network.pushSnapshotResult = SnapshotPushResponse(
            revision: 1,
            serverTime: Date(timeIntervalSinceReferenceDate: 800_000_000),
            counts: [:]
        )

        await env.manager.syncIfNeeded()

        #expect(env.network.pushSnapshotCallCount == 1)
    }

    @Test("Restore replaces local reports with the mirror's")
    func restoreReplacesReports() async throws {
        // Arrange
        let env = try SyncTestEnv()
        try await env.reportRepo.save(
            ExerciseReport(category: .bug, detail: "doomed local report")
        )
        let mirrored = ExerciseReportDTO(
            id: UUID(),
            createdAt: Date(timeIntervalSinceReferenceDate: 795_000_000),
            category: "swapRequest",
            detail: "from the mirror",
            exerciseExternalId: "squat",
            exerciseName: "Squat",
            suggestedReplacement: "Leg Press",
            workoutId: nil,
            workoutExerciseId: nil,
            templateId: nil,
            contextSummary: nil,
            status: "acknowledged",
            resolution: "looking into it",
            appVersion: "1.4.0 (42)",
            iosVersion: "26.5",
            photoURL: nil,
            lastModified: Date(timeIntervalSinceReferenceDate: 795_000_000)
        )
        env.network.fetchSnapshotResult = SnapshotFetchResponse(
            revision: 9,
            serverTime: Date(timeIntervalSinceReferenceDate: 795_000_000),
            snapshot: SyncSnapshot(
                workouts: [], templates: [], customExercises: [],
                bodyWeightEntries: [], exerciseReports: [mirrored]
            )
        )

        // Act
        let summary = try await env.manager.restoreFromSnapshot()

        // Assert
        #expect(summary.exerciseReports == 1)
        let restored = try await env.reportRepo.fetchAll()
        #expect(restored.count == 1)
        #expect(restored.first?.detail == "from the mirror")
        #expect(restored.first?.status == .acknowledged)
        #expect(restored.first?.syncStatus == .synced)
    }
}

@Suite("SyncManager — custom exercises trigger a push (#104)")
@MainActor
struct SyncManagerCustomExerciseTriggerTests {

    @Test("A custom exercise created through the UI is enough to trigger a push")
    func customExerciseTriggersPush() async throws {
        // Arrange — nothing else is pending, which is exactly the case that
        // used to leave a custom exercise stranded indefinitely.
        let env = try SyncTestEnv()
        let repository = SwiftDataExerciseRepository(
            context: env.context,
            onCustomExerciseChanged: { env.settings.markSnapshotDirty() }
        )
        try await repository.save(
            Exercise(name: "Cable Katana Extension", isCustom: true)
        )
        env.network.fetchInboxResult = InboxListResponse(operations: [])
        env.network.pushSnapshotResult = SnapshotPushResponse(
            revision: 1,
            serverTime: Date(timeIntervalSinceReferenceDate: 800_000_000),
            counts: [:]
        )

        // Act
        await env.manager.syncIfNeeded()

        // Assert
        #expect(env.network.pushSnapshotCallCount == 1)
        let sent = try #require(env.network.lastSnapshotRequest)
        #expect(sent.snapshot.customExercises.count == 1)
        #expect(env.settings.isSnapshotDirty == false)
    }

    @Test("A custom exercise created mid-push is not silently marked clean")
    func customExerciseCreatedDuringPushSurvives() async throws {
        // The main actor is reentrant: pushSnapshot serializes, awaits, then
        // clears. A create landing inside that await was never in the payload
        // and used to have its only signal wiped by the clear.
        let env = try SyncTestEnv()
        let repository = SwiftDataExerciseRepository(
            context: env.context,
            onCustomExerciseChanged: { env.settings.markSnapshotDirty() }
        )
        env.settings.markSnapshotDirty()
        env.network.pushSnapshotResult = SnapshotPushResponse(
            revision: 1,
            serverTime: Date(timeIntervalSinceReferenceDate: 800_000_000),
            counts: [:]
        )
        env.network.onPushSnapshot = {
            env.settings.markSnapshotDirty()
        }

        // Act
        try await env.manager.pushSnapshot()

        // Assert — still dirty, so the next trigger picks the new exercise up.
        #expect(env.settings.isSnapshotDirty == true)
        _ = repository
    }
}
