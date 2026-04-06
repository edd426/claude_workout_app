import Testing
import SwiftData
import Foundation
@testable import ClaudeLifter

@Suite("Sync Fields on Models Tests")
struct SyncFieldTests {
    // MARK: - syncStatusRaw tests

    @Test("Workout syncStatusRaw defaults to 'pending'")
    func workoutSyncStatusRawDefaultsPending() {
        let workout = Workout(name: "Push Day", startedAt: .now)
        #expect(workout.syncStatusRaw == "pending")
    }

    @Test("Workout syncStatusRaw stays in sync with syncStatus enum")
    func workoutSyncStatusRawSyncsWithEnum() {
        let workout = Workout(name: "Push Day", startedAt: .now)
        workout.syncStatus = .synced
        #expect(workout.syncStatusRaw == "synced")
        workout.syncStatus = .pending
        #expect(workout.syncStatusRaw == "pending")
    }

    @Test("WorkoutTemplate syncStatusRaw defaults to 'pending'")
    func templateSyncStatusRawDefaultsPending() {
        let template = WorkoutTemplate(name: "Push Day")
        #expect(template.syncStatusRaw == "pending")
    }

    @Test("WorkoutTemplate syncStatusRaw stays in sync with syncStatus enum")
    func templateSyncStatusRawSyncsWithEnum() {
        let template = WorkoutTemplate(name: "Push Day")
        template.syncStatus = .synced
        #expect(template.syncStatusRaw == "synced")
    }

    @Test("AIChatMessage syncStatusRaw defaults to 'pending'")
    func chatMessageSyncStatusRawDefaultsPending() {
        let msg = AIChatMessage(role: .user, content: "Hello")
        #expect(msg.syncStatusRaw == "pending")
    }

    @Test("AIChatMessage syncStatusRaw stays in sync with syncStatus enum")
    func chatMessageSyncStatusRawSyncsWithEnum() {
        let msg = AIChatMessage(role: .user, content: "Hello")
        msg.syncStatus = .synced
        #expect(msg.syncStatusRaw == "synced")
    }

    @Test("ProactiveInsight syncStatusRaw defaults to 'pending'")
    func insightSyncStatusRawDefaultsPending() {
        let insight = ProactiveInsight(content: "Train legs!", type: .suggestion)
        #expect(insight.syncStatusRaw == "pending")
    }

    @Test("ProactiveInsight syncStatusRaw stays in sync with syncStatus enum")
    func insightSyncStatusRawSyncsWithEnum() {
        let insight = ProactiveInsight(content: "Train legs!", type: .suggestion)
        insight.syncStatus = .synced
        #expect(insight.syncStatusRaw == "synced")
    }

    @Test("TrainingPreference syncStatusRaw defaults to 'pending'")
    func preferenceSyncStatusRawDefaultsPending() {
        let pref = TrainingPreference(key: "style", value: "strength")
        #expect(pref.syncStatusRaw == "pending")
    }

    @Test("TrainingPreference syncStatusRaw stays in sync with syncStatus enum")
    func preferenceSyncStatusRawSyncsWithEnum() {
        let pref = TrainingPreference(key: "style", value: "strength")
        pref.syncStatus = .synced
        #expect(pref.syncStatusRaw == "synced")
    }

    @Test("Predicate can filter Workout by syncStatusRaw")
    @MainActor
    func predicateCanFilterWorkoutBySyncStatusRaw() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let pending = Workout(name: "Pending", startedAt: .now, syncStatus: .pending)
        let synced = Workout(name: "Synced", startedAt: .now, syncStatus: .synced)
        context.insert(pending)
        context.insert(synced)
        try context.save()

        let pendingRaw = "pending"
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.syncStatusRaw == pendingRaw }
        )
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results[0].name == "Pending")
    }

    @Test("Predicate can filter WorkoutTemplate by syncStatusRaw")
    @MainActor
    func predicateCanFilterTemplateBySyncStatusRaw() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let pending = WorkoutTemplate(name: "Pending", syncStatus: .pending)
        let synced = WorkoutTemplate(name: "Synced", syncStatus: .synced)
        context.insert(pending)
        context.insert(synced)
        try context.save()

        let pendingRaw = "pending"
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { $0.syncStatusRaw == pendingRaw }
        )
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results[0].name == "Pending")
    }

    // MARK: - Original sync field tests

    @Test("WorkoutTemplate has default syncStatus of .pending")
    func workoutTemplateDefaultSyncStatus() {
        let template = WorkoutTemplate(name: "Push Day")
        #expect(template.syncStatus == .pending)
    }

    @Test("WorkoutTemplate has lastModified set on init")
    func workoutTemplateLastModified() {
        let before = Date()
        let template = WorkoutTemplate(name: "Push Day")
        let after = Date()
        #expect(template.lastModified >= before)
        #expect(template.lastModified <= after)
    }

    @Test("WorkoutTemplate syncStatus can be set to synced")
    func workoutTemplateSyncStatusMutable() {
        let template = WorkoutTemplate(name: "Push Day")
        template.syncStatus = .synced
        #expect(template.syncStatus == .synced)
    }

    @Test("ProactiveInsight has default syncStatus of .pending")
    func proactiveInsightDefaultSyncStatus() {
        let insight = ProactiveInsight(content: "Train legs!", type: .suggestion)
        #expect(insight.syncStatus == .pending)
    }

    @Test("ProactiveInsight has lastModified set on init")
    func proactiveInsightLastModified() {
        let before = Date()
        let insight = ProactiveInsight(content: "Train legs!", type: .suggestion)
        let after = Date()
        #expect(insight.lastModified >= before)
        #expect(insight.lastModified <= after)
    }

    @Test("TrainingPreference has default syncStatus of .pending")
    func trainingPreferenceDefaultSyncStatus() {
        let pref = TrainingPreference(key: "style", value: "strength")
        #expect(pref.syncStatus == .pending)
    }

    @Test("TrainingPreference has lastModified set on init")
    func trainingPreferenceLastModified() {
        let before = Date()
        let pref = TrainingPreference(key: "style", value: "strength")
        let after = Date()
        #expect(pref.lastModified >= before)
        #expect(pref.lastModified <= after)
    }
}
