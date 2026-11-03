import Charts
import SwiftUI

/// A medication's full history, newest first, with edit and (confirmed)
/// delete per dose, plus Edit and Archive for the medication (#164).
struct MedicationDetailView: View {
    @State var vm: MedicationDetailViewModel
    let models: BodyModels
    @State private var showEditor = false
    @State private var showLogSheet = false
    @State private var editingDoseID: UUID?
    @State private var pendingDeleteID: UUID?
    /// Bumped on each confirmed delete: the UI-H2 `.warning` haptic.
    @State private var confirmedDeletes = 0

    var body: some View {
        presentations(
            List {
                summarySection
                if vm.chartPoints.count >= 2 {
                    Section("Over time") { DoseHistoryChart(vm: vm) }
                }
                historySection
                archiveSection
            }
            .navigationTitle(vm.medication.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEditor = true }
                        .accessibilityIdentifier("editMedication")
                }
            }
            .task { await vm.load() }
        )
        .sensoryFeedback(.warning, trigger: confirmedDeletes)
    }

    /// The edit sheets and the delete confirmation (UI-P6: irreversible, so
    /// confirmed, destructive first and Cancel last).
    private func presentations(_ content: some View) -> some View {
        content
            .sheet(isPresented: $showEditor) {
                MedicationEditorSheet(
                    title: "Edit Medication",
                    draft: MedicationDraft(medication: vm.medication, usualDose: vm.usualDose)
                ) { draft in
                    await vm.saveEdits(draft)
                }
            }
            .sheet(isPresented: $showLogSheet, onDismiss: { Task { await vm.load() } }) {
                MedicationDoseSheet(
                    title: "Log Dose",
                    medicationName: vm.medication.name,
                    draft: DoseEntryDraft(newDoseFor: vm.medication, defaultDose: vm.usualDose),
                    showsMakeUsual: true
                ) { draft in
                    await models.medications.logDose(draft, for: vm.medication)
                }
            }
            .sheet(item: editingDoseBinding) { dose in
                MedicationDoseSheet(
                    title: "Edit Dose",
                    medicationName: vm.medication.name,
                    draft: DoseEntryDraft(editing: dose, medication: vm.medication),
                    showsMakeUsual: false
                ) { draft in
                    await vm.update(dose, with: draft)
                }
            }
            .confirmationDialog(
                "Delete this dose?",
                isPresented: deleteDialogBinding,
                titleVisibility: .visible,
                presenting: pendingDeleteID.flatMap { id in vm.rows.first { $0.id == id } }
            ) { row in
                Button("Delete Dose", role: .destructive) {
                    guard let dose = vm.dose(id: row.id) else { return }
                    confirmedDeletes += 1
                    Task { await vm.delete(dose) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { row in
                Text("\(row.amountText), \(row.whenText). This can't be undone.")
            }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.usualDoseText)
                    .font(.headline)
                    .monospacedDigit()
                if let strength = vm.strengthText {
                    Text(strength)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if vm.medication.isArchived {
                    Label("Archived", systemImage: "archivebox")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            if !vm.medication.isArchived {
                Button("Log a dose…") { showLogSheet = true }
                    .foregroundStyle(BrandTheme.accentText)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("detailLogDose")
            }
            if let error = vm.actionError {
                BodyErrorBanner(message: error, actionTitle: "OK") { vm.dismissActionError() }
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        Section("History") {
            if let error = vm.loadError {
                BodyErrorBanner(message: error) { Task { await vm.load() } }
            } else if !vm.isLoaded {
                BodyLoadingRow(label: "Loading doses…")
            } else if vm.rows.isEmpty {
                ContentUnavailableView(
                    "No doses yet",
                    systemImage: "clock",
                    description: Text("Doses you log appear here, newest first.")
                )
            } else {
                ForEach(vm.rows) { row in
                    DoseHistoryRowView(
                        row: row,
                        onEdit: { editingDoseID = row.id },
                        onDelete: { pendingDeleteID = row.id }
                    )
                }
            }
        }
    }

    private var archiveSection: some View {
        Section {
            if vm.medication.isArchived {
                Button("Unarchive") { Task { await vm.unarchive() } }
                    .foregroundStyle(BrandTheme.accentText)
                    .accessibilityIdentifier("unarchiveMedication")
            } else {
                Button("Archive") { Task { await vm.archive() } }
                    .foregroundStyle(BrandTheme.accentText)
                    .accessibilityIdentifier("archiveMedication")
            }
        } footer: {
            Text(vm.medication.isArchived
                 ? "Unarchive to show it on the Body tab again."
                 : "Archiving hides it from the Body tab and keeps its history. You can unarchive it.")
        }
    }

    private var editingDoseBinding: Binding<MedicationDose?> {
        Binding(
            get: { editingDoseID.flatMap { vm.dose(id: $0) } },
            set: { editingDoseID = $0?.id }
        )
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteID != nil },
            set: { if !$0 { pendingDeleteID = nil } }
        )
    }
}

/// One dose: amount and time, with a ⋯ menu for Edit and Delete. The swipe
/// is a shortcut only (UI-P7), and never a full swipe (UI-P6).
private struct DoseHistoryRowView: View {
    let row: DoseHistoryRow
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.amountText)
                    .font(.body)
                    .monospacedDigit()
                Text(row.whenText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let note = row.note {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Menu {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More for this dose")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            Button("Edit", systemImage: "pencil", action: onEdit)
        }
    }
}

/// The computed mg (or the amount) over time, with a spoken summary (UI-A4).
private struct DoseHistoryChart: View {
    let vm: MedicationDetailViewModel
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 140

    var body: some View {
        Chart(vm.chartPoints) { point in
            LineMark(x: .value("Date", point.date), y: .value(vm.chartUnit, point.value))
                .foregroundStyle(BrandTheme.accent)
            PointMark(x: .value("Date", point.date), y: .value(vm.chartUnit, point.value))
                .symbolSize(24)
                .foregroundStyle(BrandTheme.accent)
        }
        .chartYAxisLabel(vm.chartUnit)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Doses over time")
        .accessibilityValue(vm.chartSummary)
    }
}

/// Archived medications, each one tap from its history and from Unarchive.
struct ArchivedMedicationsView: View {
    let models: BodyModels

    private var vm: MedicationListViewModel { models.medications }

    var body: some View {
        List {
            if vm.archived.isEmpty {
                ContentUnavailableView(
                    "Nothing archived",
                    systemImage: "archivebox",
                    description: Text("Archived medications appear here with their history.")
                )
            } else {
                ForEach(vm.archived) { medication in
                    NavigationLink {
                        MedicationDetailView(vm: models.detailViewModel(for: medication), models: models)
                    } label: {
                        Text(medication.name)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                }
            }
        }
        .navigationTitle("Archived")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
    }
}
