import Testing
import Foundation
import SwiftData
@testable import ClaudeLifter

/// The report backlog's filter and counts (#146).
///
/// The bug this suite pins: `acknowledged` rendered as done (green resolution
/// text) while counting as open, and the only filter keyed on `resolved` — a
/// state nothing in the app or the write path ever produced. Six reports, three
/// of them answered, and the card still said "6 open reports".
@Suite("ReportListViewModel — status filter")
@MainActor
struct ReportListFilterTests {

    @MainActor
    private struct Env {
        let container: ModelContainer
        let context: ModelContext
        let repository: SwiftDataExerciseReportRepository
        let vm: ReportListViewModel

        init() throws {
            container = try makeTestContainer()
            context = container.mainContext
            repository = SwiftDataExerciseReportRepository(context: context)
            vm = ReportListViewModel(repository: repository)
        }

        @discardableResult
        func seed(_ status: ReportStatus, detail: String) throws -> ExerciseReport {
            let report = ExerciseReport(category: .bug, detail: detail)
            report.status = status
            context.insert(report)
            try context.save()
            return report
        }

        /// One of each, which is the shape of the real backlog.
        func seedOneOfEach() throws {
            try seed(.open, detail: "still open")
            try seed(.acknowledged, detail: "fix written, not installed")
            try seed(.resolved, detail: "done")
        }
    }

    @Test("The default filter is the live backlog: open and acknowledged, not resolved")
    func defaultFilterIsBacklog() async throws {
        let env = try Env()
        try env.seedOneOfEach()

        await env.vm.load()

        #expect(env.vm.statusFilter == .backlog)
        #expect(env.vm.visibleReports.count == 2)
        #expect(env.vm.visibleReports.allSatisfy { $0.status != .resolved })
    }

    @Test("Acknowledged is filterable on its own")
    func acknowledgedIsItsOwnFilter() async throws {
        let env = try Env()
        try env.seedOneOfEach()
        await env.vm.load()

        env.vm.statusFilter = .acknowledged

        #expect(env.vm.visibleReports.count == 1)
        #expect(env.vm.visibleReports.first?.detail == "fix written, not installed")
    }

    @Test("Every filter selects exactly its own status", arguments: [
        (ReportStatusFilter.open, "still open"),
        (ReportStatusFilter.acknowledged, "fix written, not installed"),
        (ReportStatusFilter.resolved, "done"),
    ])
    func singleStatusFilters(filter: ReportStatusFilter, expected: String) async throws {
        let env = try Env()
        try env.seedOneOfEach()
        await env.vm.load()

        env.vm.statusFilter = filter

        #expect(env.vm.visibleReports.map(\.detail) == [expected])
    }

    @Test("The all filter hides nothing")
    func allFilterShowsEverything() async throws {
        let env = try Env()
        try env.seedOneOfEach()
        await env.vm.load()

        env.vm.statusFilter = .all

        #expect(env.vm.visibleReports.count == 3)
    }

    /// The home card's number. It said 6 when three of the six carried a
    /// written resolution, because it counted everything not `resolved`.
    @Test("openCount counts only reports nobody has answered")
    func openCountExcludesAcknowledged() async throws {
        let env = try Env()
        try env.seedOneOfEach()

        await env.vm.load()

        #expect(env.vm.openCount == 1)
        #expect(env.vm.acknowledgedCount == 1)
    }

    @Test("A filter selecting nothing is empty rather than falling back to everything")
    func emptyFilterStaysEmpty() async throws {
        let env = try Env()
        try env.seed(.open, detail: "only an open one")
        await env.vm.load()

        env.vm.statusFilter = .resolved

        #expect(env.vm.visibleReports.isEmpty)
    }

    @Test("Acknowledging a report moves it out of the open count without hiding it")
    func acknowledgingKeepsItInTheBacklog() async throws {
        let env = try Env()
        let report = try env.seed(.open, detail: "will be acknowledged")
        await env.vm.load()

        await env.vm.setStatus(.acknowledged, for: report)

        #expect(env.vm.openCount == 0)
        #expect(env.vm.acknowledgedCount == 1)
        #expect(env.vm.visibleReports.count == 1)
    }

    /// The escape hatch #136 needed: a fix that turns out to be inert must be
    /// reopenable, or the backlog quietly loses a real complaint.
    @Test("A resolved report can be reopened")
    func resolvedCanBeReopened() async throws {
        let env = try Env()
        let report = try env.seed(.resolved, detail: "fix did nothing")
        await env.vm.load()

        await env.vm.setStatus(.open, for: report)

        #expect(env.vm.openCount == 1)
        env.vm.statusFilter = .backlog
        #expect(env.vm.visibleReports.count == 1)
    }
}
