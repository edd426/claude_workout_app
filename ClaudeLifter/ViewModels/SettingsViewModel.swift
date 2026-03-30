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
    // @needs:ui-viewmodels — serverURL added here to support Phase 2 proxy selection
    var serverURL: String {
        didSet { settingsManager.serverURL = serverURL }
    }

    let availableModels = AIModel.allCases

    private let settingsManager: SettingsManager

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        self.weightUnit = settingsManager.weightUnit
        self.aiModel = settingsManager.aiModel
        self.apiKey = settingsManager.apiKey
        self.serverURL = settingsManager.serverURL
    }
}
