import SwiftUI

/// Log a dose other than the default, or edit a logged one (#164). Fitted,
/// focused on the amount, with a keyboard Done (UI-P4).
struct MedicationDoseSheet: View {
    let title: String
    let medicationName: String
    @State var draft: DoseEntryDraft
    let showsMakeUsual: Bool
    let onSave: (DoseEntryDraft) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var saveFailed = false
    @FocusState private var amountFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    amountRow
                    if let mgText = draft.computedMgText {
                        Text(mgText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .accessibilityIdentifier("doseComputedMg")
                    }
                } header: {
                    Text(medicationName)
                }
                Section {
                    DatePicker("Taken", selection: $draft.takenAt, in: ...Date.now)
                    TextField("Note (optional)", text: $draft.note, axis: .vertical)
                }
                if showsMakeUsual {
                    Section {
                        Toggle("Make this the usual dose", isOn: $draft.makeUsual)
                    } footer: {
                        Text("The usual dose is what Log logs in one tap.")
                    }
                }
                if saveFailed {
                    Text("Couldn't save the dose. Try again.")
                        .font(.subheadline)
                        .foregroundStyle(BrandTheme.destructive)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!draft.isValid || isSaving)
                        .accessibilityIdentifier("saveDose")
                }
                KeyboardDoneItem(identifier: "doseKeyboardDone") { amountFocused = false }
            }
            .focusAfterPresentation { amountFocused = true }
        }
        .quickEntryDetents(height: showsMakeUsual ? 470 : 400)
    }

    private var amountRow: some View {
        HStack(spacing: 12) {
            TextField("Dose", text: $draft.amountText)
                .keyboardType(.decimalPad)
                .focused($amountFocused)
                .font(.title3)
                .monospacedDigit()
                .accessibilityIdentifier("doseAmountField")
            if draft.allowedUnits.count > 1 {
                Picker("Unit", selection: $draft.unit) {
                    ForEach(draft.allowedUnits) { Text($0.symbol).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            } else {
                Text(draft.unit.symbol)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        isSaving = true
        saveFailed = false
        Task {
            if await onSave(draft) {
                dismiss()
            } else {
                saveFailed = true
            }
            isSaving = false
        }
    }
}

/// Add or edit a medication (#164): a name the user chooses, the dose unit,
/// an optional usual dose, a tablet strength, and an optional concentration,
/// typed or worked out from a mixed vial.
struct MedicationEditorSheet: View {
    let title: String
    @State var draft: MedicationDraft
    let onSave: (MedicationDraft) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var saveFailed = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case name, dose, strength, concentration, vial, diluent }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .focused($focus, equals: .name)
                        .accessibilityIdentifier("medicationNameField")
                } footer: {
                    Text("Any name you like.")
                }
                doseSection
                if draft.unit.takesConcentration {
                    concentrationSection
                }
                if saveFailed {
                    Text(draft.validationMessage ?? "Couldn't save the medication. Try again.")
                        .font(.subheadline)
                        .foregroundStyle(BrandTheme.destructive)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!draft.isValid || isSaving)
                        .accessibilityIdentifier("saveMedication")
                }
                KeyboardDoneItem(identifier: "medicationKeyboardDone") { focus = nil }
            }
            .focusAfterPresentation { focus = .name }
        }
        .presentationDetents([.large])
    }

    private var doseSection: some View {
        Section {
            Picker("Unit", selection: $draft.unit) {
                ForEach(MedicationUnitChoice.allCases) { Text($0.label).tag($0) }
            }
            .accessibilityIdentifier("medicationUnitPicker")
            numberField("Usual dose", text: $draft.usualDoseText, unit: draft.unit.doseUnit.symbol, field: .dose)
            if draft.unit == .tablets {
                numberField("Strength (optional)", text: $draft.tabletStrengthText, unit: "mg each", field: .strength)
            }
        } header: {
            Text("Dose")
        } footer: {
            if let preview = draft.dosePreview, !draft.unit.takesConcentration {
                Text(preview).monospacedDigit()
            } else {
                Text("Log logs the usual dose in one tap. You can change it each time.")
            }
        }
    }

    private var concentrationSection: some View {
        Section {
            Picker("Concentration", selection: $draft.concentrationMode) {
                ForEach(ConcentrationMode.allCases) { Text($0.label).tag($0) }
            }
            .accessibilityIdentifier("concentrationModePicker")
            switch draft.concentrationMode {
            case .none:
                EmptyView()
            case .direct:
                numberField("Concentration", text: $draft.concentrationText, unit: "mg/mL", field: .concentration)
            case .vialMix:
                numberField("Amount in the vial", text: $draft.vialAmountText, unit: "mg", field: .vial)
                numberField("Liquid added", text: $draft.diluentText, unit: "mL", field: .diluent)
            }
        } header: {
            Text("Concentration (optional)")
        } footer: {
            if let preview = draft.dosePreview {
                Text(preview).monospacedDigit()
            } else {
                Text("With a concentration, a dose in mL also shows its mg.")
            }
        }
    }

    private func numberField(_ title: String, text: Binding<String>, unit: String, field: Field) -> some View {
        HStack(spacing: 8) {
            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .focused($focus, equals: field)
                .monospacedDigit()
                .accessibilityLabel(title)
                .accessibilityIdentifier("medicationField-\(title)")
            Text(unit)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private func save() {
        isSaving = true
        saveFailed = false
        Task {
            if await onSave(draft) {
                dismiss()
            } else {
                saveFailed = true
            }
            isSaving = false
        }
    }
}
