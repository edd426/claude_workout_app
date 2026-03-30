import Foundation

enum AIModel: String, CaseIterable, Sendable {
    case haiku = "claude-haiku-4-5-20251001"
    case sonnet = "claude-sonnet-4-6"
    case opus = "claude-opus-4-6"

    var displayName: String {
        switch self {
        case .haiku: return "Haiku (Fast)"
        case .sonnet: return "Sonnet (Balanced)"
        case .opus: return "Opus (Powerful)"
        }
    }

    var costIndicator: String {
        switch self {
        case .haiku: return "$"
        case .sonnet: return "$$"
        case .opus: return "$$$"
        }
    }
}

final class SettingsManager {
    private let defaults: UserDefaults

    private enum Key {
        static let weightUnit = "weightUnit"
        static let aiModel = "aiModel"
        static let apiKey = "apiKey"
        static let serverURL = "serverURL"
        static let lastSyncTimestamp = "lastSyncTimestamp"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var weightUnit: WeightUnit {
        get {
            guard let raw = defaults.string(forKey: Key.weightUnit),
                  let unit = WeightUnit(rawValue: raw) else { return .kg }
            return unit
        }
        set { defaults.set(newValue.rawValue, forKey: Key.weightUnit) }
    }

    var aiModel: AIModel {
        get {
            guard let raw = defaults.string(forKey: Key.aiModel),
                  let model = AIModel(rawValue: raw) else { return .haiku }
            return model
        }
        set { defaults.set(newValue.rawValue, forKey: Key.aiModel) }
    }

    var apiKey: String {
        get { defaults.string(forKey: Key.apiKey) ?? "" }
        set { defaults.set(newValue, forKey: Key.apiKey) }
    }

    var serverURL: String {
        get { defaults.string(forKey: Key.serverURL) ?? "" }
        set { defaults.set(newValue, forKey: Key.serverURL) }
    }

    var lastSyncTimestamp: Date? {
        get { defaults.object(forKey: Key.lastSyncTimestamp) as? Date }
        set { defaults.set(newValue, forKey: Key.lastSyncTimestamp) }
    }
}
