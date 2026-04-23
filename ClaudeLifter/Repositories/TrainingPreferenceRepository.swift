import Foundation
import SwiftData

@MainActor
protocol TrainingPreferenceRepository {
    func fetchAll() async throws -> [TrainingPreference]
    func fetch(id: UUID) async throws -> TrainingPreference?
    func upsert(key: String, value: String, source: String?) async throws
    func delete(key: String) async throws
    func fetchPending() async throws -> [TrainingPreference]
}

@MainActor
final class SwiftDataTrainingPreferenceRepository: TrainingPreferenceRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() async throws -> [TrainingPreference] {
        let descriptor = FetchDescriptor<TrainingPreference>(
            sortBy: [SortDescriptor(\.key)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(id: UUID) async throws -> TrainingPreference? {
        let descriptor = FetchDescriptor<TrainingPreference>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func upsert(key: String, value: String, source: String?) async throws {
        let descriptor = FetchDescriptor<TrainingPreference>(
            predicate: #Predicate { $0.key == key }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.value = value
            existing.source = source
            existing.updatedAt = .now
            existing.recordChange()
        } else {
            let pref = TrainingPreference(key: key, value: value, source: source)
            context.insert(pref)
        }
        try context.save()
    }

    func delete(key: String) async throws {
        let descriptor = FetchDescriptor<TrainingPreference>(
            predicate: #Predicate { $0.key == key }
        )
        let matches = try context.fetch(descriptor)
        for pref in matches {
            context.delete(pref)
        }
        try context.save()
    }

    func fetchPending() async throws -> [TrainingPreference] {
        let pendingRaw = SyncStatus.pending.rawValue
        let descriptor = FetchDescriptor<TrainingPreference>(
            predicate: #Predicate { $0.syncStatusRaw == pendingRaw }
        )
        return try context.fetch(descriptor)
    }
}
