import Foundation
@testable import ClaudeLifter

@MainActor
final class MockPRDetectionService: PRDetectionServiceProtocol {
    var detectedPRs: [PersonalRecord] = []
    var errorToThrow: Error? = nil
    var detectCallCount = 0

    func detectPRs(for workout: Workout) async throws -> [PersonalRecord] {
        detectCallCount += 1
        if let error = errorToThrow { throw error }
        return detectedPRs
    }

    func getAllPRs(for exerciseId: UUID) async throws -> [PersonalRecord] {
        if let error = errorToThrow { throw error }
        return detectedPRs.filter { $0.exerciseId == exerciseId }
    }
}
