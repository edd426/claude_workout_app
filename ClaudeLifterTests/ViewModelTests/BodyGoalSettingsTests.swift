import Foundation
import Testing
@testable import ClaudeLifter

/// The weight-goal rate (#152) and protein multiplier (#111) settings.
@Suite("Body goal settings")
struct BodyGoalSettingsTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "body-goal-\(UUID())")!
    }

    @Test("No weight goal until one is set")
    func goalDefaultsToNil() {
        let settings = SettingsManager(defaults: makeDefaults())

        #expect(settings.weightGoalPercentPerWeek == nil)
    }

    @Test("A signed weight goal persists, and clearing it removes it")
    func goalPersists() {
        let defaults = makeDefaults()
        let settings = SettingsManager(defaults: defaults)

        settings.weightGoalPercentPerWeek = -0.5
        #expect(SettingsManager(defaults: defaults).weightGoalPercentPerWeek == -0.5)

        settings.weightGoalPercentPerWeek = nil
        #expect(SettingsManager(defaults: defaults).weightGoalPercentPerWeek == nil)
    }

    @Test("A maintenance goal of zero is a goal, not no goal")
    func zeroGoalPersists() {
        let defaults = makeDefaults()
        SettingsManager(defaults: defaults).weightGoalPercentPerWeek = 0

        #expect(SettingsManager(defaults: defaults).weightGoalPercentPerWeek == 0)
    }

    @Test("Protein multiplier defaults to 1.6 g/kg")
    func multiplierDefault() {
        #expect(SettingsManager(defaults: makeDefaults()).proteinMultiplier == 1.6)
    }

    @Test("Protein multiplier persists")
    func multiplierPersists() {
        let defaults = makeDefaults()
        SettingsManager(defaults: defaults).proteinMultiplier = 2.0

        #expect(SettingsManager(defaults: defaults).proteinMultiplier == 2.0)
    }

    @Test("A corrupt stored multiplier reads as the default", arguments: [0.0, -1.0, Double.nan])
    func corruptMultiplierUsesDefault(stored: Double) {
        let defaults = makeDefaults()
        defaults.set(stored, forKey: "proteinMultiplier")

        #expect(SettingsManager(defaults: defaults).proteinMultiplier == 1.6)
    }
}
