import Foundation

/// The local view of the report backlog (issue #135).
///
/// Reports are normally closed out by the AI over MCP, but they must be
/// closeable here too — a backlog you can only clear from another device is a
/// backlog you stop trusting.
@MainActor
@Observable
final class ReportListViewModel {
    private(set) var reports: [ExerciseReport] = []
    var errorMessage: String?
    var showsResolved = false

    private let repository: any ExerciseReportRepository

    init(repository: any ExerciseReportRepository) {
        self.repository = repository
    }

    var openCount: Int {
        reports.filter { $0.status != .resolved }.count
    }

    var visibleReports: [ExerciseReport] {
        showsResolved ? reports : reports.filter { $0.status != .resolved }
    }

    func load() async {
        do {
            reports = try await repository.fetchAll()
        } catch {
            errorMessage = "Couldn't load reports: \(error.localizedDescription)"
        }
    }

    func setStatus(_ status: ReportStatus, for report: ExerciseReport) async {
        report.status = status
        report.recordChange()
        do {
            try await repository.save(report)
            await load()
        } catch {
            errorMessage = "Couldn't update the report: \(error.localizedDescription)"
        }
    }

    func delete(_ report: ExerciseReport) async {
        do {
            try await repository.delete(report)
            await load()
        } catch {
            errorMessage = "Couldn't delete the report: \(error.localizedDescription)"
        }
    }
}
