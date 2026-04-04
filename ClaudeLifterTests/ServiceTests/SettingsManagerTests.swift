import Testing
import Foundation
@testable import ClaudeLifter

@Suite("SettingsManager Tests")
struct SettingsManagerTests {
    @Test("apiKey stores in Keychain not UserDefaults")
    func apiKeyUsesKeychain() {
        let testKey = "test_keychain_\(UUID().uuidString)"
        defer { KeychainHelper.delete(key: testKey) }

        let defaults = UserDefaults(suiteName: "test-settings-\(UUID())")!
        let settings = SettingsManager(defaults: defaults, keychainKey: testKey)

        settings.apiKey = "sk-ant-test-key"

        // Should NOT be in UserDefaults
        #expect(defaults.string(forKey: "apiKey") == nil)

        // Should be readable from SettingsManager
        #expect(settings.apiKey == "sk-ant-test-key")

        // Should be in Keychain under the test key
        #expect(KeychainHelper.read(key: testKey) == "sk-ant-test-key")
    }

    @Test("apiKey migrates from UserDefaults to Keychain on first read")
    func apiKeyMigratesFromUserDefaults() {
        let testKey = "test_migrate_\(UUID().uuidString)"
        defer { KeychainHelper.delete(key: testKey) }

        let defaults = UserDefaults(suiteName: "test-migrate-\(UUID())")!
        // Simulate legacy storage
        defaults.set("sk-legacy-key", forKey: "apiKey")

        let settings = SettingsManager(defaults: defaults, keychainKey: testKey)
        let key = settings.apiKey

        // Should return the migrated value
        #expect(key == "sk-legacy-key")
        // UserDefaults should be cleared
        #expect(defaults.string(forKey: "apiKey") == nil)
        // Should now be in Keychain
        #expect(KeychainHelper.read(key: testKey) == "sk-legacy-key")
    }

    @Test("apiKey returns empty string when nothing stored")
    func apiKeyReturnsEmptyWhenNotSet() {
        let testKey = "test_empty_\(UUID().uuidString)"
        defer { KeychainHelper.delete(key: testKey) }

        let defaults = UserDefaults(suiteName: "test-empty-\(UUID())")!
        let settings = SettingsManager(defaults: defaults, keychainKey: testKey)

        #expect(settings.apiKey == "")
    }
}
