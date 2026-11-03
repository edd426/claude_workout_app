import SwiftUI

/// Card 4 (#164): one row per medication with its last dose and a one-tap
/// Log at the default dose. Generic: the user names every medication.
struct MedicationsSection: View {
    let models: BodyModels
    @State private var showAddSheet = false
    @State private var doseSheetMedicationID: UUID?
    @State private var detailMedicationID: UUID?

    private var vm: MedicationListViewModel { models.medications }

    var body: some View {
        BodyCard(title: "Medications", systemImage: "pills") {
            if !vm.rows.isEmpty {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .frame(minHeight: 44)
                }
                .secondaryActionStyle()
                .accessibilityLabel("Add medication")
                .accessibilityIdentifier("bodyAddMedication")
            }
        } content: {
            content
        }
        .sheet(isPresented: $showAddSheet) {
            MedicationEditorSheet(title: "Add Medication", draft: MedicationDraft()) { draft in
                await vm.addMedication(draft)
            }
        }
        .sheet(item: doseSheetBinding) { medication in
            MedicationDoseSheet(
                title: "Log Dose",
                medicationName: medication.name,
                draft: DoseEntryDraft(newDoseFor: medication, defaultDose: vm.defaultDose(for: medication)),
                showsMakeUsual: true
            ) { draft in
                await vm.logDose(draft, for: medication)
            }
        }
        .navigationDestination(item: detailBinding) { medication in
            MedicationDetailView(vm: models.detailViewModel(for: medication), models: models)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = vm.loadError {
            BodyErrorBanner(message: error) { Task { await vm.load() } }
        } else if !vm.isLoaded {
            BodyLoadingRow(label: "Loading medications…")
        } else if vm.rows.isEmpty {
            ContentUnavailableView {
                Label("No medications", systemImage: "pills")
            } description: {
                Text("Add a medication to log its doses here.")
            } actions: {
                Button("Add medication") { showAddSheet = true }
                    .secondaryActionStyle()
                    .accessibilityIdentifier("bodyAddFirstMedication")
            }
        } else {
            rows
        }
        if let error = vm.actionError {
            BodyErrorBanner(message: error, actionTitle: "OK") { vm.dismissActionError() }
        }
        if !vm.archived.isEmpty {
            Divider()
            NavigationLink {
                ArchivedMedicationsView(models: models)
            } label: {
                BodyDisclosureLabel(title: "Archived", value: "\(vm.archived.count)")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bodyArchivedMedications")
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(vm.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider() }
                MedicationRowView(
                    row: row,
                    undoable: vm.undoable?.medicationID == row.id ? vm.undoable : nil,
                    onOpen: { detailMedicationID = row.id },
                    onLog: { logDefault(row) },
                    onLogDifferent: { doseSheetMedicationID = row.id },
                    onUndo: { Task { await vm.undoLastLog() } },
                    onUndoExpired: { vm.clearUndo() }
                )
            }
        }
    }

    private func logDefault(_ row: MedicationRow) {
        guard let medication = vm.medication(id: row.id) else { return }
        Task {
            // No default yet: ask for the dose instead of guessing one.
            let logged = await vm.logDefaultDose(for: medication)
            if !logged, vm.actionError == nil {
                doseSheetMedicationID = row.id
            }
        }
    }

    private var doseSheetBinding: Binding<Medication?> {
        Binding(
            get: { doseSheetMedicationID.flatMap { vm.medication(id: $0) } },
            set: { doseSheetMedicationID = $0?.id }
        )
    }

    private var detailBinding: Binding<Medication?> {
        Binding(
            get: { detailMedicationID.flatMap { vm.medication(id: $0) } },
            set: { detailMedicationID = $0?.id }
        )
    }
}

/// One medication: name and last dose (opens the detail), the one-tap Log,
/// and a ⋯ menu for a different dose (never swipe-only, UI-P7).
struct MedicationRowView: View {
    let row: MedicationRow
    let undoable: UndoableDose?
    let onOpen: () -> Void
    let onLog: () -> Void
    let onLogDifferent: () -> Void
    let onUndo: () -> Void
    let onUndoExpired: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                summary
                actions
            }
            if let undoable {
                undoBanner(undoable)
            }
        }
    }

    private var summary: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(row.lastDoseText ?? "No doses logged yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the history")
        .accessibilityIdentifier("medicationRow-\(row.name)")
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(action: onLog) {
                Text(row.logTitle)
                    .monospacedDigit()
                    .frame(minHeight: 44)
            }
            .secondaryActionStyle()
            .accessibilityLabel("\(row.logTitle) of \(row.name)")
            .accessibilityIdentifier("logDose-\(row.name)")
            Menu {
                Button("Log a different dose…", systemImage: "square.and.pencil", action: onLogDifferent)
                Button("History and details", systemImage: "clock.arrow.circlepath", action: onOpen)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More for \(row.name)")
            .accessibilityIdentifier("medicationMenu-\(row.name)")
        }
    }

    /// One tap logs; one more undoes it (UI-P6: a reversible action prefers
    /// undo over a confirmation).
    private func undoBanner(_ undoable: UndoableDose) -> some View {
        HStack(spacing: 12) {
            Label(undoable.text, systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(BrandTheme.success)
            Spacer(minLength: 0)
            Button("Undo", action: onUndo)
                .secondaryActionStyle()
                .accessibilityIdentifier("undoDose-\(row.name)")
        }
        .task(id: undoable.doseID) {
            // `try?` is deliberate: the sleep throws only when the task is
            // cancelled (the row went away), and then nothing should expire.
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { onUndoExpired() }
        }
    }
}
