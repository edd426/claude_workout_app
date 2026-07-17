import Foundation
import SwiftData

@MainActor
protocol BodyWeightRepository {
    func fetchAll() async throws -> [BodyWeightEntry]
    func fetchLatest() async throws -> BodyWeightEntry?
    func fetchRange(from start: Date, to end: Date) async throws -> [BodyWeightEntry]
    func fetchPending() async throws -> [BodyWeightEntry]
    func exists(healthKitSampleUUID: UUID) async throws -> Bool
    func save(_ entry: BodyWeightEntry) async throws
    func delete(_ entry: BodyWeightEntry) async throws
}

@MainActor
final class SwiftDataBodyWeightRepository: BodyWeightRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() async throws -> [BodyWeightEntry] {
        let descriptor = FetchDescriptor<BodyWeightEntry>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetchLatest() async throws -> BodyWeightEntry? {
        var descriptor = FetchDescriptor<BodyWeightEntry>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchRange(from start: Date, to end: Date) async throws -> [BodyWeightEntry] {
        let descriptor = FetchDescriptor<BodyWeightEntry>(
            predicate: #Predicate { $0.recordedAt >= start && $0.recordedAt <= end },
            sortBy: [SortDescriptor(\.recordedAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    func fetchPending() async throws -> [BodyWeightEntry] {
        let pendingRaw = SyncStatus.pending.rawValue
        let descriptor = FetchDescriptor<BodyWeightEntry>(
            predicate: #Predicate { $0.syncStatusRaw == pendingRaw }
        )
        return try context.fetch(descriptor)
    }

    func exists(healthKitSampleUUID: UUID) async throws -> Bool {
        let descriptor = FetchDescriptor<BodyWeightEntry>(
            predicate: #Predicate { $0.healthKitSampleUUID == healthKitSampleUUID }
        )
        return try !context.fetch(descriptor).isEmpty
    }

    func save(_ entry: BodyWeightEntry) async throws {
        context.insert(entry)
        try context.save()
    }

    func delete(_ entry: BodyWeightEntry) async throws {
        context.delete(entry)
        try context.save()
    }
}
