import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

/// Shared clock and formatter for the medication tests: Wednesday
/// 4 Nov 2026 18:00 UTC, British English: 24-hour times, which iOS 27
/// writes without a leading zero ("8:05").
enum MedicationTestClock {
    static var calendar: Calendar { TrendTestClock.calendar }
    static let now = TrendTestClock.now
    static var formatter: MedicationDoseFormatter {
        MedicationDoseFormatter(calendar: calendar, locale: Locale(identifier: "en_GB"))
    }

    /// `offset` days from today at `hour`:`minute` UTC.
    static func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        TrendTestClock.day(offset, hour: 0).addingTimeInterval(Double(hour * 3_600 + minute * 60))
    }
}

@Suite("MedicationListViewModel")
@MainActor
struct MedicationListViewModelTests {
    private struct Setup {
        // Retained: a context must not outlive its container.
        let container: ModelContainer
        let medications: SwiftDataMedicationRepository
        let doses: SwiftDataMedicationDoseRepository
        let usual: UserDefaultsUsualDoseStore
        let vm: MedicationListViewModel
    }

    private func makeSetup() throws -> Setup {
        let container = try makeTestContainer()
        let context = container.mainContext
        let medications = SwiftDataMedicationRepository(context: context)
        let doses = SwiftDataMedicationDoseRepository(context: context)
        let usual = UserDefaultsUsualDoseStore(defaults: UserDefaults(suiteName: "usual-\(UUID())")!)
        let vm = MedicationListViewModel(
            medicationRepository: medications,
            doseRepository: doses,
            usualDoses: usual,
            formatter: MedicationTestClock.formatter,
            now: { MedicationTestClock.now }
        )
        return Setup(container: container, medications: medications, doses: doses, usual: usual, vm: vm)
    }

    private func tabletDraft(name: String = "Medication A") -> MedicationDraft {
        var draft = MedicationDraft()
        draft.name = name
        draft.unit = .tablets
        draft.usualDoseText = "1"
        draft.tabletStrengthText = "50"
        return draft
    }

    /// A liquid mixed from a vial: 10 mg in 2 mL is 5 mg/mL.
    private func vialDraft(name: String = "Medication B") -> MedicationDraft {
        var draft = MedicationDraft()
        draft.name = name
        draft.unit = .mL
        draft.usualDoseText = "0.25"
        draft.concentrationMode = .vialMix
        draft.vialAmountText = "10"
        draft.diluentText = "2"
        return draft
    }

    // MARK: - Add

    @Test("Adding a medication saves it with its usual dose, ready to log")
    func addMedication() async throws {
        let setup = try makeSetup()

        let added = await setup.vm.addMedication(tabletDraft())

        #expect(added)
        let medication = try #require(setup.vm.medications.first)
        #expect(medication.name == "Medication A")
        #expect(medication.doseForm == .tablet)
        #expect(medication.tabletStrengthMg == 50)
        #expect(setup.usual.usualDose(for: medication.id) == UsualDose(amount: 1, unit: .tablet))
        let row = try #require(setup.vm.rows.first)
        #expect(row.logTitle == "Log 1 tablet")
        #expect(row.lastDoseText == nil)
    }

    @Test("Several medications, each with its own name, sorted by name")
    func severalMedications() async throws {
        let setup = try makeSetup()
        await setup.vm.addMedication(vialDraft(name: "Second"))
        await setup.vm.addMedication(tabletDraft(name: "First"))

        #expect(setup.vm.rows.map(\.name) == ["First", "Second"])
        #expect(setup.vm.rows.map(\.logTitle) == ["Log 1 tablet", "Log 0.25 mL"])
    }

    @Test("A medication without a name is not saved")
    func addRejectsEmptyName() async throws {
        let setup = try makeSetup()
        var draft = tabletDraft()
        draft.name = "   "

        let added = await setup.vm.addMedication(draft)

        #expect(!added)
        #expect(setup.vm.actionError == "Enter a name.")
        #expect(try await setup.medications.fetchAll().isEmpty)
    }

    // MARK: - Log at the default dose

    @Test("One tap logs the default dose now, with its computed mg")
    func logAtDefault() async throws {
        let setup = try makeSetup()
        await setup.vm.addMedication(tabletDraft())
        let medication = try #require(setup.vm.medications.first)

        let logged = await setup.vm.logDefaultDose(for: medication)

        #expect(logged)
        let dose = try #require(try await setup.doses.fetchLatest(for: medication))
        #expect(dose.amount == 1)
        #expect(dose.unit == .tablet)
        #expect(dose.computedMg == 50)
        #expect(dose.takenAt == MedicationTestClock.now)
        #expect(setup.vm.rows.first?.lastDoseText == "1 tablet (50 mg) · today 18:00")
        #expect(setup.vm.undoable?.text == "Logged 1 tablet (50 mg)")
    }

    @Test("With no usual dose and no history, one tap logs nothing and asks for a dose")
    func logWithoutDefault() async throws {
        let setup = try makeSetup()
        var draft = tabletDraft()
        draft.usualDoseText = ""
        await setup.vm.addMedication(draft)
        let medication = try #require(setup.vm.medications.first)
        #expect(setup.vm.rows.first?.logTitle == "Log dose")

        let logged = await setup.vm.logDefaultDose(for: medication)

        #expect(!logged)
        #expect(try await setup.doses.fetch(for: medication).isEmpty)
    }

    @Test("Without a stored usual dose, the last dose logged is the default")
    func lastDoseIsTheFallback() async throws {
        let setup = try makeSetup()
        let medication = Medication(name: "Synced", doseForm: .mass, massUnit: .mcg)
        try await setup.medications.save(medication)
        try await setup.doses.save(MedicationDose(
            logging: 250, unit: .mcg, of: medication, takenAt: MedicationTestClock.at(-1, 21, 10)
        ))
        await setup.vm.load()

        #expect(setup.vm.defaultDose(for: medication) == UsualDose(amount: 250, unit: .mcg))
        #expect(setup.vm.rows.first?.logTitle == "Log 250 mcg")
        #expect(setup.vm.rows.first?.lastDoseText == "250 mcg · yesterday 21:10")
    }

    // MARK: - Log a custom dose

    @Test("A custom dose in mL converts to mg through the vial mix")
    func customDoseThroughReconstitution() async throws {
        let setup = try makeSetup()
        await setup.vm.addMedication(vialDraft())
        let medication = try #require(setup.vm.medications.first)
        #expect(medication.effectiveConcentrationMgPerMl == 5)

        var draft = DoseEntryDraft(
            newDoseFor: medication,
            defaultDose: setup.vm.defaultDose(for: medication),
            now: MedicationTestClock.now
        )
        #expect(draft.amountText == "0.25")
        draft.amountText = "0.5"
        #expect(draft.computedMgText == "= 2.5 mg")

        let logged = await setup.vm.logDose(draft, for: medication)

        #expect(logged)
        let dose = try #require(try await setup.doses.fetchLatest(for: medication))
        #expect(dose.amount == 0.5)
        #expect(dose.unit == .mL)
        #expect(dose.computedMg == 2.5)
        #expect(dose.concentrationMgPerMlAtLog == 5)
        #expect(setup.vm.rows.first?.lastDoseText == "0.5 mL (2.5 mg) · today 18:00")
        // It becomes the dose one tap repeats.
        #expect(setup.vm.rows.first?.logTitle == "Log 0.5 mL")
    }

    @Test("A one-off dose can leave the usual dose alone")
    func oneOffKeepsUsual() async throws {
        let setup = try makeSetup()
        await setup.vm.addMedication(vialDraft())
        let medication = try #require(setup.vm.medications.first)
        var draft = DoseEntryDraft(newDoseFor: medication, defaultDose: nil, now: MedicationTestClock.now)
        draft.amountText = "0,1"
        draft.makeUsual = false

        await setup.vm.logDose(draft, for: medication)

        #expect(setup.vm.rows.first?.logTitle == "Log 0.25 mL")
        #expect(setup.vm.rows.first?.lastDoseText == "0.1 mL (0.5 mg) · today 18:00")
    }

    @Test("Syringe units convert through the same concentration")
    func syringeUnits() async throws {
        let setup = try makeSetup()
        var draft = vialDraft()
        draft.unit = .syringeUnits
        draft.usualDoseText = "25"
        await setup.vm.addMedication(draft)
        let medication = try #require(setup.vm.medications.first)
        #expect(medication.allowedDoseUnits == [.mL, .syringeUnits])

        await setup.vm.logDefaultDose(for: medication)

        let dose = try #require(try await setup.doses.fetchLatest(for: medication))
        #expect(dose.unit == .syringeUnits)
        #expect(dose.computedMg == 1.25)
        #expect(setup.vm.rows.first?.lastDoseText == "25 units (1.25 mg) · today 18:00")
    }

    @Test("Undo removes the dose one tap logged")
    func undo() async throws {
        let setup = try makeSetup()
        await setup.vm.addMedication(tabletDraft())
        let medication = try #require(setup.vm.medications.first)
        await setup.vm.logDefaultDose(for: medication)

        await setup.vm.undoLastLog()

        #expect(try await setup.doses.fetch(for: medication).isEmpty)
        #expect(setup.vm.undoable == nil)
        #expect(setup.vm.rows.first?.lastDoseText == nil)
    }

    // MARK: - Archive

    @Test("Archiving hides a medication from the card and keeps its history")
    func archive() async throws {
        let setup = try makeSetup()
        await setup.vm.addMedication(tabletDraft())
        let medication = try #require(setup.vm.medications.first)
        await setup.vm.logDefaultDose(for: medication)

        await setup.vm.archive(medication)

        #expect(setup.vm.rows.isEmpty)
        #expect(setup.vm.archived.map(\.id) == [medication.id])
        #expect(try await setup.doses.fetch(for: medication).count == 1)

        await setup.vm.unarchive(medication)
        #expect(setup.vm.rows.map(\.id) == [medication.id])
    }

    // MARK: - Errors

    @Test("A failed read is an error state with nothing listed")
    func loadFails() async throws {
        let container = try makeTestContainer()
        let vm = MedicationListViewModel(
            medicationRepository: FailingMedicationRepository(),
            doseRepository: SwiftDataMedicationDoseRepository(context: container.mainContext),
            usualDoses: UserDefaultsUsualDoseStore(defaults: UserDefaults(suiteName: "usual-\(UUID())")!)
        )

        await vm.load()

        #expect(vm.isLoaded)
        #expect(vm.loadError == "Couldn't load your medications.")
        #expect(vm.rows.isEmpty)
    }

    @Test("A failed save says so")
    func addFails() async throws {
        let container = try makeTestContainer()
        let vm = MedicationListViewModel(
            medicationRepository: FailingMedicationRepository(),
            doseRepository: SwiftDataMedicationDoseRepository(context: container.mainContext),
            usualDoses: UserDefaultsUsualDoseStore(defaults: UserDefaults(suiteName: "usual-\(UUID())")!)
        )

        let added = await vm.addMedication(tabletDraft())

        #expect(!added)
        #expect(vm.actionError == "Couldn't save that medication. Try again.")
    }
}

@Suite("Usual dose store")
@MainActor
struct UsualDoseStoreTests {
    @Test("A usual dose survives a new store on the same defaults, and clears")
    func persists() {
        let defaults = UserDefaults(suiteName: "usual-\(UUID())")!
        let id = UUID()
        UserDefaultsUsualDoseStore(defaults: defaults).setUsualDose(UsualDose(amount: 0.25, unit: .mL), for: id)

        let reopened = UserDefaultsUsualDoseStore(defaults: defaults)
        #expect(reopened.usualDose(for: id) == UsualDose(amount: 0.25, unit: .mL))
        #expect(reopened.usualDose(for: UUID()) == nil)

        reopened.setUsualDose(nil, for: id)
        #expect(reopened.usualDose(for: id) == nil)
    }

    @Test("A usual dose in a unit the medication no longer takes is ignored")
    func staleUnitIgnored() {
        let medication = Medication(name: "Edited", doseForm: .tablet, tabletStrengthMg: 10)
        let resolved = medication.resolvedDefaultDose(
            usual: UsualDose(amount: 0.5, unit: .mL),
            lastDose: nil
        )
        #expect(resolved == nil)
    }
}
