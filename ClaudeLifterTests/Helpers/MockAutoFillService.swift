import Foundation
@testable import ClaudeLifter

@MainActor
final class MockAutoFillService: AutoFillServiceProtocol {
    var resultByExerciseId: [UUID: AutoFillResult] = [:]
    /// Per-set-index values for autoFillValues. When unset for an exercise,
    /// autoFillValues falls back to replicating resultByExerciseId.
    var valuesByExerciseId: [UUID: [AutoFillResult]] = [:]
    var callCount = 0
    var excludedWorkoutIds: [UUID?] = []
    var errorToThrow: Error? = nil

    func lastPerformed(exerciseId: UUID) async throws -> AutoFillResult? {
        callCount += 1
        if let error = errorToThrow { throw error }
        return resultByExerciseId[exerciseId]
    }

    func autoFillValues(exerciseId: UUID, setCount: Int) async throws -> [AutoFillResult] {
        callCount += 1
        if let error = errorToThrow { throw error }
        return values(exerciseId: exerciseId, setCount: setCount)
    }

    func autoFillValues(
        exerciseId: UUID,
        setCount: Int,
        excludingWorkoutId: UUID?
    ) async throws -> [AutoFillResult] {
        callCount += 1
        excludedWorkoutIds.append(excludingWorkoutId)
        if let error = errorToThrow { throw error }
        return values(exerciseId: exerciseId, setCount: setCount)
    }

    private func values(exerciseId: UUID, setCount: Int) -> [AutoFillResult] {
        guard setCount > 0 else { return [] }
        if let values = valuesByExerciseId[exerciseId], !values.isEmpty {
            return (0..<setCount).map { values[min($0, values.count - 1)] }
        }
        guard let result = resultByExerciseId[exerciseId] else { return [] }
        return Array(repeating: result, count: setCount)
    }
}
