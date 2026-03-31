import Foundation
import SwiftData

@MainActor
protocol PersonalRecordRepository {
    func fetchAll() async throws -> [PersonalRecord]
    func fetch(exerciseId: UUID) async throws -> [PersonalRecord]
    func fetchByType(exerciseId: UUID, type: PRType) async throws -> [PersonalRecord]
    func save(_ record: PersonalRecord) async throws
}

@MainActor
final class SwiftDataPersonalRecordRepository: PersonalRecordRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() async throws -> [PersonalRecord] {
        let descriptor = FetchDescriptor<PersonalRecord>(
            sortBy: [SortDescriptor(\.achievedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(exerciseId: UUID) async throws -> [PersonalRecord] {
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exerciseId == exerciseId }
        )
        return try context.fetch(descriptor)
    }

    func fetchByType(exerciseId: UUID, type: PRType) async throws -> [PersonalRecord] {
        let typeRawValue = type.rawValue
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exerciseId == exerciseId && $0.type == typeRawValue }
        )
        return try context.fetch(descriptor)
    }

    func save(_ record: PersonalRecord) async throws {
        context.insert(record)
        try context.save()
    }
}
