import Foundation
import SwiftData

@MainActor
protocol TrainingPreferenceRepository {
    func fetchAll() async throws -> [TrainingPreference]
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

    func upsert(key: String, value: String, source: String?) async throws {
        let descriptor = FetchDescriptor<TrainingPreference>(
            predicate: #Predicate { $0.key == key }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.value = value
            existing.source = source
            existing.updatedAt = .now
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
        // SwiftData #Predicate cannot traverse enum .rawValue at runtime,
        // so we use in-memory filtering. Preferences are a small, bounded set.
        let all = try context.fetch(FetchDescriptor<TrainingPreference>())
        return all.filter { $0.syncStatus == .pending }
    }
}
