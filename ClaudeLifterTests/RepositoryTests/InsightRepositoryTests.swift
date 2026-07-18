import Testing
import SwiftData
import Foundation
@testable import ClaudeLifter

@Suite("InsightRepository Tests")
struct InsightRepositoryTests {
    @Test("fetchAll returns empty when no insights")
    @MainActor
    func fetchAllEmpty() async throws {
        let container = try makeTestContainer()
        let repo = SwiftDataInsightRepository(context: container.mainContext)
        let results = try await repo.fetchAll()
        #expect(results.isEmpty)
    }

    @Test("save persists an insight")
    @MainActor
    func saveInsight() async throws {
        let container = try makeTestContainer()
        let repo = SwiftDataInsightRepository(context: container.mainContext)
        let insight = ProactiveInsight(content: "Train legs!", type: .warning)
        try await repo.save(insight)

        let results = try await repo.fetchAll()
        #expect(results.count == 1)
        #expect(results[0].content == "Train legs!")
    }

    @Test("fetchUnread returns only unread insights")
    @MainActor
    func fetchUnread() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataInsightRepository(context: context)

        let unread = ProactiveInsight(content: "Unread insight", type: .suggestion, isRead: false)
        let read = ProactiveInsight(content: "Read insight", type: .encouragement, isRead: true)
        context.insert(unread)
        context.insert(read)
        try context.save()

        let results = try await repo.fetchUnread()
        #expect(results.count == 1)
        #expect(results[0].content == "Unread insight")
    }

    @Test("markAsRead sets isRead to true")
    @MainActor
    func markAsRead() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataInsightRepository(context: context)

        let insight = ProactiveInsight(content: "Train legs!", type: .warning, isRead: false)
        context.insert(insight)
        try context.save()

        try await repo.markAsRead(insight)
        #expect(insight.isRead == true)
    }

    // fetchPending was removed with insight sync (issue #78) — insights are
    // local-only now; the one-way snapshot mirror covers workouts, templates,
    // custom exercises, and body weight.

    @Test("fetchAll returns insights sorted by generatedAt descending")
    @MainActor
    func fetchAllSorted() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let repo = SwiftDataInsightRepository(context: context)

        let older = ProactiveInsight(
            content: "Older",
            type: .suggestion,
            generatedAt: Date(timeIntervalSinceNow: -3600)
        )
        let newer = ProactiveInsight(
            content: "Newer",
            type: .warning,
            generatedAt: Date(timeIntervalSinceNow: -100)
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        let results = try await repo.fetchAll()
        #expect(results.count == 2)
        #expect(results[0].content == "Newer")
        #expect(results[1].content == "Older")
    }
}
