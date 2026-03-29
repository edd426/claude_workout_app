import Testing
import Foundation
@testable import ClaudeLifter

@Suite("WeightUnit Tests")
struct WeightUnitTests {
    @Test("WeightUnit has kg and lbs cases")
    func cases() {
        let kg = WeightUnit.kg
        let lbs = WeightUnit.lbs
        #expect(kg != lbs)
    }

    @Test("WeightUnit raw values are strings")
    func rawValues() {
        #expect(WeightUnit.kg.rawValue == "kg")
        #expect(WeightUnit.lbs.rawValue == "lbs")
    }

    @Test("WeightUnit is Codable")
    func codable() throws {
        let encoded = try JSONEncoder().encode(WeightUnit.kg)
        let decoded = try JSONDecoder().decode(WeightUnit.self, from: encoded)
        #expect(decoded == WeightUnit.kg)
    }

    @Test("kg to lbs conversion factor")
    func kgToLbsFactor() {
        #expect(abs(WeightUnit.kg.conversionFactor(to: .lbs) - 2.20462) < 0.001)
    }

    @Test("lbs to kg conversion factor")
    func lbsToKgFactor() {
        #expect(abs(WeightUnit.lbs.conversionFactor(to: .kg) - 0.453592) < 0.001)
    }

    @Test("same unit conversion factor is 1")
    func sameUnitFactor() {
        #expect(WeightUnit.kg.conversionFactor(to: .kg) == 1.0)
        #expect(WeightUnit.lbs.conversionFactor(to: .lbs) == 1.0)
    }

    @Test("convert 100kg to lbs", arguments: [
        (100.0, WeightUnit.kg, WeightUnit.lbs, 220.462),
        (220.462, WeightUnit.lbs, WeightUnit.kg, 100.0),
        (60.0, WeightUnit.kg, WeightUnit.kg, 60.0),
    ])
    func convert(value: Double, from: WeightUnit, to: WeightUnit, expected: Double) {
        let result = from.convert(value, to: to)
        #expect(abs(result - expected) < 0.1)
    }
}

@Suite("SyncStatus Tests")
struct SyncStatusTests {
    @Test("SyncStatus has pending and synced cases")
    func cases() {
        #expect(SyncStatus.pending != SyncStatus.synced)
    }

    @Test("SyncStatus is Codable")
    func codable() throws {
        let encoded = try JSONEncoder().encode(SyncStatus.pending)
        let decoded = try JSONDecoder().decode(SyncStatus.self, from: encoded)
        #expect(decoded == SyncStatus.pending)
    }
}

@Suite("MessageRole Tests")
struct MessageRoleTests {
    @Test("MessageRole has user, assistant, system cases")
    func cases() {
        let roles: [MessageRole] = [.user, .assistant, .system]
        #expect(roles.count == 3)
        #expect(roles[0] != roles[1])
    }

    @Test("MessageRole is Codable")
    func codable() throws {
        let encoded = try JSONEncoder().encode(MessageRole.assistant)
        let decoded = try JSONDecoder().decode(MessageRole.self, from: encoded)
        #expect(decoded == MessageRole.assistant)
    }
}

@Suite("InsightType Tests")
struct InsightTypeTests {
    @Test("InsightType has suggestion, warning, encouragement cases")
    func cases() {
        let types: [InsightType] = [.suggestion, .warning, .encouragement]
        #expect(types.count == 3)
        #expect(types[0] != types[1])
    }

    @Test("InsightType is Codable")
    func codable() throws {
        let encoded = try JSONEncoder().encode(InsightType.warning)
        let decoded = try JSONDecoder().decode(InsightType.self, from: encoded)
        #expect(decoded == InsightType.warning)
    }
}
