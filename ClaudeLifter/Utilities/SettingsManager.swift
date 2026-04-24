import Foundation
import Observation

enum AIModel: String, CaseIterable, Sendable {
    case haiku = "claude-haiku-4-5-20251001"
    case sonnet = "claude-sonnet-4-6"
    case opus = "claude-opus-4-7"

    /// Short family-plus-version label (e.g. "Haiku 4.5", "Opus 4.7"). Used
    /// in both the Settings picker and the Coach header so the user can
    /// tell at a glance which specific Anthropic version they're chatting
    /// with — not just "Opus" which is ambiguous between versions.
    var displayName: String {
        switch self {
        case .haiku: return "Haiku 4.5 (Fast)"
        case .sonnet: return "Sonnet 4.6 (Balanced)"
        case .opus: return "Opus 4.7 (Powerful)"
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

/// `@Observable` so SwiftUI views that read `settings.aiModel` re-render when
/// the user flips the model in Settings — previously the Coach header didn't
/// update until you sent a message because SettingsManager had no observation
/// plumbing. The stored-property form also means fewer UserDefaults hits per
/// view body evaluation.
@Observable
final class SettingsManager {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keychainKey: String

    private enum Key {
        static let weightUnit = "weightUnit"
        static let aiModel = "aiModel"
        static let apiKey = "apiKey"
        static let serverURL = "serverURL"
        static let lastSyncTimestamp = "lastSyncTimestamp"
        static let proactiveInsightsEnabled = "proactiveInsightsEnabled"
    }

    // MARK: - Observable stored state

    var weightUnit: WeightUnit {
        didSet { defaults.set(weightUnit.rawValue, forKey: Key.weightUnit) }
    }

    var aiModel: AIModel {
        didSet { defaults.set(aiModel.rawValue, forKey: Key.aiModel) }
    }

    var serverURL: String {
        didSet { defaults.set(serverURL, forKey: Key.serverURL) }
    }

    var proactiveInsightsEnabled: Bool {
        didSet { defaults.set(proactiveInsightsEnabled, forKey: Key.proactiveInsightsEnabled) }
    }

    var lastSyncTimestamp: Date? {
        didSet { defaults.set(lastSyncTimestamp, forKey: Key.lastSyncTimestamp) }
    }

    // MARK: - Init (loads from UserDefaults)

    init(defaults: UserDefaults = .standard, keychainKey: String? = nil) {
        self.defaults = defaults
        // Use provided key, or derive from defaults suite for test isolation
        if let keychainKey {
            self.keychainKey = keychainKey
        } else if defaults === UserDefaults.standard {
            self.keychainKey = "anthropic_api_key"
        } else {
            // Non-standard UserDefaults (test) — use UserDefaults for backward compatibility
            self.keychainKey = ""
        }

        self.weightUnit = WeightUnit(rawValue: defaults.string(forKey: Key.weightUnit) ?? "") ?? .kg
        self.aiModel = AIModel(rawValue: defaults.string(forKey: Key.aiModel) ?? "") ?? .haiku
        self.serverURL = defaults.string(forKey: Key.serverURL) ?? ""
        self.lastSyncTimestamp = defaults.object(forKey: Key.lastSyncTimestamp) as? Date
        // Missing key → treat as enabled (legacy install default).
        if defaults.object(forKey: Key.proactiveInsightsEnabled) == nil {
            self.proactiveInsightsEnabled = true
        } else {
            self.proactiveInsightsEnabled = defaults.bool(forKey: Key.proactiveInsightsEnabled)
        }
    }

    // MARK: - apiKey (keychain-backed, kept as computed to preserve the
    // UserDefaults → Keychain migration and to avoid mirroring secrets into
    // @Observable state)

    var apiKey: String {
        get {
            access(keyPath: \.apiKey)
            // Test mode: use UserDefaults (backward compatible)
            guard !keychainKey.isEmpty else {
                return defaults.string(forKey: Key.apiKey) ?? ""
            }
            // Production: migrate from UserDefaults to Keychain on first read
            if let legacy = defaults.string(forKey: Key.apiKey), !legacy.isEmpty {
                KeychainHelper.write(key: keychainKey, value: legacy)
                defaults.removeObject(forKey: Key.apiKey)
            }
            return KeychainHelper.read(key: keychainKey) ?? ""
        }
        set {
            withMutation(keyPath: \.apiKey) {
                guard !keychainKey.isEmpty else {
                    defaults.set(newValue, forKey: Key.apiKey)
                    return
                }
                KeychainHelper.write(key: keychainKey, value: newValue)
            }
        }
    }
}
