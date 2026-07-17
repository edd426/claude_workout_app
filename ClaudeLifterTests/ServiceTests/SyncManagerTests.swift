import Testing
import Foundation
@testable import ClaudeLifter

@Suite("SyncManager Tests")
@MainActor
struct SyncManagerTests {
    // MARK: - Push

    @Test("push collects pending workouts and calls network POST")
    func pushCollectsPendingWorkouts() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let pending = Workout(name: "Push Day", startedAt: .now, syncStatus: .pending)
        context.insert(pending)
        try context.save()

        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let chatRepo = SwiftDataChatMessageRepository(context: context)
        let insightRepo = SwiftDataInsightRepository(context: context)
        let prefRepo = SwiftDataTrainingPreferenceRepository(context: context)

        let network = MockNetworkService()
        network.setResponse(
            SyncPushResponse(
                accepted: 1, conflicts: 0, serverTimestamp: Date(),
                results: [SyncPushRecordResult(id: pending.id, collection: "workouts", status: "accepted")]
            ),
            forEndpoint: "/api/sync/push"
        )

        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-push-\(UUID())")!)
        settings.serverURL = "https://example.com"

        let manager = SyncManager(
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            chatRepository: chatRepo,
            insightRepository: insightRepo,
            preferenceRepository: prefRepo,
            networkService: network,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            settings: settings
        )

        try await manager.push()

        #expect(network.postCallCount == 1)
        #expect(network.lastPostEndpoint == "/api/sync/push")
    }

    @Test("push marks workouts as synced after success")
    func pushMarksSynced() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let pending = Workout(name: "Leg Day", startedAt: .now, syncStatus: .pending)
        context.insert(pending)
        try context.save()

        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let chatRepo = SwiftDataChatMessageRepository(context: context)
        let insightRepo = SwiftDataInsightRepository(context: context)
        let prefRepo = SwiftDataTrainingPreferenceRepository(context: context)

        let network = MockNetworkService()
        network.setResponse(
            SyncPushResponse(
                accepted: 1, conflicts: 0, serverTimestamp: Date(),
                results: [SyncPushRecordResult(id: pending.id, collection: "workouts", status: "accepted")]
            ),
            forEndpoint: "/api/sync/push"
        )

        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-synced-\(UUID())")!)
        settings.serverURL = "https://example.com"

        let manager = SyncManager(
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            chatRepository: chatRepo,
            insightRepository: insightRepo,
            preferenceRepository: prefRepo,
            networkService: network,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            settings: settings
        )

        try await manager.push()

        let workouts = try await workoutRepo.fetchAll()
        #expect(workouts[0].syncStatus == .synced)
    }

    @Test("push keeps rejected records pending and marks accepted synced")
    func pushKeepsRejectedPending() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let accepted = Workout(name: "Accepted", startedAt: .now, syncStatus: .pending)
        let rejected = Workout(name: "Rejected", startedAt: .now, syncStatus: .pending)
        let errored = Workout(name: "Errored", startedAt: .now, syncStatus: .pending)
        context.insert(accepted)
        context.insert(rejected)
        context.insert(errored)
        try context.save()

        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let network = MockNetworkService()
        network.setResponse(
            SyncPushResponse(
                accepted: 1, conflicts: 1, serverTimestamp: Date(),
                results: [
                    SyncPushRecordResult(id: accepted.id, collection: "workouts", status: "accepted"),
                    SyncPushRecordResult(id: rejected.id, collection: "workouts", status: "conflict"),
                    SyncPushRecordResult(id: errored.id, collection: "workouts", status: "error")
                ]
            ),
            forEndpoint: "/api/sync/push"
        )

        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-reject-\(UUID())")!)
        settings.serverURL = "https://example.com"

        let manager = SyncManager(
            workoutRepository: workoutRepo,
            templateRepository: SwiftDataTemplateRepository(context: context),
            chatRepository: SwiftDataChatMessageRepository(context: context),
            insightRepository: SwiftDataInsightRepository(context: context),
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context),
            networkService: network,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            settings: settings
        )

        try await manager.push()

        // Rejected and errored records must stay .pending so they retry;
        // marking them .synced is the issue-#74 silent data loss.
        #expect(accepted.syncStatus == .synced)
        #expect(rejected.syncStatus == .pending)
        #expect(errored.syncStatus == .pending)
    }

    @Test("push against a server without per-record results marks nothing synced")
    func pushLegacyServerMarksNothingSynced() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let pending = Workout(name: "Keep Me Pending", startedAt: .now, syncStatus: .pending)
        context.insert(pending)
        try context.save()

        let network = MockNetworkService()
        // Legacy server response: no `results` field.
        network.setResponse(
            SyncPushResponse(accepted: 1, conflicts: 0, serverTimestamp: Date()),
            forEndpoint: "/api/sync/push"
        )

        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-legacy-\(UUID())")!)
        settings.serverURL = "https://example.com"

        let manager = SyncManager(
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: SwiftDataTemplateRepository(context: context),
            chatRepository: SwiftDataChatMessageRepository(context: context),
            insightRepository: SwiftDataInsightRepository(context: context),
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context),
            networkService: network,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            settings: settings
        )

        await #expect(throws: SyncError.self) {
            try await manager.push()
        }
        #expect(pending.syncStatus == .pending)
    }

    @Test("edit made while push is in flight is not marked synced")
    func inFlightEditStaysPending() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let workout = Workout(name: "Edited Mid-Push", startedAt: .now, syncStatus: .pending)
        context.insert(workout)
        try context.save()

        let network = MockNetworkService()
        network.setResponse(
            SyncPushResponse(
                accepted: 1, conflicts: 0, serverTimestamp: Date(),
                results: [SyncPushRecordResult(id: workout.id, collection: "workouts", status: "accepted")]
            ),
            forEndpoint: "/api/sync/push"
        )
        // Simulate the user editing the workout while the POST is in flight.
        network.onPost = {
            workout.recordChange()
        }

        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-inflight-\(UUID())")!)
        settings.serverURL = "https://example.com"

        let manager = SyncManager(
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: SwiftDataTemplateRepository(context: context),
            chatRepository: SwiftDataChatMessageRepository(context: context),
            insightRepository: SwiftDataInsightRepository(context: context),
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context),
            networkService: network,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            settings: settings
        )

        try await manager.push()

        // The mid-flight edit set lastModified past the pushed snapshot; the
        // server acknowledged the OLD payload, so the edit must remain pending.
        #expect(workout.syncStatus == .pending)
    }

    @Test("push skips network call when nothing is pending")
    func pushSkipsWhenNothingPending() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let chatRepo = SwiftDataChatMessageRepository(context: context)
        let insightRepo = SwiftDataInsightRepository(context: context)
        let prefRepo = SwiftDataTrainingPreferenceRepository(context: context)

        let network = MockNetworkService()
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-skip-\(UUID())")!)
        settings.serverURL = "https://example.com"

        let manager = SyncManager(
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            chatRepository: chatRepo,
            insightRepository: insightRepo,
            preferenceRepository: prefRepo,
            networkService: network,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            settings: settings
        )

        try await manager.push()

        #expect(network.postCallCount == 0)
    }

    // MARK: - Pull

    @Test("pull calls network POST to /api/sync/pull")
    func pullCallsNetwork() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let chatRepo = SwiftDataChatMessageRepository(context: context)
        let insightRepo = SwiftDataInsightRepository(context: context)
        let prefRepo = SwiftDataTrainingPreferenceRepository(context: context)

        let network = MockNetworkService()
        let pullResponse = SyncPullResponse(
            workouts: [],
            templates: [],
            chat: [],
            insights: [],
            preferences: [],
            serverTimestamp: Date()
        )
        network.setResponse(pullResponse, forEndpoint: "/api/sync/pull")

        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-pull-\(UUID())")!)
        settings.serverURL = "https://example.com"

        let manager = SyncManager(
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            chatRepository: chatRepo,
            insightRepository: insightRepo,
            preferenceRepository: prefRepo,
            networkService: network,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            settings: settings
        )

        try await manager.pull()

        #expect(network.postCallCount == 1)
        #expect(network.lastPostEndpoint == "/api/sync/pull")
    }

    @Test("pull updates lastSyncDate after success")
    func pullUpdatesLastSyncDate() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let chatRepo = SwiftDataChatMessageRepository(context: context)
        let insightRepo = SwiftDataInsightRepository(context: context)
        let prefRepo = SwiftDataTrainingPreferenceRepository(context: context)

        let network = MockNetworkService()
        let serverTime = Date(timeIntervalSinceReferenceDate: 10000)
        let pullResponse = SyncPullResponse(
            workouts: [],
            templates: [],
            chat: [],
            insights: [],
            preferences: [],
            serverTimestamp: serverTime
        )
        network.setResponse(pullResponse, forEndpoint: "/api/sync/pull")

        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-lastSync-\(UUID())")!)
        settings.serverURL = "https://example.com"

        let manager = SyncManager(
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            chatRepository: chatRepo,
            insightRepository: insightRepo,
            preferenceRepository: prefRepo,
            networkService: network,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            settings: settings
        )

        try await manager.pull()

        #expect(manager.lastSyncDate == serverTime)
    }

    // MARK: - syncIfNeeded

    @Test("syncIfNeeded does nothing when server URL not configured")
    func syncIfNeededSkipsWhenNotConfigured() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let chatRepo = SwiftDataChatMessageRepository(context: context)
        let insightRepo = SwiftDataInsightRepository(context: context)
        let prefRepo = SwiftDataTrainingPreferenceRepository(context: context)

        let network = MockNetworkService()
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-notConfigured-\(UUID())")!)
        // serverURL left empty

        let manager = SyncManager(
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            chatRepository: chatRepo,
            insightRepository: insightRepo,
            preferenceRepository: prefRepo,
            networkService: network,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            settings: settings
        )

        await manager.syncIfNeeded()

        #expect(network.postCallCount == 0)
    }

    // MARK: - Pull inserts new records

    @Test("pull inserts new workouts from server")
    func pullInsertsNewWorkouts() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)
        try context.save()

        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let chatRepo = SwiftDataChatMessageRepository(context: context)
        let insightRepo = SwiftDataInsightRepository(context: context)
        let prefRepo = SwiftDataTrainingPreferenceRepository(context: context)
        let exerciseRepo = SwiftDataExerciseRepository(context: context)

        let setDTO = WorkoutSetDTO(
            id: UUID(), order: 0, weight: 80.0, weightUnit: "kg",
            reps: 5, isCompleted: true, completedAt: Date(), notes: nil
        )
        let weDTO = WorkoutExerciseDTO(
            id: UUID(), exerciseId: exercise.id, order: 0,
            notes: nil, restSeconds: 90, sets: [setDTO]
        )
        let workoutDTO = WorkoutDTO(
            id: UUID(), templateId: nil, name: "Server Workout",
            startedAt: Date(), completedAt: Date(), notes: nil,
            lastModified: Date(), exercises: [weDTO]
        )

        let network = MockNetworkService()
        let pullResponse = SyncPullResponse(
            workouts: [workoutDTO],
            templates: [],
            chat: [],
            insights: [],
            preferences: [],
            serverTimestamp: Date()
        )
        network.setResponse(pullResponse, forEndpoint: "/api/sync/pull")

        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-pull-insert-\(UUID())")!)
        settings.serverURL = "https://example.com"

        let manager = SyncManager(
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            chatRepository: chatRepo,
            insightRepository: insightRepo,
            preferenceRepository: prefRepo,
            networkService: network,
            exerciseRepository: exerciseRepo,
            settings: settings
        )

        try await manager.pull()

        let workouts = try await workoutRepo.fetchAll()
        #expect(workouts.count == 1)
        #expect(workouts[0].name == "Server Workout")
        #expect(workouts[0].exercises.count == 1)
        #expect(workouts[0].exercises[0].sets.count == 1)
    }

    @Test("restore round-trip: pull inserts new templates with their exercises")
    func restoreRoundTripInsertsTemplatesWithExercises() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)
        try context.save()

        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let chatRepo = SwiftDataChatMessageRepository(context: context)
        let insightRepo = SwiftDataInsightRepository(context: context)
        let prefRepo = SwiftDataTrainingPreferenceRepository(context: context)

        let teDTO = TemplateExerciseDTO(
            id: UUID(), exerciseId: exercise.id, order: 0,
            defaultSets: 3, defaultReps: 8, defaultWeight: 60.0,
            defaultRestSeconds: 90, notes: nil
        )
        let templateDTO = TemplateDTO(
            id: UUID(), name: "Server Push Day", notes: nil,
            createdAt: Date(), updatedAt: Date(), lastPerformedAt: nil,
            timesPerformed: 0, lastModified: Date(), exercises: [teDTO]
        )

        let network = MockNetworkService()
        network.setResponse(
            SyncPullResponse(
                workouts: [], templates: [templateDTO], chat: [],
                insights: [], preferences: [], serverTimestamp: Date()
            ),
            forEndpoint: "/api/sync/pull"
        )

        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-restore-\(UUID())")!)
        settings.serverURL = "https://example.com"

        // Mirrors DependencyContainer's SyncManager construction. Guards issue #73:
        // production omitted exerciseRepository, so a fresh install restored nothing.
        let manager = SyncManager(
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            chatRepository: chatRepo,
            insightRepository: insightRepo,
            preferenceRepository: prefRepo,
            networkService: network,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            settings: settings
        )

        try await manager.pull()

        let templates = try await templateRepo.fetchAll()
        #expect(templates.count == 1)
        #expect(templates.first?.name == "Server Push Day")
        #expect(templates.first?.exercises.count == 1)
        #expect(templates.first?.exercises.first?.defaultSets == 3)
    }

    @Test("pull inserts new insights from server")
    func pullInsertsNewInsights() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let chatRepo = SwiftDataChatMessageRepository(context: context)
        let insightRepo = SwiftDataInsightRepository(context: context)
        let prefRepo = SwiftDataTrainingPreferenceRepository(context: context)
        let exerciseRepo = SwiftDataExerciseRepository(context: context)

        let insightDTO = InsightDTO(
            id: UUID(), content: "Train legs!", type: "warning",
            generatedAt: Date(), isRead: false, lastModified: Date()
        )

        let network = MockNetworkService()
        let pullResponse = SyncPullResponse(
            workouts: [],
            templates: [],
            chat: [],
            insights: [insightDTO],
            preferences: [],
            serverTimestamp: Date()
        )
        network.setResponse(pullResponse, forEndpoint: "/api/sync/pull")

        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-pull-insight-\(UUID())")!)
        settings.serverURL = "https://example.com"

        let manager = SyncManager(
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            chatRepository: chatRepo,
            insightRepository: insightRepo,
            preferenceRepository: prefRepo,
            networkService: network,
            exerciseRepository: exerciseRepo,
            settings: settings
        )

        try await manager.pull()

        let insights = try await insightRepo.fetchAll()
        #expect(insights.count == 1)
        #expect(insights[0].content == "Train legs!")
    }

    // MARK: - First-sync nil timestamp (#54)

    @Test("pull with nil lastSyncTimestamp sends request and succeeds")
    func pullWithNilLastSyncTimestampSendsRequestAndSucceeds() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let chatRepo = SwiftDataChatMessageRepository(context: context)
        let insightRepo = SwiftDataInsightRepository(context: context)
        let prefRepo = SwiftDataTrainingPreferenceRepository(context: context)

        let network = MockNetworkService()
        let serverTime = Date(timeIntervalSinceReferenceDate: 50000)
        let pullResponse = SyncPullResponse(
            workouts: [],
            templates: [],
            chat: [],
            insights: [],
            preferences: [],
            serverTimestamp: serverTime
        )
        network.setResponse(pullResponse, forEndpoint: "/api/sync/pull")

        // Fresh SettingsManager — lastSyncTimestamp is nil (simulates first install)
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-nil-timestamp-\(UUID())")!)
        settings.serverURL = "https://example.com"
        #expect(settings.lastSyncTimestamp == nil)

        let manager = SyncManager(
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            chatRepository: chatRepo,
            insightRepository: insightRepo,
            preferenceRepository: prefRepo,
            networkService: network,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            settings: settings
        )

        try await manager.pull()

        #expect(network.postCallCount == 1)
        #expect(network.lastPostEndpoint == "/api/sync/pull")
        #expect(manager.lastSyncDate == serverTime)
        #expect(settings.lastSyncTimestamp == serverTime)
    }

    @Test("pull with nil timestamp merges new workouts from server")
    func pullWithNilTimestampMergesNewWorkouts() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Insert an exercise so the workout can reference it
        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        context.insert(exercise)
        try context.save()

        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let chatRepo = SwiftDataChatMessageRepository(context: context)
        let insightRepo = SwiftDataInsightRepository(context: context)
        let prefRepo = SwiftDataTrainingPreferenceRepository(context: context)
        let exerciseRepo = SwiftDataExerciseRepository(context: context)

        let setDTO = WorkoutSetDTO(
            id: UUID(), order: 0, weight: 100.0, weightUnit: "kg",
            reps: 5, isCompleted: true, completedAt: Date(), notes: nil
        )
        let weDTO = WorkoutExerciseDTO(
            id: UUID(), exerciseId: exercise.id, order: 0,
            notes: nil, restSeconds: 90, sets: [setDTO]
        )
        let workoutDTO = WorkoutDTO(
            id: UUID(), templateId: nil, name: "First Sync Workout",
            startedAt: Date(), completedAt: Date(), notes: nil,
            lastModified: Date(), exercises: [weDTO]
        )

        let network = MockNetworkService()
        let pullResponse = SyncPullResponse(
            workouts: [workoutDTO],
            templates: [],
            chat: [],
            insights: [],
            preferences: [],
            serverTimestamp: Date()
        )
        network.setResponse(pullResponse, forEndpoint: "/api/sync/pull")

        // Fresh settings — nil lastSyncTimestamp
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-nil-merge-\(UUID())")!)
        settings.serverURL = "https://example.com"
        #expect(settings.lastSyncTimestamp == nil)

        let manager = SyncManager(
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            chatRepository: chatRepo,
            insightRepository: insightRepo,
            preferenceRepository: prefRepo,
            networkService: network,
            exerciseRepository: exerciseRepo,
            settings: settings
        )

        try await manager.pull()

        let workouts = try await workoutRepo.fetchAll()
        #expect(workouts.count == 1)
        #expect(workouts[0].name == "First Sync Workout")
        #expect(workouts[0].exercises.count == 1)
        #expect(workouts[0].exercises[0].sets.count == 1)
    }

    // MARK: - mergePullResponse uses per-ID lookups (Task 4)

    @Test("mergePullResponse uses fetch(id:) not fetchAll for workouts")
    func mergePullUsesPerIdLookupForWorkouts() async throws {
        let mockWorkoutRepo = MockWorkoutRepository()
        let mockTemplateRepo = MockTemplateRepository()
        let mockChatRepo = MockChatMessageRepository()
        let mockInsightRepo = MockInsightRepository()
        let mockPrefRepo = MockTrainingPreferenceRepository()
        let mockExerciseRepo = MockExerciseRepository()

        let exercise = TestFixtures.makeExercise(name: "Bench Press")
        mockExerciseRepo.exercises = [exercise]

        let network = MockNetworkService()
        let workoutDTO = WorkoutDTO(
            id: UUID(), templateId: nil, name: "Server Workout",
            startedAt: Date(), completedAt: nil, notes: nil,
            lastModified: Date(), exercises: []
        )
        let pullResponse = SyncPullResponse(
            workouts: [workoutDTO],
            templates: [],
            chat: [],
            insights: [],
            preferences: [],
            serverTimestamp: Date()
        )
        network.setResponse(pullResponse, forEndpoint: "/api/sync/pull")

        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-perid-\(UUID())")!)
        settings.serverURL = "https://example.com"

        let manager = SyncManager(
            workoutRepository: mockWorkoutRepo,
            templateRepository: mockTemplateRepo,
            chatRepository: mockChatRepo,
            insightRepository: mockInsightRepo,
            preferenceRepository: mockPrefRepo,
            networkService: network,
            exerciseRepository: mockExerciseRepo,
            settings: settings
        )

        try await manager.pull()

        // Should NOT have called fetchAll on workout repo during merge
        #expect(mockWorkoutRepo.fetchAllCallCount == 0)
        // Should have saved the new workout
        #expect(mockWorkoutRepo.saveCallCount == 1)
    }

    @Test("mergePullResponse uses fetch(id:) not fetchAll for templates")
    func mergePullUsesPerIdLookupForTemplates() async throws {
        let mockWorkoutRepo = MockWorkoutRepository()
        let mockTemplateRepo = MockTemplateRepository()
        let mockChatRepo = MockChatMessageRepository()
        let mockInsightRepo = MockInsightRepository()
        let mockPrefRepo = MockTrainingPreferenceRepository()
        let mockExerciseRepo = MockExerciseRepository()

        let network = MockNetworkService()
        let templateDTO = TemplateDTO(
            id: UUID(), name: "Server Template", notes: nil,
            createdAt: Date(), updatedAt: Date(), lastPerformedAt: nil,
            timesPerformed: 0, lastModified: Date(), exercises: []
        )
        let pullResponse = SyncPullResponse(
            workouts: [],
            templates: [templateDTO],
            chat: [],
            insights: [],
            preferences: [],
            serverTimestamp: Date()
        )
        network.setResponse(pullResponse, forEndpoint: "/api/sync/pull")

        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-perid-tmpl-\(UUID())")!)
        settings.serverURL = "https://example.com"

        let manager = SyncManager(
            workoutRepository: mockWorkoutRepo,
            templateRepository: mockTemplateRepo,
            chatRepository: mockChatRepo,
            insightRepository: mockInsightRepo,
            preferenceRepository: mockPrefRepo,
            networkService: network,
            exerciseRepository: mockExerciseRepo,
            settings: settings
        )

        try await manager.pull()

        #expect(mockTemplateRepo.fetchAllCallCount == 0)
        #expect(mockTemplateRepo.saveCallCount == 1)
    }

    // MARK: - Error handling

    @Test("syncError is set when network throws")
    func syncErrorSetOnNetworkFailure() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let pending = Workout(name: "Push Day", startedAt: .now, syncStatus: .pending)
        context.insert(pending)
        try context.save()

        let workoutRepo = SwiftDataWorkoutRepository(context: context)
        let templateRepo = SwiftDataTemplateRepository(context: context)
        let chatRepo = SwiftDataChatMessageRepository(context: context)
        let insightRepo = SwiftDataInsightRepository(context: context)
        let prefRepo = SwiftDataTrainingPreferenceRepository(context: context)

        let network = MockNetworkService()
        network.errorToThrow = SyncError.networkUnavailable

        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-error-\(UUID())")!)
        settings.serverURL = "https://example.com"

        let manager = SyncManager(
            workoutRepository: workoutRepo,
            templateRepository: templateRepo,
            chatRepository: chatRepo,
            insightRepository: insightRepo,
            preferenceRepository: prefRepo,
            networkService: network,
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            settings: settings
        )

        do {
            try await manager.push()
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is SyncError)
        }
    }
}

@Suite("SyncManager State")
@MainActor
struct SyncStateTests {
    /// Build a SyncManager with isolated UserDefaults; only `settings.serverURL`
    /// matters for these tests. All other deps are inert.
    private func makeManager(serverURL: String = "") throws -> (SyncManager, SettingsManager) {
        let container = try makeTestContainer()
        let context = container.mainContext
        let settings = SettingsManager(
            defaults: UserDefaults(suiteName: "sync-status-\(UUID())")!
        )
        settings.serverURL = serverURL

        let manager = SyncManager(
            workoutRepository: SwiftDataWorkoutRepository(context: context),
            templateRepository: SwiftDataTemplateRepository(context: context),
            chatRepository: SwiftDataChatMessageRepository(context: context),
            insightRepository: SwiftDataInsightRepository(context: context),
            preferenceRepository: SwiftDataTrainingPreferenceRepository(context: context),
            networkService: MockNetworkService(),
            exerciseRepository: SwiftDataExerciseRepository(context: context),
            settings: settings
        )
        return (manager, settings)
    }

    @Test("status is .disabled when serverURL is empty")
    func disabledWhenNoServerURL() throws {
        let (manager, _) = try makeManager(serverURL: "")
        #expect(manager.state == SyncState.disabled)
    }

    @Test("status is .pending when configured but never synced and online")
    func pendingWhenConfiguredAndIdle() throws {
        let (manager, _) = try makeManager(serverURL: "https://example.com")
        manager.isConnected = true
        #expect(manager.state == SyncState.pending)
    }

    @Test("status is .offline when configured but no connectivity")
    func offlineWhenDisconnected() throws {
        let (manager, _) = try makeManager(serverURL: "https://example.com")
        manager.isConnected = false
        #expect(manager.state == SyncState.offline)
    }

    @Test("status is .syncing while a sync is in flight")
    func syncingWhenInFlight() throws {
        let (manager, _) = try makeManager(serverURL: "https://example.com")
        manager.isConnected = true
        manager.isSyncing = true
        #expect(manager.state == SyncState.syncing)
    }

    @Test("status is .error when last attempt failed")
    func errorAfterFailure() throws {
        let (manager, _) = try makeManager(serverURL: "https://example.com")
        manager.isConnected = true
        manager.syncError = "401 Unauthorized"
        if case .error(let msg) = manager.state {
            #expect(msg == "401 Unauthorized")
        } else {
            Issue.record("expected .error, got \(manager.state)")
        }
    }

    @Test("status is .synced when a successful sync timestamp exists")
    func syncedWhenTimestampSet() throws {
        let (manager, _) = try makeManager(serverURL: "https://example.com")
        manager.isConnected = true
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        manager.lastSyncDate = when
        if case .synced(let date) = manager.state {
            #expect(date == when)
        } else {
            Issue.record("expected .synced, got \(manager.state)")
        }
    }

    // Priority order: disabled > offline > syncing > error > synced > pending.
    // The intent is to surface the most actionable state first.

    @Test("disabled wins over every other condition")
    func disabledOverridesAll() throws {
        let (manager, settings) = try makeManager(serverURL: "")
        manager.isConnected = false
        manager.isSyncing = true
        manager.syncError = "boom"
        manager.lastSyncDate = .now
        _ = settings
        #expect(manager.state == SyncState.disabled)
    }

    @Test("offline beats error and synced when connectivity is gone")
    func offlineBeatsLowerPriority() throws {
        let (manager, _) = try makeManager(serverURL: "https://example.com")
        manager.isConnected = false
        manager.syncError = "previous failure"
        manager.lastSyncDate = .now
        #expect(manager.state == SyncState.offline)
    }

    @Test("syncing beats error and synced while running")
    func syncingBeatsLowerPriority() throws {
        let (manager, _) = try makeManager(serverURL: "https://example.com")
        manager.isConnected = true
        manager.isSyncing = true
        manager.syncError = "previous failure"
        manager.lastSyncDate = .now
        #expect(manager.state == SyncState.syncing)
    }

    @Test("error beats synced when both are present and online idle")
    func errorBeatsSynced() throws {
        let (manager, _) = try makeManager(serverURL: "https://example.com")
        manager.isConnected = true
        manager.syncError = "401"
        manager.lastSyncDate = .now
        if case .error = manager.state {} else {
            Issue.record("expected .error, got \(manager.state)")
        }
    }
}
