import Foundation
import Observation

/// One medication on the Body tab's Medications card.
struct MedicationRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    /// "0.25 mL (2.5 mg) · yesterday 21:10", nil before the first dose.
    let lastDoseText: String?
    /// What one tap logs; nil means the button asks for a dose instead.
    let defaultDose: UsualDose?
    /// "Log 0.25 mL", or "Log dose" when there is no default yet.
    let logTitle: String
}

/// A dose logged by one tap, kept briefly so it can be undone (UI-P6).
struct UndoableDose: Equatable, Sendable {
    let doseID: UUID
    let medicationID: UUID
    let text: String
}

/// Drives the Medications card (#164): several user-named medications, each
/// with its last dose and a one-tap Log at its default dose. Generic by
/// design: nothing here knows or suggests what a medication is.
@Observable
@MainActor
final class MedicationListViewModel {
    private let medicationRepository: any MedicationRepository
    private let doseRepository: any MedicationDoseRepository
    private let usualDoses: any MedicationUsualDoseStoring
    private let formatter: MedicationDoseFormatter
    private let now: () -> Date

    private(set) var medications: [Medication] = []
    private(set) var archived: [Medication] = []
    private(set) var rows: [MedicationRow] = []
    private(set) var isLoaded = false
    /// The list could not be read: shown with Retry.
    private(set) var loadError: String?
    /// An action failed: shown until dismissed or the next action succeeds.
    private(set) var actionError: String?
    private(set) var undoable: UndoableDose?
    private var lastDoses: [UUID: MedicationDose] = [:]

    init(
        medicationRepository: any MedicationRepository,
        doseRepository: any MedicationDoseRepository,
        usualDoses: any MedicationUsualDoseStoring,
        formatter: MedicationDoseFormatter = MedicationDoseFormatter(),
        now: @escaping () -> Date = { .now }
    ) {
        self.medicationRepository = medicationRepository
        self.doseRepository = doseRepository
        self.usualDoses = usualDoses
        self.formatter = formatter
        self.now = now
    }

    func load() async {
        do {
            let all = try await medicationRepository.fetchAll()
            medications = all.filter { !$0.isArchived }
            archived = all.filter(\.isArchived)
            var latest: [UUID: MedicationDose] = [:]
            for medication in medications {
                latest[medication.id] = try await doseRepository.fetchLatest(for: medication)
            }
            lastDoses = latest
            loadError = nil
        } catch {
            loadError = "Couldn't load your medications."
        }
        rebuildRows()
        isLoaded = true
    }

    func medication(id: UUID) -> Medication? {
        medications.first { $0.id == id } ?? archived.first { $0.id == id }
    }

    func lastDose(for medication: Medication) -> MedicationDose? {
        lastDoses[medication.id]
    }

    func defaultDose(for medication: Medication) -> UsualDose? {
        medication.resolvedDefaultDose(
            usual: usualDoses.usualDose(for: medication.id),
            lastDose: lastDoses[medication.id]
        )
    }

    // MARK: - Logging

    /// One tap: logs the default dose now. False when there is no default,
    /// in which case the caller opens the dose sheet.
    @discardableResult
    func logDefaultDose(for medication: Medication) async -> Bool {
        guard let dose = defaultDose(for: medication) else { return false }
        return await log(amount: dose.amount, unit: dose.unit, for: medication, takenAt: now(), note: nil, makeUsual: true)
    }

    /// Logs a dose from the sheet. `makeUsual` makes it the one-tap default.
    @discardableResult
    func logDose(_ draft: DoseEntryDraft, for medication: Medication) async -> Bool {
        guard let amount = draft.amount else {
            actionError = "Enter a dose above zero."
            return false
        }
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return await log(
            amount: amount, unit: draft.unit, for: medication,
            takenAt: draft.takenAt, note: note.isEmpty ? nil : note,
            makeUsual: draft.makeUsual
        )
    }

    private func log(
        amount: Double, unit: DoseUnit, for medication: Medication,
        takenAt: Date, note: String?, makeUsual: Bool
    ) async -> Bool {
        let dose = MedicationDose(logging: amount, unit: unit, of: medication, takenAt: takenAt, note: note)
        do {
            try await doseRepository.save(dose)
        } catch {
            actionError = "Couldn't log that dose. Try again."
            return false
        }
        actionError = nil
        if makeUsual {
            usualDoses.setUsualDose(UsualDose(amount: amount, unit: unit), for: medication.id)
        }
        await load()
        undoable = UndoableDose(
            doseID: dose.id,
            medicationID: medication.id,
            text: "Logged \(formatter.amount(of: dose))"
        )
        return true
    }

    /// Deletes the dose the last one-tap logged.
    func undoLastLog() async {
        guard let undoable else { return }
        self.undoable = nil
        do {
            if let dose = try await doseRepository.fetch(id: undoable.doseID) {
                try await doseRepository.delete(dose)
            }
            actionError = nil
        } catch {
            actionError = "Couldn't undo that dose. Delete it from the medication's history."
        }
        await load()
    }

    /// Hides the Undo once its moment has passed.
    func clearUndo() {
        undoable = nil
    }

    func dismissActionError() {
        actionError = nil
    }

    // MARK: - Medications

    /// Saves a new medication and its usual dose. False when the draft is
    /// invalid or the save fails.
    @discardableResult
    func addMedication(_ draft: MedicationDraft) async -> Bool {
        guard let medication = draft.makeMedication(now: now()) else {
            actionError = draft.validationMessage
            return false
        }
        do {
            try await medicationRepository.save(medication)
        } catch {
            actionError = "Couldn't save that medication. Try again."
            return false
        }
        actionError = nil
        usualDoses.setUsualDose(draft.usualDose, for: medication.id)
        await load()
        return true
    }

    func archive(_ medication: Medication) async {
        do {
            try await medicationRepository.archive(medication)
            actionError = nil
        } catch {
            actionError = "Couldn't archive that medication."
        }
        await load()
    }

    func unarchive(_ medication: Medication) async {
        do {
            try await medicationRepository.unarchive(medication)
            actionError = nil
        } catch {
            actionError = "Couldn't restore that medication."
        }
        await load()
    }

    // MARK: - Rows

    private func rebuildRows() {
        let current = now()
        rows = medications.map { medication in
            let dose = defaultDose(for: medication)
            return MedicationRow(
                id: medication.id,
                name: medication.name,
                lastDoseText: lastDoses[medication.id].map { formatter.summary(of: $0, now: current) },
                defaultDose: dose,
                logTitle: dose.map { "Log \(formatter.amount($0.amount, unit: $0.unit))" } ?? "Log dose"
            )
        }
    }
}
