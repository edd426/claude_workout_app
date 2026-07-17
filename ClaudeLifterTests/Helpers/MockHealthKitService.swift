import Foundation
@testable import ClaudeLifter

@MainActor
final class MockHealthKitService: HealthKitServiceProtocol {
    var isAvailable = true
    var authorizationRequestCount = 0
    var writeBodyMassCalls: [(kilograms: Double, date: Date)] = []
    var writeResultUUID = UUID()
    var writeError: Error?
    var samplesToReturn: [HealthKitBodyMassSample] = []
    var fetchError: Error?

    func requestAuthorization() async throws {
        authorizationRequestCount += 1
    }

    func writeBodyMass(kilograms: Double, date: Date) async throws -> UUID {
        if let writeError { throw writeError }
        writeBodyMassCalls.append((kilograms, date))
        return writeResultUUID
    }

    func fetchNewBodyMassSamples() async throws -> [HealthKitBodyMassSample] {
        if let fetchError { throw fetchError }
        return samplesToReturn
    }
}
