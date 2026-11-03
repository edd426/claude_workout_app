import Foundation
import Observation

/// One logged dose in a medication's history.
struct DoseHistoryRow: Identifiable, Equatable, Sendable {
    let id: UUID
    /// "0.25 mL (2.5 mg)".
    let amountText: String
    /// "yesterday 21:10".
    let whenText: String
    let note: String?
}

/// One point on a medication's history chart.
struct DoseChartPoint: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let value: Double
}

/// Drives a medication's detail screen (#164): the full history newest
/// first, editing and deleting doses, editing the medication, archiving it.
@Observable
@MainActor
final class MedicationDetailViewModel {
    let medication: Medication
    private let medicationRepository: any MedicationRepository
    private let doseRepository: any MedicationDoseRepository
    private let usualDoses: any MedicationUsualDoseStoring
    private let formatter: MedicationDoseFormatter
    private let now: () -> Date

    /// Newest first.
    private(set) var doses: [MedicationDose] = []
    private(set) var rows: [DoseHistoryRow] = []
    private(set) var isLoaded = false
    private(set) var loadError: String?
    private(set) var actionError: String?

    init(
        medication: Medication,
        medicationRepository: any MedicationRepository,
        doseRepository: any MedicationDoseRepository,
        usualDoses: any MedicationUsualDoseStoring,
        formatter: MedicationDoseFormatter = MedicationDoseFormatter(),
        now: @escaping () -> Date = { .now }
    ) {
        self.medication = medication
        self.medicationRepository = medicationRepository
        self.doseRepository = doseRepository
        self.usualDoses = usualDoses
        self.formatter = formatter
        self.now = now
    }

    func load() async {
        do {
            doses = try await doseRepository.fetch(for: medication)
            loadError = nil
        } catch {
            loadError = "Couldn't load this medication's doses."
        }
        let current = now()
        rows = doses.map { dose in
            DoseHistoryRow(
                id: dose.id,
                amountText: formatter.amount(of: dose),
                whenText: formatter.when(dose.takenAt, now: current),
                note: dose.note
            )
        }
        isLoaded = true
    }

    func dose(id: UUID) -> MedicationDose? {
        doses.first { $0.id == id }
    }

    // MARK: - Summary

    var usualDose: UsualDose? {
        medication.resolvedDefaultDose(
            usual: usualDoses.usualDose(for: medication.id),
            lastDose: doses.first
        )
    }

    /// "Usual dose 0.25 mL (2.5 mg)", or a prompt when there is none.
    var usualDoseText: String {
        guard let usual = usualDose else { return "No usual dose yet" }
        let mg = DoseCalculator.computedMg(
            amount: usual.amount, unit: usual.unit,
            tabletStrengthMg: medication.tabletStrengthMg,
            concentrationMgPerMl: medication.effectiveConcentrationMgPerMl
        )
        return "Usual dose \(formatter.amount(usual.amount, unit: usual.unit, computedMg: mg))"
    }

    /// "5 mg/mL (10 mg in 2 mL)", "50 mg per tablet", or nil.
    var strengthText: String? {
        switch medication.doseForm {
        case .tablet:
            return medication.tabletStrengthMg.map { "\(BodyFormat.number($0, maxFractionDigits: 3)) mg per tablet" }
        case .liquid:
            guard let concentration = medication.effectiveConcentrationMgPerMl else {
                return "No concentration set"
            }
            var text = "\(BodyFormat.number(concentration, maxFractionDigits: 3)) mg/mL"
            if medication.concentrationMgPerMl == nil,
               let vial = medication.vialAmountMg, let diluent = medication.diluentMl {
                text += " (\(BodyFormat.number(vial, maxFractionDigits: 3)) mg in \(BodyFormat.number(diluent, maxFractionDigits: 3)) mL)"
            }
            return text
        case .mass, .units:
            return nil
        }
    }

    // MARK: - Chart

    /// Computed mg when every dose has it, otherwise the amounts in the most
    /// recent dose's unit. Oldest first.
    var chartPoints: [DoseChartPoint] {
        let chronological = doses.reversed()
        if !doses.isEmpty, doses.allSatisfy({ $0.computedMg != nil }) {
            return chronological.compactMap { dose in
                dose.computedMg.map { DoseChartPoint(id: dose.id, date: dose.takenAt, value: $0) }
            }
        }
        guard let unitRaw = doses.first?.unitRaw else { return [] }
        return chronological
            .filter { $0.unitRaw == unitRaw }
            .map { DoseChartPoint(id: $0.id, date: $0.takenAt, value: $0.amount) }
    }

    /// The chart's axis unit: "mg", or the unit plotted instead.
    var chartUnit: String {
        if !doses.isEmpty, doses.allSatisfy({ $0.computedMg != nil }) { return "mg" }
        return doses.first?.unit?.symbol ?? ""
    }

    /// VoiceOver summary for the chart (UI-A4).
    var chartSummary: String {
        let points = chartPoints
        guard let first = points.first, let last = points.last else { return "No doses yet" }
        let since = first.date.formatted(date: .abbreviated, time: .omitted)
        return "\(points.count) doses since \(since). Latest \(BodyFormat.number(last.value, maxFractionDigits: 3)) \(chartUnit)."
    }

    // MARK: - Dose edits

    /// Saves an edited dose. mg recomputes against the dose's snapshot, never
    /// the medication's current concentration.
    @discardableResult
    func update(_ dose: MedicationDose, with draft: DoseEntryDraft) async -> Bool {
        guard let amount = draft.amount else {
            actionError = "Enter a dose above zero."
            return false
        }
        dose.revise(amount: amount, unit: draft.unit)
        dose.takenAt = draft.takenAt
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        dose.note = note.isEmpty ? nil : note
        do {
            try await doseRepository.update(dose)
            actionError = nil
        } catch {
            actionError = "Couldn't save that change. Try again."
            await load()
            return false
        }
        await load()
        return true
    }

    func delete(_ dose: MedicationDose) async {
        do {
            try await doseRepository.delete(dose)
            actionError = nil
        } catch {
            actionError = "Couldn't delete that dose. Try again."
        }
        await load()
    }

    // MARK: - Medication edits

    @discardableResult
    func saveEdits(_ draft: MedicationDraft) async -> Bool {
        guard draft.isValid else {
            actionError = draft.validationMessage
            return false
        }
        draft.apply(to: medication)
        do {
            try await medicationRepository.update(medication)
            actionError = nil
        } catch {
            actionError = "Couldn't save the medication. Try again."
            return false
        }
        usualDoses.setUsualDose(draft.usualDose, for: medication.id)
        await load()
        return true
    }

    func archive() async {
        await setArchived(true)
    }

    func unarchive() async {
        await setArchived(false)
    }

    private func setArchived(_ archived: Bool) async {
        do {
            if archived {
                try await medicationRepository.archive(medication)
            } else {
                try await medicationRepository.unarchive(medication)
            }
            actionError = nil
        } catch {
            actionError = archived ? "Couldn't archive the medication." : "Couldn't restore the medication."
        }
    }

    func dismissActionError() {
        actionError = nil
    }
}
