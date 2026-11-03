import Foundation
import SwiftData

@MainActor
protocol BodyMeasurementRepository {
    /// Every measurement, newest-first.
    func fetchAll() async throws -> [BodyMeasurement]
    func fetch(id: UUID) async throws -> BodyMeasurement?
    /// One site, newest-first.
    func fetch(site: MeasurementSite) async throws -> [BodyMeasurement]
    /// One site inside `[start, end]`, oldest-first (chart order).
    func fetch(site: MeasurementSite, from start: Date, to end: Date) async throws -> [BodyMeasurement]
    func fetchLatest(site: MeasurementSite) async throws -> BodyMeasurement?
    /// The most recent measurement of every site that has one.
    func fetchLatestPerSite() async throws -> [MeasurementSite: BodyMeasurement]
    func fetchPending() async throws -> [BodyMeasurement]
    /// Inserts (or re-saves) a measurement. Callers editing an existing one
    /// call `recordChange()` first, as with every syncable model.
    func save(_ measurement: BodyMeasurement) async throws
    func delete(_ measurement: BodyMeasurement) async throws
}

@MainActor
final class SwiftDataBodyMeasurementRepository: BodyMeasurementRepository {
    private let context: ModelContext
    /// A deletion leaves no `.pending` row to trigger a push, so the owner
    /// passes `settings.markSnapshotDirty` here (see DependencyContainer).
    private let onDeletion: @MainActor () -> Void

    init(context: ModelContext, onDeletion: @escaping @MainActor () -> Void = {}) {
        self.context = context
        self.onDeletion = onDeletion
    }

    func fetchAll() async throws -> [BodyMeasurement] {
        let descriptor = FetchDescriptor<BodyMeasurement>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(id: UUID) async throws -> BodyMeasurement? {
        let descriptor = FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func fetch(site: MeasurementSite) async throws -> [BodyMeasurement] {
        let raw = site.rawValue
        let descriptor = FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate { $0.siteRaw == raw },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(site: MeasurementSite, from start: Date, to end: Date) async throws -> [BodyMeasurement] {
        let raw = site.rawValue
        let descriptor = FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate {
                $0.siteRaw == raw && $0.recordedAt >= start && $0.recordedAt <= end
            },
            sortBy: [SortDescriptor(\.recordedAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    func fetchLatest(site: MeasurementSite) async throws -> BodyMeasurement? {
        let raw = site.rawValue
        var descriptor = FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate { $0.siteRaw == raw },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchLatestPerSite() async throws -> [MeasurementSite: BodyMeasurement] {
        var latest: [MeasurementSite: BodyMeasurement] = [:]
        // Newest-first, so the first one seen per site wins. A site this build
        // does not know is skipped rather than guessed at.
        for measurement in try await fetchAll() {
            guard let site = measurement.site, latest[site] == nil else { continue }
            latest[site] = measurement
        }
        return latest
    }

    func fetchPending() async throws -> [BodyMeasurement] {
        let pendingRaw = SyncStatus.pending.rawValue
        let descriptor = FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate { $0.syncStatusRaw == pendingRaw }
        )
        return try context.fetch(descriptor)
    }

    func save(_ measurement: BodyMeasurement) async throws {
        context.insert(measurement)
        try context.save()
    }

    func delete(_ measurement: BodyMeasurement) async throws {
        context.delete(measurement)
        try context.save()
        onDeletion()
    }
}
