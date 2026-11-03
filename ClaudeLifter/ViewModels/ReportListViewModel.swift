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
    var statusFilter: ReportStatusFilter = .backlog

    private let repository: any ExerciseReportRepository

    init(repository: any ExerciseReportRepository) {
        self.repository = repository
    }

    /// Reports nobody has answered yet. Deliberately **not** everything that
    /// is un-resolved: `acknowledged` means a fix is written and waiting on an
    /// install, and counting those as open made the home card read "6 open
    /// reports" while three of the six showed a written resolution (#146).
    var openCount: Int {
        reports.filter { $0.status == .open }.count
    }

    /// Answered, not yet finished. Surfaced separately so the two halves of
    /// the backlog stop being conflated.
    var acknowledgedCount: Int {
        reports.filter { $0.status == .acknowledged }.count
    }

    var visibleReports: [ExerciseReport] {
        reports.filter { statusFilter.includes($0.status) }
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

    // MARK: - Row menu (#154)

    /// The moves out of a status, in menu order. Delete is always last
    /// (UI-P6), and the view confirms it before calling `perform`.
    static func actions(for status: ReportStatus) -> [ReportRowAction] {
        switch status {
        case .open: [.acknowledge, .resolve, .delete]
        case .acknowledged: [.resolve, .reopen, .delete]
        case .resolved: [.reopen, .delete]
        }
    }

    func perform(_ action: ReportRowAction, on report: ExerciseReport) async {
        switch action {
        case .acknowledge: await setStatus(.acknowledged, for: report)
        case .resolve: await setStatus(.resolved, for: report)
        case .reopen: await setStatus(.open, for: report)
        case .delete: await delete(report)
        }
    }
}

/// One entry in a report row's menu and swipe actions (#154). The swipe stays
/// as the quick path; the menu makes the same actions visible (UI-P7).
enum ReportRowAction: String, CaseIterable, Identifiable, Sendable {
    case acknowledge, resolve, reopen, delete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .acknowledge: "Acknowledge"
        case .resolve: "Resolve"
        case .reopen: "Reopen"
        case .delete: "Delete"
        }
    }

    var systemImage: String {
        switch self {
        case .acknowledge: "checkmark.bubble"
        case .resolve: "checkmark.circle"
        case .reopen: "arrow.uturn.backward"
        case .delete: "trash"
        }
    }

    var isDestructive: Bool { self == .delete }
}

extension ReportStatus {
    /// The status capsule's text. Acknowledged means a fix is written and
    /// waiting on an install, so it says that rather than "Acknowledged".
    var badgeTitle: String {
        switch self {
        case .open: "Open"
        case .acknowledged: "Fixed – awaiting install"
        case .resolved: "Resolved"
        }
    }
}
