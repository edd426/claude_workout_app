import Foundation
@testable import ClaudeLifter

@MainActor
final class MockTrainingPreferenceRepository: TrainingPreferenceRepository {
    var preferences: [TrainingPreference] = []
    var errorToThrow: Error? = nil

    func fetchAll() async throws -> [TrainingPreference] {
        if let error = errorToThrow { throw error }
        return preferences
    }

    func upsert(key: String, value: String, source: String?) async throws {
        if let error = errorToThrow { throw error }
        if let existing = preferences.first(where: { $0.key == key }) {
            existing.value = value
            existing.source = source
        } else {
            preferences.append(TrainingPreference(key: key, value: value, source: source))
        }
    }

    func delete(key: String) async throws {
        if let error = errorToThrow { throw error }
        preferences.removeAll { $0.key == key }
    }

    func fetchPending() async throws -> [TrainingPreference] {
        if let error = errorToThrow { throw error }
        return preferences.filter { $0.syncStatus == .pending }
    }
}
