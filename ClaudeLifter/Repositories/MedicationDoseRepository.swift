import Foundation
import SwiftData

@MainActor
protocol MedicationDoseRepository {
    /// Every dose, newest-first.
    func fetchAll() async throws -> [MedicationDose]
    func fetch(id: UUID) async throws -> MedicationDose?
    /// One medication's doses, newest-first.
    func fetch(for medication: Medication) async throws -> [MedicationDose]
    /// One medication's doses inside `[start, end]`, oldest-first (chart order).
    func fetch(for medication: Medication, from start: Date, to end: Date) async throws -> [MedicationDose]
    /// Every medication's doses inside `[start, end]`, oldest-first.
    func fetchRange(from start: Date, to end: Date) async throws -> [MedicationDose]
    /// The most recent dose — "log the same as last time".
    func fetchLatest(for medication: Medication) async throws -> MedicationDose?
    func fetchPending() async throws -> [MedicationDose]
    /// Inserts a new dose.
    func save(_ dose: MedicationDose) async throws
    /// Persists edits to an existing dose and marks it for push.
    func update(_ dose: MedicationDose) async throws
    func delete(_ dose: MedicationDose) async throws
}

@MainActor
final class SwiftDataMedicationDoseRepository: MedicationDoseRepository {
    private let context: ModelContext
    /// A deletion leaves no `.pending` row to trigger a push, so the owner
    /// passes `settings.markSnapshotDirty` here (see DependencyContainer).
    private let onDeletion: @MainActor () -> Void

    init(context: ModelContext, onDeletion: @escaping @MainActor () -> Void = {}) {
        self.context = context
        self.onDeletion = onDeletion
    }

    func fetchAll() async throws -> [MedicationDose] {
        let descriptor = FetchDescriptor<MedicationDose>(
            sortBy: [SortDescriptor(\.takenAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(id: UUID) async throws -> MedicationDose? {
        let descriptor = FetchDescriptor<MedicationDose>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    // Per-medication reads go through the relationship rather than a
    // predicate across it: one person's dose history is small, and this
    // avoids depending on optional-chained relationship predicates.
    func fetch(for medication: Medication) async throws -> [MedicationDose] {
        liveDoses(of: medication).sorted { $0.takenAt > $1.takenAt }
    }

    func fetch(for medication: Medication, from start: Date, to end: Date) async throws -> [MedicationDose] {
        liveDoses(of: medication)
            .filter { $0.takenAt >= start && $0.takenAt <= end }
            .sorted { $0.takenAt < $1.takenAt }
    }

    func fetchRange(from start: Date, to end: Date) async throws -> [MedicationDose] {
        let descriptor = FetchDescriptor<MedicationDose>(
            predicate: #Predicate { $0.takenAt >= start && $0.takenAt <= end },
            sortBy: [SortDescriptor(\.takenAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    func fetchLatest(for medication: Medication) async throws -> MedicationDose? {
        liveDoses(of: medication).max { $0.takenAt < $1.takenAt }
    }

    func fetchPending() async throws -> [MedicationDose] {
        let pendingRaw = SyncStatus.pending.rawValue
        let descriptor = FetchDescriptor<MedicationDose>(
            predicate: #Predicate { $0.syncStatusRaw == pendingRaw }
        )
        return try context.fetch(descriptor)
    }

    func save(_ dose: MedicationDose) async throws {
        context.insert(dose)
        try context.save()
    }

    func update(_ dose: MedicationDose) async throws {
        dose.recordChange()
        context.insert(dose)
        try context.save()
    }

    func delete(_ dose: MedicationDose) async throws {
        context.delete(dose)
        try context.save()
        onDeletion()
    }

    private func liveDoses(of medication: Medication) -> [MedicationDose] {
        medication.doses.filter { !$0.isDeleted }
    }
}
