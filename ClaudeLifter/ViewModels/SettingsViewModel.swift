import Foundation
import Observation

@Observable
@MainActor
final class SettingsViewModel {
    var weightUnit: WeightUnit {
        didSet { settingsManager.weightUnit = weightUnit }
    }
    var aiModel: AIModel {
        didSet { settingsManager.aiModel = aiModel }
    }
    var apiKey: String {
        didSet { settingsManager.apiKey = apiKey }
    }

    let availableModels = AIModel.allCases

    private let settingsManager: SettingsManager

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        self.weightUnit = settingsManager.weightUnit
        self.aiModel = settingsManager.aiModel
        self.apiKey = settingsManager.apiKey
    }
}
