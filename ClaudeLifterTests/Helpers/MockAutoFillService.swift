import Foundation
@testable import ClaudeLifter

final class MockAutoFillService: AutoFillServiceProtocol, @unchecked Sendable {
    var resultByExerciseId: [UUID: AutoFillResult] = [:]
    var callCount = 0
    var errorToThrow: Error? = nil

    func lastPerformed(exerciseId: UUID) async throws -> AutoFillResult? {
        callCount += 1
        if let error = errorToThrow { throw error }
        return resultByExerciseId[exerciseId]
    }
}
