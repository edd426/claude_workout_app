import Testing
import Foundation
@testable import ClaudeLifter

@Suite("SettingsViewModel Tests")
@MainActor
struct SettingsViewModelTests {

    @Test("default weightUnit is kg")
    func defaultWeightUnitIsKg() {
        let settings = SettingsManager(defaults: makeFreshDefaults())
        let vm = SettingsViewModel(settingsManager: settings)
        #expect(vm.weightUnit == .kg)
    }

    @Test("setting weightUnit persists via settingsManager")
    func setWeightUnitPersists() {
        let defaults = makeFreshDefaults()
        let settings = SettingsManager(defaults: defaults)
        let vm = SettingsViewModel(settingsManager: settings)

        vm.weightUnit = .lbs

        let settings2 = SettingsManager(defaults: defaults)
        #expect(settings2.weightUnit == .lbs)
    }

    @Test("default aiModel is haiku")
    func defaultAiModelIsHaiku() {
        let settings = SettingsManager(defaults: makeFreshDefaults())
        let vm = SettingsViewModel(settingsManager: settings)
        #expect(vm.aiModel == AIModel.haiku)
    }

    @Test("setting aiModel persists")
    func setAiModelPersists() {
        let defaults = makeFreshDefaults()
        let settings = SettingsManager(defaults: defaults)
        let vm = SettingsViewModel(settingsManager: settings)

        vm.aiModel = .sonnet

        let settings2 = SettingsManager(defaults: defaults)
        #expect(settings2.aiModel == .sonnet)
    }

    @Test("apiKey can be set and read")
    func apiKeyCanBeSetAndRead() {
        let defaults = makeFreshDefaults()
        let settings = SettingsManager(defaults: defaults)
        let vm = SettingsViewModel(settingsManager: settings)

        vm.apiKey = "sk-ant-test123"

        let settings2 = SettingsManager(defaults: defaults)
        #expect(settings2.apiKey == "sk-ant-test123")
    }

    private func makeFreshDefaults() -> UserDefaults {
        let name = UUID().uuidString
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
}
