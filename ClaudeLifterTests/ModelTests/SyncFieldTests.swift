import Testing
import Foundation
@testable import ClaudeLifter

@Suite("Sync Fields on Models Tests")
struct SyncFieldTests {
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
