import Foundation
import Testing
@testable import ClaudeLifter

@Suite("MeasurementsViewModel")
@MainActor
struct MeasurementsViewModelTests {
    private struct Setup {
        let vm: MeasurementsViewModel
        let settings: SettingsManager
        let preferences: UserDefaults
        let repository: MockBodyMeasurementRepository
    }

    private func makeSetup(
        heightCm: Double? = nil,
        waists: [(daysAgo: Int, cm: Double)] = [],
        unit: WeightUnit = .kg
    ) -> Setup {
        let repository = MockBodyMeasurementRepository()
        repository.measurements = waists.map {
            BodyMeasurement(site: .waist, valueCm: $0.cm, recordedAt: TrendTestClock.day(-$0.daysAgo))
        }
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "measure-\(UUID())")!)
        settings.weightUnit = unit
        settings.heightCm = heightCm
        let preferences = UserDefaults(suiteName: "measure-prefs-\(UUID())")!
        let vm = MeasurementsViewModel(
            repository: repository,
            settings: settings,
            preferences: preferences,
            calendar: TrendTestClock.calendar,
            now: { TrendTestClock.now }
        )
        return Setup(vm: vm, settings: settings, preferences: preferences, repository: repository)
    }

    // MARK: - Waist-to-height display states

    @Test("Without a height, WHtR asks for it, even with a waist on file")
    func noHeightAsksForHeight() async {
        let setup = makeSetup(heightCm: nil, waists: [(3, 92)])
        await setup.vm.load()

        #expect(setup.vm.waistToHeight == .needsHeight)
        #expect(setup.vm.waistToHeight.text == "Add your height")
        #expect(setup.vm.waistToHeight.bandText == nil)
    }

    @Test("With a height but no waist, WHtR asks for a waist")
    func noWaistAsksForWaist() async {
        let setup = makeSetup(heightCm: 180)
        await setup.vm.load()

        #expect(setup.vm.waistToHeight == .needsWaist)
        #expect(setup.vm.latestWaistText == nil)
    }

    @Test("With both, WHtR shows the ratio against the 0.5 line")
    func bothShowRatio() async {
        let setup = makeSetup(heightCm: 180, waists: [(40, 95), (3, 92)])
        await setup.vm.load()

        // 92 / 180 = 0.5111: the latest waist, not the older one.
        #expect(setup.vm.waistToHeight == .ratio(0.51, .increased))
        #expect(setup.vm.waistToHeight.text == "WHtR 0.51 · aim below 0.5")
        #expect(setup.vm.waistToHeight.bandText == "Increased risk (0.5 to 0.59)")
        #expect(setup.vm.latestWaistText == "92 cm")
        #expect(setup.vm.latestWaistAge == "3 days ago")
    }

    @Test("Below 0.5 reads as under the line")
    func healthyRatio() async {
        let setup = makeSetup(heightCm: 180, waists: [(0, 85)])
        await setup.vm.load()

        #expect(setup.vm.waistToHeight == .ratio(0.47, .healthy))
        #expect(setup.vm.waistToHeight.text == "WHtR 0.47 · below 0.5")
    }

    @Test("The shown ratio is truncated, so 0.49994 never reads as 0.50")
    func ratioTruncates() async {
        let setup = makeSetup(heightCm: 180, waists: [(0, 89.99)])
        await setup.vm.load()

        #expect(setup.vm.waistToHeight == .ratio(0.49, .healthy))
    }

    // MARK: - Height entry

    @Test("5 ft 11 in is stored as cm and shown back as 5 ft 11 in")
    func feetInchesRoundTrip() throws {
        let setup = makeSetup()

        let saved = setup.vm.setHeight(feetText: "5", inchesText: "11")

        #expect(saved)
        let cm = try #require(setup.settings.heightCm)
        #expect(abs(cm - 180.34) < 1e-9)
        #expect(setup.vm.heightStyle == .feetInches)
        #expect(setup.vm.heightText == "5 ft 11 in")
    }

    @Test("180 cm is stored as entered and shows in either style")
    func centimetresEntry() {
        let setup = makeSetup()

        #expect(setup.vm.setHeight(centimetresText: "180"))

        #expect(setup.settings.heightCm == 180)
        #expect(setup.vm.heightText == "180 cm")
        setup.vm.heightStyle = .feetInches
        #expect(setup.vm.heightText == "5 ft 11 in")
    }

    @Test("A comma decimal is accepted for centimetres")
    func commaDecimal() {
        let setup = makeSetup()
        #expect(setup.vm.setHeight(centimetresText: "180,5"))
        #expect(setup.settings.heightCm == 180.5)
    }

    @Test("Unusable heights are rejected and nothing is stored", arguments: [
        ("5", "12"), ("5", "-1"), ("abc", ""), ("5.5", "0"), ("1", "0"), ("", "11"),
    ])
    func invalidFeetInches(feet: String, inches: String) {
        let setup = makeSetup()
        #expect(!setup.vm.setHeight(feetText: feet, inchesText: inches))
        #expect(setup.settings.heightCm == nil)
    }

    @Test("Unusable centimetre heights are rejected", arguments: ["30", "400", "", "abc"])
    func invalidCentimetres(text: String) {
        let setup = makeSetup(heightCm: 175)
        #expect(!setup.vm.setHeight(centimetresText: text))
        #expect(setup.settings.heightCm == 175)
    }

    @Test("Empty inches means 0 in")
    func emptyInches() {
        let setup = makeSetup()
        #expect(setup.vm.setHeight(feetText: "6", inchesText: ""))
        #expect(abs((setup.settings.heightCm ?? 0) - 182.88) < 1e-9)
        #expect(setup.vm.heightText == "6 ft 0 in")
    }

    @Test("The sheet prefills the stored height in either style")
    func prefillFields() {
        let fields = HeightEntry.fields(cm: 180.34, style: .feetInches)
        #expect(fields.first == "5")
        #expect(fields.second == "11")
        #expect(HeightEntry.fields(cm: 180.34, style: .centimetres).first == "180")
    }

    @Test("The style is remembered and defaults from the weight unit")
    func styleDefaultsAndPersists() {
        let imperial = makeSetup(unit: .lbs)
        #expect(imperial.vm.heightStyle == .feetInches)
        let metric = makeSetup(unit: .kg)
        #expect(metric.vm.heightStyle == .centimetres)

        metric.vm.heightStyle = .feetInches
        let reopened = MeasurementsViewModel(
            repository: metric.repository,
            settings: metric.settings,
            preferences: metric.preferences
        )
        #expect(reopened.heightStyle == .feetInches)
    }

    // MARK: - Waist log

    @Test("Logging a waist saves it now, rounded to 0.1 cm, pending for sync")
    func logWaist() async throws {
        let setup = makeSetup(heightCm: 180, waists: [(30, 94)])
        await setup.vm.load()
        #expect(setup.vm.waistPrefill == "94")

        let saved = await setup.vm.logWaist(cm: 92.34)

        #expect(saved)
        let latest = try #require(setup.vm.latestWaist)
        #expect(latest.valueCm == 92.3)
        #expect(latest.recordedAt == TrendTestClock.now)
        #expect(latest.syncStatus == .pending)
        #expect(latest.site == .waist)
        #expect(setup.vm.waistPrefill == "92.3")
        #expect(setup.vm.latestWaistAge == "today")
    }

    @Test("An implausible waist is not saved")
    func logWaistRejectsOutOfRange() async {
        let setup = makeSetup()
        #expect(MeasurementsViewModel.parseWaist("12") == nil)
        #expect(MeasurementsViewModel.parseWaist("88,5") == 88.5)

        let saved = await setup.vm.logWaist(cm: 12)

        #expect(!saved)
        #expect(setup.repository.saveCallCount == 0)
        #expect(setup.vm.entryError == "Enter a waist between 40 and 250 cm.")
    }

    @Test("A failed save reports an error instead of pretending")
    func logWaistSaveFails() async {
        let setup = makeSetup()
        setup.repository.errorToThrow = MockMedicationRepositoryError()

        let saved = await setup.vm.logWaist(cm: 90)

        #expect(!saved)
        #expect(setup.vm.entryError == "Couldn't save that measurement. Try again.")
    }

    @Test("A failed load is an error state, not an empty card")
    func loadFails() async {
        let setup = makeSetup()
        setup.repository.errorToThrow = MockMedicationRepositoryError()

        await setup.vm.load()

        #expect(setup.vm.isLoaded)
        #expect(setup.vm.loadError == "Couldn't load your measurements.")
    }

    // MARK: - Sparkline

    @Test("The sparkline is one mean per month, oldest first, within a year")
    func monthlySparkline() async {
        // TrendTestClock.now is 4 Nov 2026; day -1 is 3 Nov, -3 is 1 Nov.
        let setup = makeSetup(heightCm: 180, waists: [
            (400, 99), (40, 95), (35, 93), (3, 91), (1, 90),
        ])
        await setup.vm.load()

        let points = setup.vm.waistSparkline
        #expect(points.map(\.valueCm) == [94, 90.5])
        #expect(setup.vm.sparklineSummary.contains("2 months"))
    }
}
