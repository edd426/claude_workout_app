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

    @Test("lastSyncRevision persists across SettingsManager instances")
    func lastSyncRevisionPersists() {
        // Arrange
        let suite = "test-revision-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsManager(defaults: defaults)
        #expect(settings.lastSyncRevision == nil)

        // Act
        settings.lastSyncRevision = 42

        // Assert — a fresh instance reads the persisted value
        let reloaded = SettingsManager(defaults: UserDefaults(suiteName: suite)!)
        #expect(reloaded.lastSyncRevision == 42)
    }

    @Test("snapshot dirty state persists across SettingsManager instances")
    func snapshotDirtyPersists() {
        let suite = "settings-snapshot-dirty-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsManager(defaults: defaults)

        settings.markSnapshotDirty()
        let reloaded = SettingsManager(defaults: UserDefaults(suiteName: suite)!)

        #expect(reloaded.isSnapshotDirty == true)
    }

    @Test("a legacy stored isSnapshotDirty flag survives the upgrade to generations")
    func legacyDirtyFlagMigrates() {
        // A pre-#104 install that was dirty at upgrade time has unpushed state.
        // Reading the new keys and finding nothing must not be read as clean.
        let suite = "settings-legacy-dirty-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "isSnapshotDirty")

        let settings = SettingsManager(defaults: defaults)

        #expect(settings.isSnapshotDirty == true)
    }

    @Test("clearing names the generation it pushed, so a mid-request change stays dirty")
    func cleanUpToStaleGenerationLeavesItDirty() {
        let defaults = UserDefaults(suiteName: "settings-generation-\(UUID())")!
        let settings = SettingsManager(defaults: defaults)

        settings.markSnapshotDirty()
        let inFlight = settings.currentSnapshotGeneration()
        // A custom exercise created while the POST was in flight.
        settings.markSnapshotDirty()
        settings.markSnapshotClean(upTo: inFlight)

        #expect(settings.isSnapshotDirty == true)

        // The next push covers both and does clear it.
        settings.markSnapshotClean(upTo: settings.currentSnapshotGeneration())
        #expect(settings.isSnapshotDirty == false)
    }

    @Test("clearing lastSyncRevision removes the stored value")
    func lastSyncRevisionClears() {
        // Arrange
        let suite = "test-revision-clear-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsManager(defaults: defaults)
        settings.lastSyncRevision = 7

        // Act
        settings.lastSyncRevision = nil

        // Assert
        let reloaded = SettingsManager(defaults: UserDefaults(suiteName: suite)!)
        #expect(reloaded.lastSyncRevision == nil)
    }
}

@Suite("SettingsManager — snapshot dirty generations (#104)")
struct SettingsManagerSnapshotGenerationTests {

    @Test("A phone marked dirty but never cleaned reloads as dirty")
    func dirtyWithoutCleanKeyReloadsDirty() {
        // `didSet` does not fire for init assignments, so the clean key is
        // absent on a phone that has only ever been marked dirty. Reading
        // that as clean would strand unpushed state.
        let suite = "settings-dirty-no-clean-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        SettingsManager(defaults: defaults).markSnapshotDirty()

        let reloaded = SettingsManager(defaults: UserDefaults(suiteName: suite)!)

        #expect(reloaded.isSnapshotDirty == true)
    }

    @Test("A cleared phone reloads clean")
    func cleanedReloadsClean() {
        let suite = "settings-cleaned-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsManager(defaults: defaults)
        settings.markSnapshotDirty()
        settings.markSnapshotClean(upTo: settings.currentSnapshotGeneration())

        let reloaded = SettingsManager(defaults: UserDefaults(suiteName: suite)!)

        #expect(reloaded.isSnapshotDirty == false)
    }

    @Test("A fresh install starts clean")
    func freshInstallIsClean() {
        let settings = SettingsManager(
            defaults: UserDefaults(suiteName: "settings-fresh-\(UUID())")!
        )
        #expect(settings.isSnapshotDirty == false)
    }
}
