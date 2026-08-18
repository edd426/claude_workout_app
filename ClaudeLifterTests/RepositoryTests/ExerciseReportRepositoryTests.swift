import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

@Suite("ExerciseReportRepository Tests")
@MainActor
struct ExerciseReportRepositoryTests {

    private struct Setup {
        let container: ModelContainer
        let repository: SwiftDataExerciseReportRepository
    }

    private func makeSetup() throws -> Setup {
        let container = try makeTestContainer()
        return Setup(
            container: container,
            repository: SwiftDataExerciseReportRepository(context: container.mainContext)
        )
    }

    @Test("Saved reports fetch newest-first")
    func fetchAllNewestFirst() async throws {
        let setup = try makeSetup()
        try await setup.repository.save(ExerciseReport(
            createdAt: Date(timeIntervalSinceNow: -3600),
            category: .bug,
            detail: "Rest timer fired twice"
        ))
        try await setup.repository.save(ExerciseReport(
            createdAt: .now,
            category: .swapRequest,
            detail: "Swap this for a machine row"
        ))

        let all = try await setup.repository.fetchAll()
        #expect(all.count == 2)
        #expect(all.first?.detail == "Swap this for a machine row")
    }

    @Test("fetch by id returns the matching report")
    func fetchByID() async throws {
        let setup = try makeSetup()
        let id = UUID()
        try await setup.repository.save(ExerciseReport(
            id: id, category: .other, detail: "Something"
        ))

        let found = try await setup.repository.fetch(id: id)
        #expect(found?.id == id)
        #expect(try await setup.repository.fetch(id: UUID()) == nil)
    }

    @Test("fetchOpen excludes resolved but keeps acknowledged")
    func fetchOpenExcludesResolvedOnly() async throws {
        let setup = try makeSetup()
        try await setup.repository.save(ExerciseReport(
            category: .bug, detail: "open one", status: .open
        ))
        try await setup.repository.save(ExerciseReport(
            category: .bug, detail: "seen but not fixed", status: .acknowledged
        ))
        try await setup.repository.save(ExerciseReport(
            category: .bug, detail: "done", status: .resolved
        ))

        let open = try await setup.repository.fetchOpen()
        #expect(open.count == 2)
        #expect(!open.contains { $0.detail == "done" })
    }

    @Test("fetchPending returns only unsynced reports")
    func fetchPendingReturnsUnsynced() async throws {
        let setup = try makeSetup()
        try await setup.repository.save(ExerciseReport(
            category: .bug, detail: "not yet pushed", syncStatus: .pending
        ))
        try await setup.repository.save(ExerciseReport(
            category: .bug, detail: "already mirrored", syncStatus: .synced
        ))

        let pending = try await setup.repository.fetchPending()
        #expect(pending.count == 1)
        #expect(pending.first?.detail == "not yet pushed")
    }

    @Test("Deleting removes the report")
    func deleteRemovesReport() async throws {
        let setup = try makeSetup()
        let report = ExerciseReport(category: .other, detail: "temp")
        try await setup.repository.save(report)
        try await setup.repository.delete(report)

        #expect(try await setup.repository.fetchAll().isEmpty)
    }
}

@Suite("ExerciseReport Model Tests")
@MainActor
struct ExerciseReportModelTests {

    @Test("Unknown raw category and status fall back rather than crashing")
    func unknownRawValuesFallBack() {
        let report = ExerciseReport(category: .bug, detail: "x")
        report.categoryRaw = "somethingFromANewerBuild"
        report.statusRaw = "quarantined"

        #expect(report.category == .other)
        #expect(report.status == .open)
        // The raw value itself is untouched — the fallback is a read-time
        // convenience, not a rewrite.
        #expect(report.categoryRaw == "somethingFromANewerBuild")
    }

    @Test("recordChange re-queues the report for the next snapshot push")
    func recordChangeMarksPending() {
        let report = ExerciseReport(
            category: .bug, detail: "x", syncStatus: .synced
        )
        report.status = .resolved
        report.recordChange()

        #expect(report.syncStatus == .pending)
    }

    @Test("Every category has a distinct display name and icon")
    func categoriesAreDistinct() {
        let names = Set(ReportCategory.allCases.map(\.displayName))
        let icons = Set(ReportCategory.allCases.map(\.systemImage))
        #expect(names.count == ReportCategory.allCases.count)
        #expect(icons.count == ReportCategory.allCases.count)
    }
}
