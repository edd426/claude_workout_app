import Foundation
import SwiftData

@MainActor
protocol MedicationRepository {
    /// Every medication, archived included, by name.
    func fetchAll() async throws -> [Medication]
    /// Not archived, by name — what the quick-log picker offers.
    func fetchActive() async throws -> [Medication]
    func fetch(id: UUID) async throws -> Medication?
    func fetchPending() async throws -> [Medication]
    /// Inserts a new medication.
    func save(_ medication: Medication) async throws
    /// Persists edits to an existing medication and marks it for push.
    func update(_ medication: Medication) async throws
    /// Hides it from the quick-log picker. Its dose history is untouched.
    func archive(_ medication: Medication) async throws
    func unarchive(_ medication: Medication) async throws
    /// Restore only — the UI archives. Cascades to the medication's doses.
    func delete(_ medication: Medication) async throws
}

@MainActor
final class SwiftDataMedicationRepository: MedicationRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() async throws -> [Medication] {
        let descriptor = FetchDescriptor<Medication>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    func fetchActive() async throws -> [Medication] {
        let descriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(id: UUID) async throws -> Medication? {
        let descriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    func fetchPending() async throws -> [Medication] {
        let pendingRaw = SyncStatus.pending.rawValue
        let descriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.syncStatusRaw == pendingRaw }
        )
        return try context.fetch(descriptor)
    }

    func save(_ medication: Medication) async throws {
        context.insert(medication)
        try context.save()
    }

    func update(_ medication: Medication) async throws {
        medication.recordChange()
        context.insert(medication)
        try context.save()
    }

    func archive(_ medication: Medication) async throws {
        medication.isArchived = true
        try await update(medication)
    }

    func unarchive(_ medication: Medication) async throws {
        medication.isArchived = false
        try await update(medication)
    }

    func delete(_ medication: Medication) async throws {
        context.delete(medication)
        try context.save()
    }
}
