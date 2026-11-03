import Foundation
@testable import ClaudeLifter

struct MockMedicationRepositoryError: Error {}

/// A `MedicationRepository` that fails every call, for the error states.
/// Happy-path tests use the real SwiftData repositories in memory, because a
/// dose reaches its medication through a SwiftData relationship.
@MainActor
final class FailingMedicationRepository: MedicationRepository {
    func fetchAll() async throws -> [Medication] { throw MockMedicationRepositoryError() }
    func fetchActive() async throws -> [Medication] { throw MockMedicationRepositoryError() }
    func fetch(id: UUID) async throws -> Medication? { throw MockMedicationRepositoryError() }
    func fetchPending() async throws -> [Medication] { throw MockMedicationRepositoryError() }
    func save(_ medication: Medication) async throws { throw MockMedicationRepositoryError() }
    func update(_ medication: Medication) async throws { throw MockMedicationRepositoryError() }
    func archive(_ medication: Medication) async throws { throw MockMedicationRepositoryError() }
    func unarchive(_ medication: Medication) async throws { throw MockMedicationRepositoryError() }
    func delete(_ medication: Medication) async throws { throw MockMedicationRepositoryError() }
}
