import Foundation

enum WeightUnit: String, Codable, CaseIterable, Sendable {
    case kg
    case lbs

    func conversionFactor(to target: WeightUnit) -> Double {
        switch (self, target) {
        case (.kg, .lbs): return 2.20462
        case (.lbs, .kg): return 0.453592
        default: return 1.0
        }
    }

    func convert(_ value: Double, to target: WeightUnit) -> Double {
        value * conversionFactor(to: target)
    }
}
