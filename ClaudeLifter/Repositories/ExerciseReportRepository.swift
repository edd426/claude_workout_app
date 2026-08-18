import Foundation
import SwiftData

@MainActor
protocol ExerciseReportRepository {
    func fetchAll() async throws -> [ExerciseReport]
    func fetch(id: UUID) async throws -> ExerciseReport?
    /// Everything not yet resolved — the backlog the Home badge counts and
    /// `list_exercise_reports` defaults to.
    func fetchOpen() async throws -> [ExerciseReport]
    func fetchPending() async throws -> [ExerciseReport]
    func save(_ report: ExerciseReport) async throws
    func delete(_ report: ExerciseReport) async throws
}

@MainActor
final class SwiftDataExerciseReportRepository: ExerciseReportRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() async throws -> [ExerciseReport] {
        let descriptor = FetchDescriptor<ExerciseReport>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(id: UUID) async throws -> ExerciseReport? {
        let descriptor = FetchDescriptor<ExerciseReport>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func fetchOpen() async throws -> [ExerciseReport] {
        // "Open" is everything that is not resolved — acknowledged reports are
        // still outstanding work, they have only been read.
        let resolvedRaw = ReportStatus.resolved.rawValue
        let descriptor = FetchDescriptor<ExerciseReport>(
            predicate: #Predicate { $0.statusRaw != resolvedRaw },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetchPending() async throws -> [ExerciseReport] {
        let pendingRaw = SyncStatus.pending.rawValue
        let descriptor = FetchDescriptor<ExerciseReport>(
            predicate: #Predicate { $0.syncStatusRaw == pendingRaw }
        )
        return try context.fetch(descriptor)
    }

    func save(_ report: ExerciseReport) async throws {
        context.insert(report)
        try context.save()
    }

    func delete(_ report: ExerciseReport) async throws {
        context.delete(report)
        try context.save()
    }
}
