import Foundation
import Testing
@testable import ClaudeLifter

/// Height is a profile setting, not a model (#165): nil until the user sets
/// it, persisted in UserDefaults, and mirrored in the snapshot as a scalar.
@Suite("Height Setting Tests")
struct HeightSettingTests {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "height-test-\(UUID())")!
    }

    @Test("Height is nil until it is set")
    func nilUntilSet() {
        let settings = SettingsManager(defaults: makeDefaults())
        #expect(settings.heightCm == nil)
    }

    @Test("Height persists across SettingsManager instances")
    func persists() {
        let defaults = makeDefaults()
        SettingsManager(defaults: defaults).heightCm = 182.88

        #expect(SettingsManager(defaults: defaults).heightCm == 182.88)
    }

    @Test("Clearing height removes the stored value")
    func clearing() {
        let defaults = makeDefaults()
        let settings = SettingsManager(defaults: defaults)
        settings.heightCm = 180

        settings.heightCm = nil

        #expect(defaults.object(forKey: "heightCm") == nil)
        #expect(SettingsManager(defaults: defaults).heightCm == nil)
    }

    /// Height has no per-record syncStatus, so changing it must set the
    /// durable snapshot trigger itself — otherwise the mirror never hears of it.
    @Test("Changing height marks the snapshot dirty so it pushes")
    func changeMarksSnapshotDirty() {
        let settings = SettingsManager(defaults: makeDefaults())
        #expect(!settings.isSnapshotDirty)

        settings.heightCm = 182.88

        #expect(settings.isSnapshotDirty)
    }

    @Test("Setting the same height again does not mark the snapshot dirty")
    func unchangedHeightIsNotAChange() {
        let settings = SettingsManager(defaults: makeDefaults())
        settings.heightCm = 182.88
        settings.markSnapshotClean(upTo: settings.currentSnapshotGeneration())

        settings.heightCm = 182.88

        #expect(!settings.isSnapshotDirty)
    }
}
